local namespace = select(2, ...) -- Get the namespace table from the addon
namespace.modules = namespace.modules or {} -- Initialize the modules table if it doesn't exist

namespace.require = function(module_name)
    -- Check if the module is already loaded
    if namespace.modules[module_name] then
        return namespace.modules[module_name]
    else
        error("import '" .. module_name .. "' failed: module not found")
    end
end

namespace.export = function(module_name, module_table)
    namespace.modules[module_name] = module_table
end