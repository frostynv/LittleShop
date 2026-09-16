local namespace = select(2, ...) -- Get the namespace table from the addon
local Order = namespace.require("order")
local Craft = namespace.require("craft")
local Event = namespace.require("event")

-- ============================================================
-- Persistence Class
-- @note Decoupling persistence from orchestration, and provide a central hub for similar data (orders, crafts, crafters), allowing all data stored within the same scope level
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
	instance.event_space = nil     -- EventSpace for pub-sub events (set later via SetEventSpace)
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
		for _, craft_data in pairs(self.learned_crafts) do
			setmetatable(craft_data, Craft)
		end

		-- Restore metatables to persisted Order instances
		for _, order_data in pairs(self.orders) do
			setmetatable(order_data, Order)
		end
	end
	return self
end

function Persistence:CurrentProfile()
	return self.profile_settings
end

-- Sets the EventSpace for firing persistence change events
-- @param event_space EventSpace Event space for pub-sub communication
-- @return void
function Persistence:SetEventSpace(event_space)
	self.event_space = event_space
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
	if self.event_space then
		self.event_space:ThrowEvent("CRAFTS_CHANGED")
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
	if self.event_space then
		self.event_space:ThrowEvent("CRAFTS_CHANGED")
	end
	LOGGER.CONSOLE.info("In total " .. self:CraftableItemCountSize() .. " craft in persistence.")
end

namespace.export("persistence", Persistence) -- Export to the LittleShop addon instance