---
description: LittleShop Lua addon project context, architecture, and coding standards
applyTo: '**/*.lua'
---

# LittleShop Lua Helper Agent

## Project Context

**LittleShop** is a World of Warcraft addon for managing work orders and crafting requests. 

### Architecture Overview
- **Core Modules**: `logger.lua`, `craft.lua`, `order.lua`, `littleshop.lua`
- **Dependencies**: LibDBIcon-1.0, LibDataBroker-1.1, LibStub
- **Persistence**: SavedVariables (`LittleShopSavedVariables`) for learned_crafts, orders, profile_settings
- **Core Classes**: `Craft`, `Order`, `Item`, `Persistence`

**Important**: You are still learning WoW API. Explain concepts when coding, but keep documentation concise—avoid over-explanation in comments.

---

## Code Style Guidelines

### Naming Conventions
- **Variables & Functions**: `snake_case` (e.g., `item_id`, `profile_settings`, `unique_id`, `player_realm`)
- **Methods**: `snake_case` in function definitions: `function ClassName:method_name()`
- **Constants**: `UPPERCASE` (e.g., `ORDER_STATE`, `PROFESSION`, `SAVED_VARS_SCHEMA`)
- **Classes**: `CamelCase` (e.g., `Order`, `Craft`, `Persistence`)

### Class Structure & Encapsulation

**Standard Lua class pattern used throughout the codebase:**

```lua
local MyClass = {}
MyClass.__index = MyClass

function MyClass:New(arg1, arg2)
    local instance = setmetatable({}, MyClass)
    instance.field1 = arg1
    instance.field2 = arg2
    return instance
end

function MyClass:InstanceMethod(args)
    -- encapsulated state manipulation
end

-- Export to global if needed for cross-module use
_G.MyClass = MyClass
```

**Encapsulation Rules:**
- Objects encapsulate their state and behavior (methods that operate on that state)
- Use getter/setter methods: `GetValue()`, `SetValue()`, `AddItem()`, `RemoveItem()`
- For 1-n or n-n relationships (e.g., Craft has many Crafters), use tables with helper methods
- Avoid directly exposing internal tables; provide methods to interact with them

### Separation of Concerns

- **One responsibility per function/class**: Order handles order state, Craft handles craftable items, Persistence handles storage
- **Top-down framework approach**: Build the framework first, then break down recursively into smaller, modular pieces
- **Understand before modularizing**: It's acceptable to write larger functions initially; modularize as understanding grows
- **Validation & error handling happen at boundaries**: Persistence layer validates data before storage; classes validate inputs in setters

### Error Handling & Validation

