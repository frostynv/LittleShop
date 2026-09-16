-- ======
-- Helper functions that utilize the WOW API,
-- @module
-- @note Avoid calling the same API at multiple locations, causing costly refactoring if the API changes (which it does)
-- ====


local namespace = select(2, ...) -- Get the namespace table from the addon
local WowUtil = {}
WowUtil.__index = WowUtil


-- Extracts item ID from a WoW item link
-- Item link format: |cFF0070dditem:item_id:...|h[Item Name]|h|r
-- @param item_link string WoW item hyperlink
-- @return number item_id or nil if extraction fails
function WowUtil.ParseItemIdFromLink(item_link)
    if not item_link then return nil end
    return string.match(item_link, "item:(%d+)")
end

namespace.export("wowutil", WowUtil)