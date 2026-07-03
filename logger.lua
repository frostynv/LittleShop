-- Color Constants (WoW color code format: |cFFRRGGBB text |r)


LOGGER = {
    COLORS = {
        GREEN = "|cFF00FF00", -- Success, info
        RED = "|cFFFF0000", -- Error, critical
        YELLOW = "|cFFFFFF00", -- Warning, caution
        BLUE = "|cFF0080FF", -- Debug, info
        GOLD = "|cFFFFD700", -- Highlight, important
        WHITE = "|cFFFFFFFF", -- Default, neutral
        ORANGE = "|cFFFF8000", -- Alert, notice
        PURPLE = "|cFFB000FF", -- Special, magic
        GRAY = "|cFF808080", -- Muted, disabled
        RESET = "|r",      -- Color reset code

        APP_COLOR = "|cFFB000FF", -- Application-specific color (example: purple)
    },
    IS_DEBUG = true,
    CONSOLE = {
        print = function(message)
            if LOGGER.IS_DEBUG then
                print(LOGGER.COLORS.APP_COLOR .. "[" .. APP_NAME .. "]" .. LOGGER.COLORS.RESET .. " " .. message)
            end
        end,
        error = function(message)
            print(LOGGER.COLORS.APP_COLOR .. "[" .. APP_NAME .. "]" .. LOGGER.COLORS.RED .. " " .. message)
        end,
        warn = function(message)
            print(LOGGER.COLORS.APP_COLOR .. "[" .. APP_NAME .. "]" .. LOGGER.COLORS.YELLOW .. " " .. message)
        end,
        info = function(message)
            print(LOGGER.COLORS.APP_COLOR .. "[" .. APP_NAME .. "]" .. LOGGER.COLORS.BLUE .. " " .. message)
        end,
    },
}
