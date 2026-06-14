-- LFC Service Class:
-- This class will encapsulate all LFC related functionalities

-- Activation Script (must stay in global scope)
SLASH_ACTIVATE_LFC_DETECTION1 = "/littleshop"
SLASH_ACTIVATE_LFC_PANEL1 = "/showshop"
SlashCmdList["ACTIVATE_LFC_DETECTION"] = function()
    LFC_SERVICE.ActivateService()
end
SlashCmdList["ACTIVATE_LFC_PANEL"] = function()
    LFC_SERVICE.ToggleFrame()
end

LFC_SERVICE = {
    -- Global Variables (member variables)
    WATCHLIST = {},
    MAINFRAME = nil,
    ORDERFRAME = nil,                     -- This will hold the current orders detected in chat
    SOUNDS = { LFC_DETECTED = 120,        -- Sound kit ID for raid warning sound (good for alerts)
    },

    ORDERS = {
        DATA_PROVIDER_ORDERS = CreateDataProvider(),
        GetOrder = function()
            return LFC_SERVICE.ORDERS.DATA_PROVIDER_ORDERS:GetData()
        end,
        AddOrder = function(orderData)
            LFC_SERVICE.ORDERS.DATA_PROVIDER_ORDERS:Insert(orderData)
        end,
        RemoveOrder = function(order)
            LFC_SERVICE.ORDERS.DATA_PROVIDER_ORDERS:RemoveByIndex(order.unique_id) -- Assuming unique_id is used as the index for simplicity
        end,
        ResetOrders = function()
            LFC_SERVICE.ORDERS.DATA_PROVIDER_ORDERS:Flush()
        end


        --[[
            ORDER DATA STRUCTURE:{
            unique_id = "A unique identifier for the order, could be a combination of player name and item ID or a timestamp",
            message = "Full chat message text",
            player = "Name of the player who sent the message",
            item_link = 12345 -- The ID of the item mentioned in the message (if any)
            is_link = true/false -- Whether the message contains an item link
            is_learned = true/false -- Whether the item is in the player's profession watchlist
            is_followed_up = true/false -- Whether the user has already followed up on this order
            is_completed = true/false -- Whether the order has been marked as completed
        }
        ]]

    },

    InitializeFrame = function()
        -- Set titleString
        LFC_SERVICE.MAINFRAME = CreateFrame("Frame", "LFC_Main_Frame", UIParent, "BasicFrameTemplate")
        LFC_SERVICE.MAINFRAME.TitleText:SetText("Little Shop - Your Order Board")
        LFC_SERVICE.MAINFRAME:SetSize(700, 400)
        LFC_SERVICE.MAINFRAME:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

        LFC_SERVICE.MAINFRAME:SetMovable(true)
        LFC_SERVICE.MAINFRAME:EnableMouse(true)
        LFC_SERVICE.MAINFRAME:RegisterForDrag("LeftButton")
        LFC_SERVICE.MAINFRAME:SetScript("OnDragStart", LFC_SERVICE.MAINFRAME.StartMoving)
        LFC_SERVICE.MAINFRAME:SetScript("OnDragStop", LFC_SERVICE.MAINFRAME.StopMovingOrSizing)

        LFC_SERVICE.ORDERFRAME = CreateFrame("Frame", "LFC_Order_Frame", LFC_SERVICE.MAINFRAME, "BackdropTemplate")
        LFC_SERVICE.ORDERFRAME:SetSize(400, 300)
        LFC_SERVICE.ORDERFRAME:SetPoint("TOPLEFT", LFC_SERVICE.MAINFRAME, "TOPLEFT", 10, -30)

        -- ORDERFRAME BACKDROP
        LFC_SERVICE.ORDERFRAME:SetBackdrop({
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
        LFC_SERVICE.ORDERFRAME:SetBackdropColor(0, 0, 0, 0.5)
        -- Gold border, 50% opaque
        LFC_SERVICE.ORDERFRAME:SetBackdropBorderColor(1, 0.8, 0, 0.5)

        -- Element: Scroll Box List
        local scroll_box = CreateFrame("Frame", nil, LFC_SERVICE.ORDERFRAME, "WowScrollBoxList")
        scroll_box:SetPoint("TOPLEFT", LFC_SERVICE.ORDERFRAME, "TOPLEFT", 4, -10)
        scroll_box:SetPoint("BOTTOMRIGHT", LFC_SERVICE.ORDERFRAME, "BOTTOMRIGHT", -22, 0)
        

        -- Element: Scroll Bar
        local scroll_bar = CreateFrame("EventFrame", nil, LFC_SERVICE.ORDERFRAME, "MinimalScrollBar")
        scroll_bar:SetPoint("TOPLEFT", scroll_box, "TOPRIGHT", 4, 0)
        scroll_bar:SetPoint("BOTTOMLEFT", scroll_box, "BOTTOMRIGHT", 4, 10)

        -- Element: Scroll Box List View
        local itemSpacing = 2
        local view = CreateScrollBoxListLinearView(itemSpacing, itemSpacing, itemSpacing, itemSpacing, itemSpacing)
        view:SetElementExtent(20)
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
            button.text:SetText(element.item_link or element.message or "Unknown Order")
            button:SetScript("OnClick", function()
                print("Order from " .. tostring(element.player) .. ": " .. tostring(element.item_link or element.message))
            end)
        end)
        scroll_box:SetDataProvider(LFC_SERVICE.ORDERS.DATA_PROVIDER_ORDERS, ScrollBoxConstants.RetainScrollPosition)
    end,

    InitializeWatchList = function()
        -- This function can be expanded in the future to include more complex logic for populating the watchlist
        LFC_SERVICE.WATCHLIST = LFC_SERVICE.ScanCraftableItems()
    end,

    -- API Functions
    ToggleFrame = function()
        if not LFC_SERVICE.MAINFRAME then
            LFC_SERVICE.InitializeFrame()
        end
        if LFC_SERVICE.MAINFRAME:IsShown() then
            LFC_SERVICE.MAINFRAME:Hide()
        else
            LFC_SERVICE.MAINFRAME:Show()
        end
    end,

    ActivateService = function()
        -- Initialize the frame if it hasn't been created yet
        if not LFC_SERVICE.MAINFRAME then
            LFC_SERVICE.InitializeFrame()
        end

        LFC_SERVICE.MAINFRAME:RegisterEvent("CHAT_MSG_CHANNEL") -- Listens to Trade Chat (/2)
        LFC_SERVICE.MAINFRAME:RegisterEvent("CHAT_MSG_SAY")     -- Listens to normal /say (Great for testing!)
        LFC_SERVICE.MAINFRAME:SetScript("OnEvent", LFC_SERVICE.OnChatDetectedEvent)
        LFC_SERVICE.InitializeWatchList()                       -- Populate the watchlist with the player's current profession recipes
    end,

    OnChatDetectedEvent = function(self, event, ...)
        local message, player_name, _, channel_name, whisper_name = ...
        local is_lfc, has_item, item_id, has_link, item_link, is_learned = LFC_SERVICE.ScanChat(message) -- Pass the chat message to the ScanChat function for processing

        if is_lfc and has_item and is_learned then
            -- Create a data object for the data provider
            local order_data = {
                unique_id = player_name .. "_" .. item_id .. "_" .. time(), -- Example unique ID
                message = message,
                player = player_name,
                item_id = item_id,
                item_link = item_link,
                is_link = has_link,
                is_learned = true,      -- Placeholder, update with actual logic
                is_followed_up = false, -- Placeholder, update with actual logic
                is_completed = false    -- Placeholder, update with actual logic
            }
            LFC_SERVICE.ORDERS.AddOrder(order_data)                                                  -- Add the order data to the provider
            PlaySound(LFC_SERVICE.SOUNDS.LFC_DETECTED, "Master")                                     -- Play a sound to alert the user
        end
    end,

    ScanCraftableItems = function()
        local items = {}
        -- Fetch all recipe IDs available to the player
        local recipeIDs = C_TradeSkillUI.GetAllRecipeIDs()
        if not recipeIDs or #recipeIDs == 0 then
            return
        end

        local count = 0
        for index, recipeID in ipairs(recipeIDs) do
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
        return items
    end,

    ScanChat = function(chat_text)
        -- Initialize variables
        local lower_chat_text = string.lower(chat_text)
        local has_lfc_keyword, has_link, has_item, is_learned = false, false, false, false

        -- Scan for LFC keywords (this can be expanded in the future to include more variations and languages)
        if string.match(lower_chat_text, "lfc") then
            has_lfc_keyword = true
        end

        -- Scan for item links
        -- WoW item link format: |cnIQx|Hitem:payload|h[text]|h|r
        -- where x is Enum.ItemQuality (can be numeric or other formats)
        local item_link = string.match(chat_text, "|cnIQ[^|]+|H[^|]+|h.-%|h|r")
        local item_id = nil

        if item_link then
            -- Now extract just the item ID from the full link for the watchlist lookup
            has_link = true
            item_id = string.match(item_link, "item:(%d+)")
            if item_id then
                has_item = true
            end
        end
        -- Crosscheck with watchlist
        if item_link or item_id then
            -- Direct map lookup O(1) instead of iterating through array O(n)
            if LFC_SERVICE.WATCHLIST[item_id] then
                is_learned = true
            end
        end
        return has_lfc_keyword, has_item, item_id, has_link, item_link, is_learned
    end
}
