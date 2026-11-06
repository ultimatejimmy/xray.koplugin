std = "lua51"

globals = {
    "G_reader_settings",
    "Device",
    "logger",
    "UIManager",
    "InfoMessage",
    "ButtonDialog",
    "Dispatcher",
    "Event",
    "Screen",
    "CanvasContext",
    "Blitbuffer",
    "DataStorage",
    "dump",
    "_t",
    "plugin_path",
    "_G",
    "XRAY_DISABLE_UNIT_SUBPROCESS",
    "bit",
    "bit32",
    "_wavy_tile_cache",
    "_circle_tile_cache",
}

ignore = {
    "211", -- Unused local variable
    "212", -- Unused argument
    "213", -- Unused loop variable
}
