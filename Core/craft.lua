-- ============================================================
-- Craft Class
-- ============================================================
-- Represents a craftable item in the player's known recipes. Craftable items could spread across different characters thus, it's important to keep information about the crafter character
local Craft = {}
Craft.__index = Craft

function Craft:New(item_id, item_link, crafters, profession)
    local instance      = setmetatable({}, Craft)
    instance.item_id    = item_id
    instance.item_link  = item_link
    instance.crafters    = crafters
    instance.profession = profession
    return instance
end

function Craft:AddCrafter(crafter)
    if not self.crafters then
        self.crafters = {}
    end
    self.crafters[crafter] = true
end

function Craft:AddCrafters(crafters)
    if not self.crafters then
        self.crafters = {}
    end
    for _, crafter in ipairs(crafters) do
        self:AddCrafter(crafter)
    end
end

function Craft:RemoveCrafter(crafter)
    if self.crafters then
        self.crafters[crafter] = nil
    end
end

function Craft:GetCrafters()
    local crafter_list = {}
    if self.crafters then
        for crafter, _ in pairs(self.crafters) do
            table.insert(crafter_list, crafter)
        end
    end
    return crafter_list
end


_G.Craft = Craft