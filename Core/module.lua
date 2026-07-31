local namespace = select(2, ...) -- Get the namespace table from the addon
namespace.modules = namespace.modules or {} -- Initialize the modules table if it doesn't exist

namespace.require = function(module_name)
    local module_key = string.lower(module_name)
    -- Check if the module is already loaded
    if namespace.modules[module_key] then
        return namespace.modules[module_key]
    else
        error("import '" .. module_key .. "' failed: module not found")
    end
end

namespace.export = function(module_name, module_table)
    local module_key = string.lower(module_name)
    namespace.modules[module_key] = module_table
end