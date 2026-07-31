local namespace = select(2, ...) -- Get the namespace table from the addon
local Character = namespace.require("character")

-- ============================================================
-- Crafter Class
-- ============================================================

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

namespace.export("crafter", Crafter)