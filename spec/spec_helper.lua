-- spec_helper.lua
package.path = package.path .. ";xray.koplugin/?.lua"
package.path = package.path .. ";/home/jpautz/.luarocks/share/lua/5.1/?.lua"
package.path = package.path .. ";/home/jpautz/.luarocks/share/lua/5.1/?/init.lua"

-- Mocking KOReader environment
package.loaded["device"] = {
    getModel = function() return "K5" end,
    isAndroid = function() return false end,
    isKindle = function() return true end,
    isPocketBook = function() return false end,
    isKobo = function() return false end,
    isKoboV2 = function() return false end,
    screen = {
        getWidth = function() return 600 end,
        getHeight = function() return 800 end,
        scaleBySize = function(a, b) return b or a end,
    }
}

package.loaded["docsettings"] = {
    getSidecarDir = function(_, book_path) return book_path .. ".sdr" end
}

package.loaded["lfs"] = {
    attributes = function(path) 
        -- Basic mock: if it ends in .sdr, it's a directory
        if path:match("%.sdr$") or path:match("%.sdr/$") then
            return { mode = "directory" }
        end
        -- If we can open it, it's a file
        local f = io.open(path, "r")
        if f then
            f:close()
            return { mode = "file" }
        end
        return nil
    end,
    mkdir = function() return true end
}

package.loaded["logger"] = {
    info = function(...) end,
    warn = function(...) end,
    err = function(...) end,
    debug = function(...) end
}

package.loaded["xray_logger"] = {
    log = function(...) print(...) end,
}

package.loaded["datastorage"] = {
    getSettingsDir = function() return "/tmp/koreader/settings" end
}

-- UI tracking for testing
_G.ui_tracker = {
    shown = {},
    last_shown = nil,
    closed = {}
}

