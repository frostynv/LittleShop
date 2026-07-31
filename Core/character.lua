local namespace = select(2, ...) -- Get the namespace table from the addon

-- ============================================================
-- Character Class
-- ============================================================

-- @type Character
-- @field name  string Character name
-- @field realm string Realm (server) name
-- @field guid  string WoW player GUID
local Character = {}
Character.__index = Character

-- Creates a new Character instance
-- @param name string Character name
-- @param realm string Realm name
-- @param guid string Player GUID
-- @return Character
function Character:New(name, realm, guid)
    local instance = setmetatable({}, Character)
    instance.name = name
    instance.realm = realm
    instance.guid = guid
    return instance
end

namespace.export("character", Character)