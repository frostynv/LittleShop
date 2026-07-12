
LittleShop = _G["LittleShop"]
-- Minimap Button Setup
LittleShop.MINIMAP_BUTTON = {
    dbname = "LittleShopMinimapButton",
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

-- Minimap button library
local icon = LibStub("LibDBIcon-1.0")
-- Persistent storage for the addon using AceDB-3.0
local minimap_button = LibStub("LibDataBroker-1.1"):NewDataObject(LittleShop.MINIMAP_BUTTON.dbname, {
    type = "UI",
    text = LittleShop.MINIMAP_BUTTON.tooltip,
    icon = LittleShop.MINIMAP_BUTTON.icon,
    OnClick = LittleShop.MINIMAP_BUTTON.OnClick,
})
icon:Register("LittleShop", minimap_button, LittleShop:Persistence():CurrentProfile().minimap)