package.loaded["ui/uimanager"] = {
    show = function(self, widget, refreshtype, region, x, y)
        local w = type(self) == "table" and widget or self
        local posX = type(self) == "table" and x or refreshtype
        local posY = type(self) == "table" and y or region
        table.insert(_G.ui_tracker.shown, w)
        _G.ui_tracker.last_shown = w
        _G.ui_tracker.last_show_x = posX
        _G.ui_tracker.last_show_y = posY
    end,
    close = function(a, b)
        local w = b or a
        table.insert(_G.ui_tracker.closed, w)
    end,
    scheduleIn = function(a, b, c)
        if type(a) == "function" then a()
        elseif type(b) == "function" then b()
        elseif type(c) == "function" then c() end
    end,
    nextTick = function(a, b)
        local f = b or a
        if type(f) == "function" then f() end
    end,
    setDirty = function() end,
    forceRePaint = function() end,
    getTime = function() return 0 end,
}
package.loaded["ui/widget/infomessage"] = {
    new = function(a, b) return { type = "InfoMessage", args = b or a } end
}
package.loaded["ui/widget/notification"] = {
    new = function(a, b) return { type = "Notification", args = b or a } end
}
package.loaded["ui/widget/progressbardialog"] = {
    new = function(a, b)
        local dialog = { type = "ProgressBarDialog", args = b or a }
        dialog.show = function() end
        dialog.close = function() end
        dialog.reportProgress = function() end
        return dialog
    end
}
package.loaded["ui/widget/buttondialog"] = {
    new = function(a, b) 
        local dialog = { type = "ButtonDialog", args = b or a }
        dialog.getSize = function() return { w = 800, h = 100 } end
        return dialog
    end
}
package.loaded["ui/widget/confirmbox"] = {
    new = function(a, b) return { type = "ConfirmBox", args = b or a } end
}
package.loaded["ui/widget/textviewer"] = {
    new = function(a, b) return { type = "TextViewer", args = b or a } end
}
package.loaded["ui/widget/menu"] = {
    new = function(a, b) return { type = "Menu", args = b or a } end
}
package.loaded["ui/widget/verticalgroup"] = {
    new = function(a, b) return { type = "VerticalGroup", args = b or a } end
}
package.loaded["ui/widget/widget"] = (function()
    local klass = {}
    klass.extend = function(self, prototype)
        prototype = prototype or {}
        prototype.new = function(cls, args)
            local instance = {}
            for k, v in pairs(prototype) do instance[k] = v end
            for k, v in pairs(args or {}) do instance[k] = v end
            return instance
        end
        return prototype
    end
    klass.new = function(self, args)
        return klass:extend(args):new()
    end
    return klass
end)()
package.loaded["ui/widget/widgetcontainer"] = {
    new = function(a, b) return { type = "WidgetContainer", args = b or a } end
}
package.loaded["ui/widget/container/framecontainer"] = {
    new = function(a, b) 
        local fc = { type = "FrameContainer", args = b or a }
        fc.getSize = function() return { w = 800, h = 300 } end
        return fc
    end
}
package.loaded["ui/widget/container/alphacontainer"] = {
    new = function(a, b)
        local ac = { type = "AlphaContainer", args = b or a }
        ac.getSize = function() return { w = 800, h = 800 } end
        ac.paintTo = function() end
        ac.onCloseWidget = function() end
        return ac
    end
}
package.loaded["ui/widget/container/centercontainer"] = {
    new = function(a, b) return { type = "CenterContainer", args = b or a } end
}
package.loaded["ui/widget/container/movablecontainer"] = {
    new = function(a, b) return { type = "MovableContainer", args = b or a } end
}
package.loaded["ui/widget/container/widgetcontainer"] = {
    new = function(a, b) return { type = "WidgetContainer", args = b or a } end
}
package.loaded["ui/widget/container/inputcontainer"] = (function()
    local klass = {}
    klass.extend = function(self, prototype)
        prototype = prototype or {}
        prototype.new = function(cls, args)
            args = args or {}
            local instance = {}
            for k, v in pairs(prototype) do instance[k] = v end
            for k, v in pairs(args) do instance[k] = v end
            instance.type = "InputContainer"
            if instance.init then instance:init() end
            return instance
        end
        return prototype
    end
    klass.new = function(self, args)
        return klass:extend(args):new()
    end
    return klass
end)()
package.loaded["ui/widget/container/leftcontainer"] = {
    new = function(a, b) return { type = "LeftContainer", args = b or a } end
}
package.loaded["ui/widget/container/rightcontainer"] = {
    new = function(a, b) return { type = "RightContainer", args = b or a } end
}
package.loaded["ui/widget/container/bottomcontainer"] = {
    new = function(a, b) return { type = "BottomContainer", args = b or a } end
}
package.loaded["ui/widget/textboxwidget"] = {
    new = function(a, b) return { type = "TextBoxWidget", args = b or a } end
}
package.loaded["ui/widget/linewidget"] = {
    new = function(a, b) return { type = "LineWidget", args = b or a } end
}
package.loaded["ui/widget/verticalspan"] = {
    new = function(a, b) return { type = "VerticalSpan", args = b or a } end
}
package.loaded["ui/widget/horizontalgroup"] = {
    new = function(a, b) return { type = "HorizontalGroup", args = b or a } end
}
package.loaded["ui/widget/horizontalspan"] = {
    new = function(a, b) return { type = "HorizontalSpan", args = b or a } end
}
package.loaded["ui/size"] = {
    line = { thick = 2 },
    padding = { small = 4 }
}
package.loaded["ui/geometry"] = {
    new = function(a, b) return b or a end
}
package.loaded["ui/widget/horizontalgroup"] = {
    new = function(a, b) return { type = "HorizontalGroup", args = b or a } end
}
package.loaded["ui/widget/table"] = {
    new = function(a, b) return { type = "Table", args = b or a } end
}
package.loaded["ui/widget/textwidget"] = {
    new = function(a, b) 
        local tw = { type = "TextWidget", args = b or a }
        tw.getSize = function() return nil end
        return tw
    end
}
package.loaded["ui/widget/button"] = {
    new = function(a, b) 
        local btn = { type = "Button", args = b or a }
        btn.getSize = function() return { w = 100, h = 50 } end
        return btn
    end
}
package.loaded["ffi/blitbuffer"] = {
    COLOR_BLACK = 0,
    COLOR_WHITE = 1,
    COLOR_GRAY = 2,
    COLOR_LIGHT_GRAY = 3,
    COLOR_DARK_GRAY = 4,
    COLOR_GRAY_B = 5,
    Color8 = function(g) return g end
}
package.loaded["ui/font"] = {
    getFace = function() return {} end
}
package.loaded["ui/rendertext"] = {}
package.loaded["ui/event"] = {
    new = function(a, b, c) 
        if type(a) == "string" then return { name = a, args = b } end
        return { name = b, args = c }
    end
}
package.loaded["ui/gesturerange"] = {
    new = function(a, b) return { type = "GestureRange", args = b or a } end
}
package.loaded["gettext"] = {
    _ = function(s) return s end,
    getLanguage = function() return "en" end
}
package.loaded["ui/trapper"] = {
    dismissableRunInSubprocess = function(_, _, f) return true, f() end
}
package.loaded["xray_logger"] = {
    log = function(...) end,
}
package.loaded["socket.http"] = {}
package.loaded["ssl.https"] = {}
package.loaded["ltn12"] = {}
package.loaded["socket"] = {}
package.loaded["socketutil"] = {}
package.loaded["util"] = {
    splitToChars = function(text)
        local chars = {}
        for c in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
            table.insert(chars, c)
        end
        return chars
    end
}
local json_lib = nil
pcall(function() json_lib = require("dkjson") end)
if not json_lib then
    json_lib = {
        encode = function(t) return "{}" end,
        decode = function(s) return {} end
    }
