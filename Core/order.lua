
local namespace = select(2, ...) -- Get the namespace table from the addon
-- ============================================================
-- Order Class
-- ============================================================
-- @type Order
-- @field unique_id   string  Composite key: GUID + day/H/M/S components
-- @field message     string  Raw chat message that triggered the order
-- @field player      table   Player identity: { name, realm, guid }
-- @field item_link   string  WoW item hyperlink extracted from the message
-- @field state       number  Current ORDER_STATE value
-- @field timestamp   table   os.date("*t") table captured at detection time
-- @field flags       table   Behavioral flags: { is_lfc, is_learned }
local Order = {}
Order.__index = Order

-- Lifecycle states for a work order.
-- Negative values represent pre-active/non-actionable states.
Order.ORDER_STATE = {
    NONDECISIVE = -3, -- Cannot determine if it is a craftable order
    UNLEARNED   = -2, -- Item is not in the player's known recipes
    HIDDEN      = -1, -- Removed from view without completing
    COMPLETE    =  0, -- Order has been completed
    PENDING     =  1, -- Detected; no whisper follow-up yet
    UNFULFILLED =  2, -- Followed up but not yet completed
    FULFILLED   =  3, -- Followed up and completed
}

Order.PROFESSION = {
    [1] = "Alchemy",
    [2] = "Blacksmithing",
    [3] = "Enchanting",
    [4] = "Engineering",
    [5] = "Inscription",
    [6] = "Jewelcrafting",
    [7] = "Leatherworking",
    [8] = "Tailoring",
}

Order.TradeLineSkill = {}

-- @param unique_id    string  Composite key (guid + timestamp components)
-- @param message      string  Raw chat message
-- @param player_name  string
-- @param player_realm string
-- @param guid         string  Player GUID from GetPlayerInfoByGUID
-- @param item_link    string  WoW item hyperlink
-- @param state        number  Initial ORDER_STATE; defaults to PENDING
-- @param timestamp    table   os.date("*t") table
-- @param flags        table   { is_lfc: bool }
-- @return Order
function Order:New(unique_id, message, player_name, player_realm, guid, item_link, state, timestamp, flags)
    local instance = setmetatable({}, Order)
    instance.unique_id  = unique_id
    instance.message    = message
    instance.player     = { name = player_name, realm = player_realm, guid = guid }
    instance.item_link  = item_link
    instance.state      = state or Order.ORDER_STATE.PENDING
    instance.timestamp  = timestamp
    instance.flags      = flags or { is_lfc = false, is_learned = false}
    return instance
end
namespace.export("Order", Order)

-- ============================================================
-- Item Class
-- ============================================================

-- @type Item
-- @field item_id    string         Numeric item ID extracted from the item link
-- @field item_link  string         WoW item hyperlink
-- @field crafter    string|nil     Optional: name of the assigned crafter
-- @field profession string|nil     Optional: profession that produces this item
local Item = {}
Item.__index = Item
namespace.export("Item", Item)

-- @param item_id    string
-- @param item_link  string
-- @param crafter    string|nil  Optional
-- @param profession string|nil  Optional
-- @return Item
function Item:New(item_id, item_link, crafter, profession)
    local instance = setmetatable({}, Item)
    instance.item_id    = item_id
    instance.item_link  = item_link
    instance.crafter    = crafter       -- Optional
    instance.profession = profession    -- Optional
    return instance
end

namespace.export("Order", Order)
