local namespace = select(2, ...) -- Get the namespace table from the addon
-- ============================================================
-- Event-Driven Framework for LittleShop
-- ============================================================
-- Pub-Sub event system for decoupled communication between data
-- layer (Persistence) and UI layer (Frames). Solves the problem of
-- tight coupling by letting frames subscribe to domain events.
--
-- Key Design Principles:
-- - Events represent state changes, not implementation details
-- - Listeners (frames) register near their instantiation (high cohesion)
-- - Persistence fires events but doesn't know about UI
-- - Multiple frames can listen to the same event independently

-- ============================================================
-- Event Class
-- ============================================================
-- @type Event
-- @field name       string Event identifier (e.g., "CRAFT_LEARNED")
-- @field callback   function Default callback triggered when event fires
-- Encapsulates a single event with name and optional callback
Event = {}
Event.__index = Event
namespace.export("Event", Event) -- Export to the LittleShop addon instance

-- Creates a new Event instance
-- @param name string Event identifier
-- @param callback function Optional default callback to trigger
-- @return Event
function Event:New(name, callback)
    local instance = setmetatable({}, Event)
    instance.name = name
    instance.callback = callback
    return instance
end

-- ============================================================
-- EventSpace Class
-- ============================================================
-- @type EventSpace
-- @field events table Map of event_name -> Event instances
-- Pub-Sub event broker managing event registration and listener callbacks.
-- Uses WoW's built-in CallbackRegistryMixin for callback management.
--
-- EventSpaces group related domain events (e.g., PERSISTENCE_EVENTS for
-- craft and order changes). Persistence fires events to its EventSpace,
-- and UI frames listen to events they care about.
--
-- Example Event Space (PERSISTENCE_EVENTS):
--   - CRAFT_LEARNED: A new craft item was learned
--   - CRAFT_REMOVED: A craft was removed from known recipes
--   - ORDER_ADDED: A new order was detected
--   - ORDER_STATE_CHANGED: An order's state changed
EventSpace = {}
EventSpace.__index = EventSpace
namespace.export("EventSpace", EventSpace) -- Export to the LittleShop addon instance

-- Creates a new EventSpace instance
-- Initializes with META_INFO event for basic pub-sub functionality
-- @return EventSpace
function EventSpace:New()
    local instance = setmetatable({}, EventSpace)
    CreateFromMixins(instance, CallbackRegistryMixin)
    instance.events = {
        ["META_INFO"] = Event:New("META_INFO", function()
            LOGGER.CONSOLE.print("EventSpace: GET_INFO event triggered")
        end)
    }
    return instance
end

-- ============================================================
-- EventSpace API - Listener Registration
-- ============================================================

-- Registers a listener callback for a specific event
-- Multiple callbacks can listen to the same event
-- @param event string Event name to listen for
-- @param callback function Called when event is fired: callback(...)
-- @return void
function EventSpace:RegisterListener(event, callback)
    self:RegisterCallback(event.name, callback)
end

-- Unregisters all listeners for a specific event
-- @param event string Event name to stop listening for
-- @return void
function EventSpace:UnregisterListener(event)
    self:UnregisterCallback(event.name)
end

-- ============================================================
-- EventSpace API - Event Management
-- ============================================================

-- Registers a new event type in this event space
-- Generates callback infrastructure for the event
-- @param event Event Event instance to register
-- @return void
function EventSpace:RegisterEvent(event)
    self:GenerateCallbackEvents(event)
    self.events[event.name] = event
end

-- Unregisters an event type and removes all listeners
-- @param event Event Event instance to unregister
-- @return void
function EventSpace:UnregisterEvent(event)
    self:UnregisterCallbackEvents(event)
    self.events[event.name] = nil
end

-- Fires an event, triggering all registered listeners
-- Calls both the event's default callback and registered listeners
-- @param event string or Event Event name or Event object to fire
-- @param ... any Arguments passed to all listeners
-- @return void
function EventSpace:ThrowEvent(event, ...)
    if self.events[event] then
        self.events[event].callback(...)
    end
    self:TriggerEvent(event.name, ...)
end

-- ============================================================
-- EnhancedFrame Class
-- ============================================================
-- Mixin that adds event-driven capabilities to WoW Frame objects.
-- Allows frames to easily subscribe and unsubscribe from EventSpace events.
local EnhancedFrame = {}
EnhancedFrame.__index = EnhancedFrame
namespace.export("EnhancedFrame", EnhancedFrame) -- Export to the LittleShop addon instance

-- Converts a standard WoW Frame into an EnhancedFrame
-- Adds event subscription capabilities without modifying original frame
-- @param parent_frame Frame The WoW Frame to enhance
-- @return Frame The enhanced frame with event methods
function EnhancedFrame:New(parent_frame)
    Mixin(parent_frame, EnhancedFrameMixin)
    return parent_frame
end

-- ============================================================
-- EnhancedFrameMixin
-- ============================================================
-- Mixin providing event handling methods to frames
EnhancedFrameMixin = {}

-- Registers frame to listen for an event from an EventSpace
-- Called during frame initialization to hook into data changes
-- High cohesion: subscription logic lives near frame creation
--
-- Usage:
--   local crafts_frame = CreateFrame("Frame", nil, parent)
--   crafts_frame = EnhancedFrame:New(crafts_frame)
--   crafts_frame:On(PERSISTENCE_EVENTS, "CRAFT_LEARNED", function(craft)
--       -- refresh crafts list
--   end)
--
-- @param eventspace EventSpace EventSpace to subscribe to
-- @param event string Event name to listen for
-- @param callback function Listener function called when event fires
-- @return void
function EnhancedFrameMixin:On(eventspace, event, callback)
    eventspace:RegisterListener(event, callback)
end

-- Unregisters frame from listening to an event
-- @param eventspace EventSpace EventSpace to unsubscribe from
-- @param event string Event name to stop listening for
-- @return void
function EnhancedFrameMixin:Off(eventspace, event)
    eventspace:UnregisterListener(event)
end