end
package.loaded["json"] = json_lib

function _G.createMockPlugin()
    local plugin = {
        ui = {
            document = {
                file = "test_book.epub",
                getToc = function() return {} end,
                getProps = function() return { title = "Test Title", authors = "Test Author" } end,
                compareXPointers = function(self_doc, xp1, xp2)
                    if xp1 == xp2 then return 0 end
                    local mock_positions = {
                        xp_five = 5,
                        xp_25 = 6,
                        xp_37 = 7,
                        xp_minus37 = 7,
                        xp_uni37 = 7,
                        xp_space37 = 7,
                        xp_80 = 8,
                        xp1 = 10,
                        xp2 = 20,
                    }
                    local pos1 = mock_positions[xp1] or 0
                    local pos2 = mock_positions[xp2] or 0
                    if pos1 < pos2 then return 1 end
                    if pos1 > pos2 then return -1 end
                    if xp1 < xp2 then return 1 end
                    return -1
                end
            },
            paging = {
                getCurrentPage = function() return 10 end
            },
            handleEvent = function() end,
            font = {
                font_face = "FreeSerif",
                configurable = {
                    font_size = 22,
                }
            }
        },
        loc = {
            t = function(s, ...)
                local fmt = s
                local args = {...}
                if type(s) == "table" then
                    fmt = args[1]
                    table.remove(args, 1)
                end
                if type(fmt) == "string" and #args > 0 then
                    if fmt:find("%%") then
                        local status, res = pcall(string.format, fmt, unpack(args))
                        if status then return res end
                    end
                    -- Fallback for testing: just append args
                    for i = 1, #args do
                        fmt = fmt .. " " .. tostring(args[i])
                    end
                end
                return fmt
            end,
            getLanguage = function() return "en" end,
            setLanguage = function() end
        },
        ai_helper = {
            log = function() end,
            settings = {}
        },
        characters = {},
        locations = {},
        timeline = {},
        historical_figures = {},
        log = function(...) end,
        normalizeChapterName = function(self, name) return name:lower() end,
        isNonNarrativeChapter = function() return false end,
        deduplicateByName = function(self, list) return list end,
        sortDataByFrequency = function(self, list) return list end,
        assignTimelinePages = function() end,
        sortTimelineByTOC = function() end
    }
    return plugin
end
