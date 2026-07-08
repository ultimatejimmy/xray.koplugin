local Screen = require("device").screen
local Font = require("ui/font")
local Geom = require("ui/geometry")
local Blitbuffer = require("ffi/blitbuffer")
local UIManager = require("ui/uimanager")
local FrameContainer = require("ui/widget/container/framecontainer")
local InputContainer = require("ui/widget/container/inputcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local TextWidget = require("ui/widget/textwidget")
local Button = require("ui/widget/button")
local GestureRange = require("ui/gesturerange")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local MovableContainer = require("ui/widget/container/movablecontainer")
local TextBoxWidget = require("ui/widget/textboxwidget")
local LineWidget = require("ui/widget/linewidget")

local plugin_path = ((...) or ""):match("(.-)[^%.]+$") or ""
local xray_theme = require(plugin_path .. "xray_theme")

local M = {}

local function sc(val)
    return Screen:scaleBySize(val)
end

function M.show(ui_instance, args)
    local sw = Screen:getWidth()
    local sh = Screen:getHeight()
    local dialog_w = math.min(sw - sc(20), sc(380))

    local fs = 20
    if G_reader_settings then
        fs = G_reader_settings:readSetting("cre_font_size") or 20
    end
    local ui_font_size = math.max(14, math.min(fs, 24))
    local label_font_size = math.max(11, math.min(fs - 4, 18))
    local title_font_size = math.max(10, math.min(fs - 5, 15))

    local overlay
    local refresh

    refresh = function()
        if overlay then
            UIManager:close(overlay, "ui")
        end

        local current_val = args.get_current_func()

        local function span()
            return VerticalSpan:new{ width = xray_theme.gap }
        end

        local title_label = TextWidget:new{
            text = args.title:upper(),
            face = Font:getFace("infofont", title_font_size),
            fgcolor = Blitbuffer.COLOR_BLACK,
        }

        local content_vg = VerticalGroup:new{
            align = "left",
            title_label,
            span(),
        }

        if args.description and args.description ~= "" then
            local formatted_desc = "\xEF\xBF\xB1" .. args.description:gsub("%[B%]", "\xEF\xBF\xB2"):gsub("%[/B%]", "\xEF\xBF\xB3")
            table.insert(content_vg, TextBoxWidget:new{
                text = formatted_desc,
                face = Font:getFace("cfont", ui_font_size),
                width = dialog_w - sc(32),
                alignment = ui_instance:isRTL() and "right" or "left",
            })
            table.insert(content_vg, span())
        end

        local options_list = (type(args.options) == "function") and args.options() or args.options
        for _, opt in ipairs(options_list) do
            local is_selected = (opt.value == current_val)
            local dot_char = is_selected and "●" or "○"
            
            local row_content = HorizontalGroup:new{
                align = "center",
            }
            if ui_instance:isRTL() then
                table.insert(row_content, TextBoxWidget:new{
                    text = opt.text,
                    face = Font:getFace("cfont", ui_font_size),
                    fgcolor = Blitbuffer.COLOR_BLACK,
                    width = dialog_w - sc(72),
                    alignment = "right",
                })
                table.insert(row_content, WidgetContainer:new{ dimen = Geom:new{ w = sc(6), h = 1 } })
                table.insert(row_content, TextWidget:new{
                    text = dot_char,
                    face = Font:getFace("cfont", ui_font_size),
                    fgcolor = Blitbuffer.COLOR_BLACK,
                })
            else
                table.insert(row_content, TextWidget:new{
                    text = dot_char,
                    face = Font:getFace("cfont", ui_font_size),
                    fgcolor = Blitbuffer.COLOR_BLACK,
                })
                table.insert(row_content, WidgetContainer:new{ dimen = Geom:new{ w = sc(6), h = 1 } })
                table.insert(row_content, TextBoxWidget:new{
                    text = opt.text,
                    face = Font:getFace("cfont", ui_font_size),
                    fgcolor = Blitbuffer.COLOR_BLACK,
                    width = dialog_w - sc(72),
                    alignment = "left",
                })
            end

            local frame = FrameContainer:new{
                bordersize = is_selected and xray_theme.border_btn or sc(1),
                radius = xray_theme.radius_btn,
                padding = sc(6),
                color = is_selected and xray_theme.color_border or xray_theme.color_section_rule,
                background = xray_theme.color_bg,
                width = dialog_w - sc(32),
                row_content
            }
            local item = InputContainer:new{ frame }
            item.ges_events = {
                Tap = {
                    GestureRange:new{
                        ges = "tap",
                        range = function()
                            return Geom:new{
                                x = frame.dimen.x,
                                y = frame.dimen.y,
                                w = dialog_w - sc(32),
                                h = frame.dimen.h
                            }
                        end
                    }
                }
            }
            item.onTap = function()
                local handled = args.save_func(opt.value, refresh)
                if not handled then
                    refresh()
                end
                return true
            end
            table.insert(content_vg, item)
            table.insert(content_vg, WidgetContainer:new{ dimen = Geom:new{ w = 1, h = sc(4) } })
        end

        -- Extra customizable middle widgets
        if args.extra_widgets_func then
            local extra = args.extra_widgets_func(refresh)
            if extra then
                for _, widget in ipairs(extra) do
                    table.insert(content_vg, widget)
                end
            end
        end

        table.insert(content_vg, span())
        table.insert(content_vg, LineWidget:new{
            dimen = Geom:new{ w = dialog_w - sc(32), h = sc(1) },
            background = xray_theme.color_section_rule,
        })
        table.insert(content_vg, span())

        -- Close & About buttons at the bottom
        local buttons = {}
        if args.about_text then
            local about_btn = Button:new{
                text = ui_instance.loc:t("menu_about") or "About",
                face = Font:getFace("cfont", ui_font_size),
                width = (dialog_w - sc(40)) / 2,
                height = sc(42),
                bordersize = xray_theme.border_btn,
                radius = xray_theme.radius_btn,
                callback = function()
                    M.showAbout(ui_instance, args.title, args.about_text)
                end
            }
            table.insert(buttons, about_btn)
        end

        local close_btn = Button:new{
            text = ui_instance.loc:t("close") or "Close",
            face = Font:getFace("cfont", ui_font_size),
            width = args.about_text and ((dialog_w - sc(40)) / 2) or (dialog_w - sc(32)),
            height = sc(42),
            bordersize = xray_theme.border_btn,
            radius = xray_theme.radius_btn,
            callback = function()
                UIManager:close(overlay, "ui")
            end
        }
        table.insert(buttons, close_btn)

        local btn_row
        if #buttons == 2 then
            btn_row = HorizontalGroup:new{
                align = "center",
                buttons[1],
                WidgetContainer:new{ dimen = Geom:new{ w = sc(8), h = 1 } },
                buttons[2],
            }
        else
            btn_row = close_btn
        end
        table.insert(content_vg, btn_row)

        local card = FrameContainer:new{
            padding = sc(12),
            radius = xray_theme.radius_window,
            bordersize = sc(2),
            color = Blitbuffer.COLOR_BLACK,
            background = xray_theme.color_bg,
            width = dialog_w - sc(2),
            content_vg
        }

        local card_outer = FrameContainer:new{
            bordersize = sc(1),
            color = Blitbuffer.Color8(180),
            padding = 0,
            background = xray_theme.color_bg,
            radius = xray_theme.radius_window,
            width = dialog_w,
            card
        }

        local movable = MovableContainer:new{ card_outer }
        if ui_instance._current_card_offset then
            movable:setMovedOffset(ui_instance._current_card_offset)
        end

        local orig_handleEvent = movable.handleEvent
        movable.handleEvent = function(this, ev)
            local res = orig_handleEvent(this, ev)
            if ev.type == "Gesture" or ev.type == "Pan" or ev.type == "Hold" then
                ui_instance._current_card_offset = this.moved_offset
            end
            return res
        end

        overlay = InputContainer:new{
            key_events = {
                Close = { { "Back" } }
            },
            CenterContainer:new{
                dimen = Geom:new{ w = sw, h = sh },
                movable
            }
        }
        function overlay:onClose()
            if self._closing then return end
            self._closing = true
            ui_instance._current_card_offset = nil
            UIManager:close(self, "ui")
            if args.on_close then args.on_close() end
            return true
        end
        UIManager:show(overlay, "ui")
    end

    refresh()
end

function M.showAbout(ui_instance, title, text)
    local sw = Screen:getWidth()
    local sh = Screen:getHeight()
    local dialog_w = math.min(sw - sc(20), sc(380))

    local fs = 20
    if G_reader_settings then
        fs = G_reader_settings:readSetting("cre_font_size") or 20
    end
    local ui_font_size = math.max(14, math.min(fs, 24))
    local title_font_size = math.max(10, math.min(fs - 5, 15))

    local overlay

    local function span()
        return VerticalSpan:new{ width = xray_theme.gap }
    end

    local title_label = TextWidget:new{
        text = (title or "About"):upper(),
        face = Font:getFace("infofont", title_font_size),
        fgcolor = Blitbuffer.COLOR_BLACK,
    }

    local formatted_text = "\xEF\xBF\xB1" .. text:gsub("%[B%]", "\xEF\xBF\xB2"):gsub("%[/B%]", "\xEF\xBF\xB3")
    local content_vg = VerticalGroup:new{
        align = "left",
        title_label,
        span(),
        TextBoxWidget:new{
            text = formatted_text,
            face = Font:getFace("cfont", ui_font_size),
            width = dialog_w - sc(32),
            alignment = ui_instance:isRTL() and "right" or "left",
        },
        span(),
        LineWidget:new{
            dimen = Geom:new{ w = dialog_w - sc(32), h = sc(1) },
            background = xray_theme.color_section_rule,
        },
        span(),
        Button:new{
            text = ui_instance.loc:t("close") or "Close",
            face = Font:getFace("cfont", ui_font_size),
            width = dialog_w - sc(32),
            height = sc(42),
            bordersize = xray_theme.border_btn,
            radius = xray_theme.radius_btn,
            callback = function()
                UIManager:close(overlay, "ui")
            end
        }
    }

    local card = FrameContainer:new{
        padding = sc(12),
        radius = xray_theme.radius_window,
        bordersize = sc(2),
        color = Blitbuffer.COLOR_BLACK,
        background = xray_theme.color_bg,
        width = dialog_w - sc(2),
        content_vg
    }

    local card_outer = FrameContainer:new{
        bordersize = sc(1),
        color = Blitbuffer.Color8(180),
        padding = 0,
        background = xray_theme.color_bg,
        radius = xray_theme.radius_window,
        width = dialog_w,
        card
    }

    local movable = MovableContainer:new{ card_outer }
    if ui_instance._about_card_offset then
        movable:setMovedOffset(ui_instance._about_card_offset)
    end

    local orig_handleEvent = movable.handleEvent
    movable.handleEvent = function(this, ev)
        local res = orig_handleEvent(this, ev)
        if ev.type == "Gesture" or ev.type == "Pan" or ev.type == "Hold" then
            ui_instance._about_card_offset = this.moved_offset
        end
        return res
    end

    local AlphaContainer = require("ui/widget/container/alphacontainer")
    local dim_child = {
        getSize = function(this)
            return Geom:new{ w = sw, h = sh }
        end,
        paintTo = function(this, bb, x, y)
            bb:paintRoundedRect(x, y, sw, sh, Blitbuffer.COLOR_BLACK, 0)
        end
    }
    local dim_bg = AlphaContainer:new{
        alpha = 0.4,
        dim_child
    }

    local main_container = CenterContainer:new{
        dimen = Geom:new{ w = sw, h = sh },
        movable
    }

    local orig_paintTo = main_container.paintTo
    main_container.paintTo = function(this, bb, x, y)
        dim_bg:paintTo(bb, x, y)
        orig_paintTo(this, bb, x, y)
    end

    local orig_onCloseWidget = main_container.onCloseWidget
    main_container.onCloseWidget = function(this)
        dim_bg:onCloseWidget()
        if orig_onCloseWidget then
            orig_onCloseWidget(this)
        end
    end

    overlay = InputContainer:new{
        key_events = {
            Close = { { "Back" } }
        },
        main_container
    }
    UIManager:show(overlay, "ui")
end

return M