- Use **defensive checks** before operations: `if not value or next(value) == nil then`
- Log errors/warnings via `LOGGER.CONSOLE`: `warn()`, `error()`, `info()`
- Return nil or default values on validation failure (don't throw errors)
- Example:
  ```lua
  function Persistence:MergeLearnedCrafts(new_crafts)
      if not new_crafts or next(new_crafts) == nil then
          LOGGER.CONSOLE.warn("No new crafts to merge. Skipping.")
          return
      end
      -- proceed with merge
  end
  ```

---

## Documentation Format

### Function Documentation (LuaDoc Style, Above Definition)

Place LuaDoc comments **directly above** function definitions. Include:
- `@param` for each parameter
- `@return` for return values
- Brief description of what the function does

**Example:**
```lua
-- Adds a new crafter to the craft's crafter list
-- @param crafter string Character name of the crafter
function Craft:AddCrafter(crafter)
    if not self.crafters then
        self.crafters = {}
    end
    self.crafters[crafter] = true
end
```

### Class Documentation (LuaDoc Type, Above Class Definition)

Place type documentation **above** the class definition:

```lua
-- @type Craft
-- @field item_id    string       Unique item identifier
-- @field item_link  string       WoW item hyperlink
-- @field crafters   table        Map of crafter names: { crafter_name = true }
-- @field profession string       Profession that produces this item
local Craft = {}
Craft.__index = Craft
```

### Design Explanations (Inline Comments)

For complex logic or design decisions, add inline comments explaining:
- **Why** a specific approach was chosen
- **What** behavior is expected
- **Constraints** or important context

**Example:**
```lua
-- Restore metatables to persisted instances
-- (Serialization loses metatable info; we reattach them when loading)
for item_id, craft_data in pairs(self.learned_crafts) do
    setmetatable(craft_data, Craft)
end
```

### Where to Document
- **Function signatures**: LuaDoc comments directly above function
- **Class types**: LuaDoc `@type` and `@field` above class definition
- **Complex logic**: Inline comments explaining the "why" and "what"
- **Design notes**: If design spans multiple functions, add a section comment like:
  ```lua
  -- ============================================================
  -- Profile System and Cross-Character Persistence
  -- ============================================================
  ```

---

## WoW API Guidance

When writing WoW-specific code:
- **Explain the concept briefly** when introducing WoW API calls
- **Include inline comments** for non-obvious WoW mechanics (e.g., GUID format, SavedVariables)
- **Don't over-document**: Assume you'll explain in conversation, not in comments

**Example:**
```lua
-- SavedVariables auto-persists tables across sessions when registered in .toc
-- Format: LittleShopSavedVariables = { learned_crafts = {}, orders = {} }
function Persistence:Save()
    LittleShopSavedVariables.learned_crafts = self.learned_crafts
end
```

---

## Code Examples (For Review & Iteration)

Below are three example code snippets showing your expected style.

### Example 1: New Class Definition with Encapsulation

```lua
-- ============================================================
-- Manager Class
-- ============================================================

-- @type Manager
-- @field items table Map of item_id -> Item object
-- @field count number Total number of items managed
local Manager = {}
Manager.__index = Manager

-- Creates a new Manager instance
-- @return Manager
function Manager:New()
    local instance = setmetatable({}, Manager)
    instance.items = {}
    instance.count = 0
    return instance
end

-- Registers an item with the manager
-- @param item Item to register
-- @return boolean true if successfully added, false if already exists
function Manager:RegisterItem(item)
    if self.items[item.id] then
        LOGGER.CONSOLE.warn("Item " .. item.id .. " already registered. Skipping.")
        return false
    end
    self.items[item.id] = item
    self.count = self.count + 1
    return true
end

-- Retrieves an item by ID
-- @param item_id string Unique item identifier
-- @return Item or nil
function Manager:GetItem(item_id)
    return self.items[item_id]
end

-- Lists all managed items
-- @return table Array of Item objects
function Manager:GetAllItems()
    local result = {}
    for _, item in pairs(self.items) do
        table.insert(result, item)
    end
    return result
end

_G.Manager = Manager
```

**Key features shown:**
- Snake_case method names: `RegisterItem()`, `GetItem()`, `GetAllItems()`
- LuaDoc comments above class and each method
- Encapsulation: Items stored in private table, accessed via getter methods
- Error handling: Check for duplicates, log warnings
- Return values: Boolean for success, nil for not found

---

### Example 2: Utility Function with Error Handling

```lua
-- Extracts item ID from a WoW item link
-- Item link format: |cFF0070dditem:item_id:...|h[Item Name]|h|r
-- @param item_link string WoW item hyperlink
-- @return number item_id or nil if extraction fails
local function ExtractItemIDFromLink(item_link)
    if not item_link or item_link == "" then
        LOGGER.CONSOLE.warn("Attempted to extract item ID from empty link")
        return nil
    end
    
    -- WoW item link format: |c...item:ID:...|h[Name]|h|r
    -- Use simple pattern match to find "item:NUMBER:"
    local item_id = string.match(item_link, "item:(%d+):")
    
    if not item_id then
        LOGGER.CONSOLE.warn("Failed to extract item ID from link: " .. item_link)
        return nil
    end
    
    return tonumber(item_id)
end
```

**Key features shown:**
- Clear parameter and return documentation (including data format)
- Defensive null/empty checks at start
- Explanatory comment for non-obvious logic (WoW link format)
- Consistent logging for validation failures
- Return nil on failure (not exceptions)

---

### Example 3: Event Handler with Top-Down Structure

```lua
-- Handles PLAYER_LOGIN event: initializes addon, scans recipes, activates service
-- @self LittleShop instance
local function OnPlayerLogin()
    -- Initialize persistence layer
    persistence:Initialize()
    
    -- Scan player's known recipes
    local learned_crafts = ScanPlayerRecipes()
    persistence:MergeLearnedCrafts(learned_crafts)
    
    LOGGER.CONSOLE.info("LittleShop initialized. Found " .. persistence:CraftableItemCountSize() .. " known recipes.")
    
    -- Activate monitoring systems
    ActivateOrderMonitoring()
end
```

**Key features shown:**
- Clear, linear flow (top-down)
- Comments explain intent at high level
- Separate concerns (initialization → scanning → activation)
- Logging for user feedback
- Functions called are documented above (not shown in this snippet)

---

## Workflow for Adding New Code

1. **Discuss the requirement** in conversation: what does the new code do, what class/module does it belong to?
2. **Review examples** if needed: Code snippets matching your style
3. **Suggest modifications** before implementation: Let me know if naming, structure, or approach should change
4. **Implementation**: Once approved, integrate code into the appropriate module
5. **Iterate**: If refactoring is needed later, follow the same review-first approach