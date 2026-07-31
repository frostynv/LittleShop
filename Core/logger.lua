local namespace = select(2, ...)

local Logger = {}
Logger.__index = Logger
Logger._instance = nil

Logger.COLORS = {
    GREEN = "|cFF00FF00",
    RED = "|cFFFF0000",
    YELLOW = "|cFFFFFF00",
    BLUE = "|cFF0080FF",
    GOLD = "|cFFFFD700",
    WHITE = "|cFFFFFFFF",
    ORANGE = "|cFFFF8000",
    PURPLE = "|cFFB000FF",
    GRAY = "|cFF808080",
    RESET = "|r",
    APP_COLOR = "|cFFB000FF",
}

local function create_instance(tag, is_debug)
    local instance = setmetatable({}, Logger)
    instance.tag = tag or "LittleShop"
    instance.is_debug = is_debug ~= false
    instance.COLORS = Logger.COLORS
    instance.CONSOLE = {
        print = function(message)
            instance:Print(message)
        end,
        error = function(message)
            instance:Error(message)
        end,
        warn = function(message)
            instance:Warn(message)
        end,
        info = function(message)
            instance:Info(message)
        end,
        list = function(items)
            instance:List(items)
        end,
    }
    return instance
end

function Logger:GetInstance(tag, is_debug)
    if not Logger._instance then
        Logger._instance = create_instance(tag, is_debug)
    elseif is_debug ~= nil then
        Logger._instance.is_debug = is_debug
    end
    return Logger._instance
end

function Logger:New(tag, is_debug)
    return Logger:GetInstance(tag, is_debug)
end

function Logger:_emit(color, message)
    print(self.COLORS.APP_COLOR .. "[" .. self.tag .. "]" .. color .. " " .. tostring(message) .. self.COLORS.RESET)
end

function Logger:Print(message)
    if self.is_debug then
        self:_emit(self.COLORS.RESET, message)
    end
end

function Logger:Error(message)
    self:_emit(self.COLORS.RED, message)
end

function Logger:Warn(message)
    self:_emit(self.COLORS.YELLOW, message)
end

function Logger:Info(message)
    self:_emit(self.COLORS.BLUE, message)
end

function Logger:List(items)
    if not items or #items == 0 then
        return
    end

    for index, item in ipairs(items) do
        if index == 1 then
            print(self.COLORS.APP_COLOR .. "[" .. self.tag .. "]" .. self.COLORS.RESET .. " | " .. tostring(item))
        else
            print(" | " .. tostring(item))
        end
    end
end

namespace.export("logger", Logger)

LOGGER = Logger:GetInstance(select(1, ...))
