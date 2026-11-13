--[[
    xray_style_cards.lua
    Interactive style cards, onboarding dialogs, and preview widgets for KOReader X-Ray Plugin.
--]]

local ok_ui, UIManager = pcall(require, "ui/uimanager")

local plugin_path = ((...) or ""):match("(.-)[^%.]+$") or ""

local M = {}

local function _t(self, key, default)
    if self and self.loc and self.loc.t then
        local res = self.loc:t(key)
        if res and res ~= key then return res end
    end
    return default
end

local findUnitConverterMenuPath

function M:showUnitStyleCard()
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
    local MovableContainer = require("ui/widget/container/movablecontainer")
    local GestureRange = require("ui/gesturerange")
    local VerticalSpan = require("ui/widget/verticalspan")
    local WidgetContainer = require("ui/widget/container/widgetcontainer")
    local RenderText = require("ui/rendertext")
    local OverlapGroup = require("ui/widget/overlapgroup")
    local LineWidget = require("ui/widget/linewidget")
    local Widget = require("ui/widget/widget")

    local xray_theme = require(plugin_path .. "xray_theme")

    local function sc(val)
        return Screen:scaleBySize(val)
    end

    local sw = Screen:getWidth()
    local sh = Screen:getHeight()
    local dialog_w = math.min(sw - sc(20), sc(380))

    local fs = 20
    if G_reader_settings then
        fs = G_reader_settings:readSetting("cre_font_size") or 20
    end
    -- Clamp UI fonts to reasonable sizes based on reader settings
    local ui_font_size = math.max(14, math.min(fs, 24))
    local label_font_size = math.max(11, math.min(fs - 4, 18))
    local title_font_size = math.max(10, math.min(fs - 5, 15))

    local overlay
    local focused_row = 1
    local focused_col = 1
    local refresh

    local row_definitions = {}

    refresh = function()
        local settings = self.ai_helper.settings or {}
        local underline_style = settings.unit_underline_style or "wavy"
        local underline_thickness = tonumber(settings.unit_underline_thickness) or 2
        local underline_intensity = settings.unit_underline_intensity or "light"
        local tooltip_timeout = tonumber(settings.unit_tooltip_timeout) or 4

        local function saveSetting(key, val)
            self.ai_helper:saveSettings({ [key] = val })
            local is_visual = (key == "unit_underline_style" or key == "unit_underline_thickness" or key == "unit_underline_intensity" or key == "unit_tooltip_timeout")
            if not is_visual then
                if self.scanBookForUnits then self:scanBookForUnits() end
            else
                if self.ui and self.ui.view and self.ui.view.dialog then
                    UIManager:setDirty(self.ui.view.dialog, "ui")
                end
            end
            refresh()
        end

        row_definitions = {
            {
                key = "unit_underline_style",
                options = {
                    { text = self.loc:t("unit_underline_solid") or "Solid", value = "solid" },
                    { text = self.loc:t("unit_underline_wavy") or "Wavy", value = "wavy" }
                },
                current = underline_style,
            },
            {
                key = "unit_underline_style",
                options = {
                    { text = self.loc:t("unit_underline_dotted") or "Dotted", value = "dotted" },
                    { text = self.loc:t("unit_underline_dashed") or "Dashed", value = "dashed" }
                },
                current = underline_style,
            },
            {
                key = "unit_underline_style",
                options = {
                    { text = self.loc:t("unit_underline_double") or "Double", value = "double" },
                    { text = self.loc:t("unit_underline_invisible") or "Invisible", value = "invisible" }
                },
                current = underline_style,
            },
            {
                key = "unit_underline_thickness",
                options = {
                    { text = "1px", value = 1 },
                    { text = "2px", value = 2 },
                    { text = "3px", value = 3 }
                },
                current = underline_thickness,
            },
            {
                key = "unit_underline_intensity",
                options = {
                    { text = self.loc:t("unit_intensity_light") or "Light", value = "light" },
                    { text = self.loc:t("unit_intensity_medium") or "Medium", value = "medium" },
                    { text = self.loc:t("unit_intensity_dark") or "Dark", value = "dark" }
                },
                current = underline_intensity,
            },
            {
                key = "unit_tooltip_timeout",
                options = {
                    { text = "2s", value = 2 },
                    { text = "4s", value = 4 },
                    { text = "8s", value = 8 },
                    { text = self.loc:t("unit_timeout_never") or "Never", value = 0 }
                },
                current = tooltip_timeout,
            },
            {
                key = "close",
                options = {
                    { text = self.loc:t("close") or "Close", value = "close" }
                },
                current = nil,
            }
        }

        local num_rows = #row_definitions
        if focused_row > num_rows then focused_row = num_rows end
        if focused_row < 1 then focused_row = 1 end

        local cur_row_opts = row_definitions[focused_row].options
        if focused_col > #cur_row_opts then focused_col = #cur_row_opts end
        if focused_col < 1 then focused_col = 1 end

        local function option_row(row_idx)
            local rdef = row_definitions[row_idx]
            local options = rdef.options
            local current = rdef.current
            local key = rdef.key

            local row = { align = "center" }
            for col_i, opt in ipairs(options) do
                if col_i > 1 then
                    table.insert(row, WidgetContainer:new{ dimen = Geom:new{ w = sc(12), h = 1 } })
                end
                local value = opt.value
                local is_selected = (value == current)
                local is_focused = (row_idx == focused_row and col_i == focused_col)
                local dot_char = is_selected and "●" or "○"
                
                local frame = FrameContainer:new{
                    bordersize = is_focused and (xray_theme.border_focus or sc(3)) or (is_selected and (xray_theme.border_btn or sc(1)) or sc(1)),
                    radius = xray_theme.radius_btn,
                    padding = sc(6),
                    color = is_focused and (xray_theme.color_focus_border or Blitbuffer.COLOR_BLACK) or (is_selected and xray_theme.color_border or xray_theme.color_section_rule),
                    background = is_focused and (xray_theme.color_focus_bg or Blitbuffer.Color8(215)) or (is_selected and Blitbuffer.Color8(240) or xray_theme.color_bg),
                    HorizontalGroup:new{
                        align = "center",
                        TextWidget:new{ text = dot_char, face = Font:getFace("cfont", ui_font_size), bold = is_focused or is_selected },
                        WidgetContainer:new{ dimen = Geom:new{ w = sc(4), h = 1 } },
                        TextWidget:new{ text = opt.text, face = Font:getFace("cfont", ui_font_size), bold = is_focused or is_selected },
                    }
                }
                local item = InputContainer:new{ frame }
                item.ges_events = {
                    Tap = {
                        GestureRange:new{
                            ges = "tap",
                            range = function() return frame.dimen end
                        }
                    }
                }
                item.onTap = function()
                    focused_row = row_idx
                    focused_col = col_i
                    saveSetting(key, value)
                    return true
                end
                table.insert(row, item)
            end
            return HorizontalGroup:new(row)
        end

        local UnderlinePreview = Widget:extend{
            width = 0,
            height = 0,
            underline_style = underline_style,
            underline_thickness = underline_thickness,
            underline_color_val = nil,
            plugin = nil,
        }
        function UnderlinePreview:getSize()
            return Geom:new{ w = self.width, h = self.height }
        end
        function UnderlinePreview:paintTo(bb, x, y)
            local plugin = self.plugin
            if plugin and plugin._draw_underline then
                local grey = 150
                if underline_intensity == "light" then
                    grey = 200
                elseif underline_intensity == "dark" then
                    grey = 30
                end
                local ok_ui, UIManager = pcall(require, "ui/uimanager")
                local thickness = Screen:scaleBySize(self.underline_thickness)
                local box = { x = x, y = y, w = self.width, h = self.height }
                plugin._draw_underline(bb, box, self.underline_style, grey, thickness, self.underline_thickness, plugin.path)
            end
        end

        local preview_face = Font:getFace("cfont", ui_font_size + 2)
        local before_text = TextWidget:new{
            text = "about ",
            face = preview_face,
        }
        local entity_text = TextWidget:new{
            text = "5 miles",
            face = preview_face,
        }
        local after_text = TextWidget:new{
            text = " away",
            face = preview_face,
        }

        local entity_size = (entity_text.getSize and entity_text:getSize()) or Geom:new{ w = sc(120), h = sc(24) }
        local underline_color_val
        if underline_intensity == "light" then
            underline_color_val = Blitbuffer.Color8(200)
        elseif underline_intensity == "dark" then
            underline_color_val = Blitbuffer.Color8(30)
        else
            underline_color_val = Blitbuffer.Color8(120)
        end

        local underline_widget = UnderlinePreview:new{
            width = entity_size.w,
            height = entity_size.h,
            underline_style = underline_style,
            underline_thickness = underline_thickness,
            underline_color_val = underline_color_val,
            plugin = self,
        }

        local entity_with_underline = OverlapGroup:new{
            dimen = entity_size,
            entity_text,
            underline_widget,
        }

        local preview_example = HorizontalGroup:new{
            align = "center",
            before_text,
            entity_with_underline,
            after_text,
        }

        local tooltip_text = "8.05 km"
        local tooltip_face = Font:getFace("cfont", fs)
        local pad_h = 28
        local pad_v = math.floor(fs * 0.55)
        local text_size = RenderText and RenderText.sizeUtf8Text and RenderText:sizeUtf8Text(0, 9999, tooltip_face, tooltip_text, false, false)
        local text_w = text_size and text_size.x or 70
        local tooltip_max_w = dialog_w - sc(64)
        local popup_w = math.min(tooltip_max_w, text_w + pad_h * 2)

        local tb = TextWidget:new{
            text = tooltip_text,
            face = tooltip_face,
        }

        local border_sz = sc(2)
        local preview_tooltip = FrameContainer:new{
            background = Blitbuffer.COLOR_WHITE,
            bordersize = border_sz,
            color = Blitbuffer.COLOR_DARK_GRAY,
            radius = 0,
            padding_top = pad_v,
            padding_bottom = pad_v,
            padding_left = pad_h,
            padding_right = pad_h,
            width = popup_w,
            VerticalGroup:new{
                align = "center",
                tb
            }
        }

        local card_size = (preview_tooltip.getSize and preview_tooltip:getSize()) or Geom:new{ w = popup_w, h = sc(50) }
        local card_h = card_size.h

        local arrow_w = sc(16)
        local arrow_h = sc(8)
        local _PointerArrow = self._PointerArrow or (require(plugin_path .. "xray_unitscanner")._PointerArrow)
        local preview_arrow = _PointerArrow and _PointerArrow:new{
            width = arrow_w,
            height = arrow_h,
            direction = "down",
            apex_offset = arrow_w / 2,
            border_size = border_sz,
            border_color = Blitbuffer.COLOR_DARK_GRAY,
            fill_color = Blitbuffer.COLOR_WHITE,
        }
        if preview_arrow then
            preview_arrow.overlap_offset = { math.floor((popup_w - arrow_w) / 2), card_h - border_sz }
        end

        local tooltip_with_arrow
        if preview_arrow then
            tooltip_with_arrow = OverlapGroup:new{
                dimen = Geom:new{ w = popup_w, h = card_h + arrow_h - border_sz },
                preview_tooltip,
                preview_arrow,
            }
        else
            tooltip_with_arrow = preview_tooltip
        end

        local preview_panel = FrameContainer:new{
            padding = sc(8),
            radius = xray_theme.radius_window,
            bordersize = xray_theme.border_preview,
            color = xray_theme.color_border,
            background = Blitbuffer.COLOR_WHITE,
            width = dialog_w - sc(28),
            VerticalGroup:new{
                align = "center",
                HorizontalGroup:new{
                    align = "center",
                    tooltip_with_arrow
                },
                VerticalSpan:new{ width = sc(2) },
                CenterContainer:new{
                    dimen = Geom:new{ w = dialog_w - sc(44), h = entity_size.h },
                    preview_example
                }
            }
        }

        local title_label = TextWidget:new{
            text = self.loc:t("unit_style_preview_title") or "STYLE PREVIEW",
            face = Font:getFace("cfont", ui_font_size - 1),
            bold = true,
            fgcolor = Blitbuffer.COLOR_BLACK,
        }

        local function label(str)
            return TextWidget:new{
                text = str,
                face = Font:getFace("cfont", ui_font_size - 2),
                bold = true,
                fgcolor = Blitbuffer.COLOR_BLACK,
            }
        end

        local function span()
            return VerticalSpan:new{ width = sc(6) }
        end

        local function divider()
            return LineWidget:new{
                dimen = Geom:new{ w = dialog_w - sc(28), h = xray_theme.border_line_h },
                background = xray_theme.color_section_rule,
            }
        end

        local style_row_1 = option_row(1)
        local style_row_2 = option_row(2)
        local style_row_3 = option_row(3)
        local thickness_row = option_row(4)
        local intensity_row = option_row(5)
        local timeout_row = option_row(6)

        local is_close_focused = (focused_row == 7)
        local close_btn = Button:new{
            text = self.loc:t("close") or "Close",
            face = Font:getFace("cfont", ui_font_size),
            bold = is_close_focused,
            width = dialog_w - sc(32),
            height = sc(42),
            bordersize = is_close_focused and (xray_theme.border_focus or sc(3)) or xray_theme.border_btn,
            color = is_close_focused and (xray_theme.color_focus_border or Blitbuffer.COLOR_BLACK) or xray_theme.color_border,
            background = is_close_focused and (xray_theme.color_focus_bg or Blitbuffer.Color8(215)) or nil,
            radius = xray_theme.radius_btn,
            callback = function()
                if overlay then overlay:onClose() end
            end
        }

        local card = FrameContainer:new{
            padding = sc(12),
            radius = xray_theme.radius_window,
            bordersize = sc(2),
            color = Blitbuffer.COLOR_BLACK,
            background = xray_theme.color_bg,
            width = dialog_w - sc(2),
            VerticalGroup:new{
                align = "left",
                title_label,
                span(),
                preview_panel,
                span(),
                label(self.loc:t("unit_underline_style_label") or "Underline Style"),
                style_row_1,
                WidgetContainer:new{ dimen = Geom:new{ w = 1, h = sc(4) } },
                style_row_2,
                WidgetContainer:new{ dimen = Geom:new{ w = 1, h = sc(4) } },
                style_row_3,
                span(),
                label(self.loc:t("unit_underline_thickness_label") or "Underline Thickness"),
                thickness_row,
                span(),
                label(self.loc:t("unit_underline_intensity_label") or "Underline Intensity"),
                intensity_row,
                span(),
                label(self.loc:t("unit_tooltip_timeout_label") or "Tooltip Timeout"),
                timeout_row,
                span(),
                divider(),
                span(),
                close_btn,
            }
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
        if self._styling_offset then
            movable:setMovedOffset(self._styling_offset)
        end

        local orig_handleEvent = movable.handleEvent
        movable.handleEvent = function(this, ev)
            local res = orig_handleEvent(this, ev)
            if ev.type == "Gesture" or ev.type == "Pan" or ev.type == "Hold" then
                self._styling_offset = this.moved_offset
            end
            return res
        end

        local main_center = CenterContainer:new{
            dimen = Geom:new{ w = sw, h = sh },
            movable
        }

        if overlay then
            overlay[1] = main_center
            UIManager:setDirty(overlay, "ui")
        else
            overlay = InputContainer:new{
                key_events = {
                    FocusUp = {
                        { "Up" },
                        { "PrevPage" },
                    },
                    FocusDown = {
                        { "Down" },
                        { "NextPage" },
                    },
                    FocusLeft = {
                        { "Left" },
                    },
                    FocusRight = {
                        { "Right" },
                    },
                    Select = {
                        { "Return" },
                        { "KP_Enter" },
                        { "Enter" },
                        { "Press" },
                        { "Select" },
                        { "Space" },
                    },
                    Close = {
                        { "Escape" },
                        { "Back" },
                        { "q" },
                        { "Q" },
                    },
                },
                main_center
            }

            if Device and Device.input and Device.input.group then
                if Device.input.group.Enter then table.insert(overlay.key_events.Select, { Device.input.group.Enter }) end
                if Device.input.group.Select then table.insert(overlay.key_events.Select, { Device.input.group.Select }) end
                if Device.input.group.Back then table.insert(overlay.key_events.Close, { Device.input.group.Back }) end
            end

            overlay.onFocusUp = function()
                if focused_row > 1 then
                    focused_row = focused_row - 1
                else
                    focused_row = num_rows
                end
                local opts = row_definitions[focused_row].options
                if focused_col > #opts then focused_col = #opts end
                refresh()
                return true
            end

            overlay.onFocusDown = function()
                if focused_row < num_rows then
                    focused_row = focused_row + 1
                else
                    focused_row = 1
                end
                local opts = row_definitions[focused_row].options
                if focused_col > #opts then focused_col = #opts end
                refresh()
                return true
            end

            overlay.onFocusLeft = function()
                local opts = row_definitions[focused_row].options
                if focused_col > 1 then
                    focused_col = focused_col - 1
                else
                    focused_col = #opts
                end
                refresh()
                return true
            end

            overlay.onFocusRight = function()
                local opts = row_definitions[focused_row].options
                if focused_col < #opts then
                    focused_col = focused_col + 1
                else
                    focused_col = 1
                end
                refresh()
                return true
            end

            overlay.onSelect = function()
                if focused_row <= 6 then
                    local rdef = row_definitions[focused_row]
                    local opt = rdef.options[focused_col]
                    if opt then
                        saveSetting(rdef.key, opt.value)
                    end
                else
                    overlay:onClose()
                end
                return true
            end

            function overlay:onClose()
                self._styling_offset = nil
                UIManager:close(overlay, "ui")
                return true
            end

            overlay.handleEvent = function(this, ev)
                if ev.type == "Key" or ev.type == "KeyPress" or ev.type == "KeyDown" then
                    local key = ev.key or ev.name or ev.sym
                    if key == "Return" or key == "KP_Enter" or key == "Enter" or key == "Select" or key == "Space" or key == "Press" then
                        return this:onSelect()
                    elseif key == "Up" or key == "PrevPage" or key == "PageUp" then
                        return this:onFocusUp()
                    elseif key == "Down" or key == "NextPage" or key == "PageDown" then
                        return this:onFocusDown()
                    elseif key == "Left" then
                        return this:onFocusLeft()
                    elseif key == "Right" then
                        return this:onFocusRight()
                    elseif key == "Escape" or key == "Back" or key == "q" or key == "Q" then
                        return this:onClose()
                    end
                end
                return InputContainer.handleEvent(this, ev)
            end

            UIManager:show(overlay, "ui")
        end
    end

    refresh()
end

function M:showUnitAutoScanCard()
    local XRaySettingsCard = require(plugin_path .. "xray_settings_card")
    local enabled_text = self.loc:t("unit_auto_scan_enabled") or "Enabled"
    local disabled_text = self.loc:t("unit_auto_scan_disabled") or "Disabled"
    XRaySettingsCard.show(self, {
        title = self.loc:t("unit_auto_scan_settings") or "Auto-Scan Settings",
        description = self.loc:t("unit_auto_scan_desc") or "Scan books for units automatically:",
        options = {
            { text = enabled_text, value = true },
            { text = disabled_text, value = false },
        },
        get_current_func = function()
            return self.ai_helper.settings.unit_auto_scan_enabled ~= false
        end,
        save_func = function(val)
            self.ai_helper:saveSettings({ unit_auto_scan_enabled = val })
        end,
        about_text = self.loc:t("unit_auto_scan_about") or "Scanning can take up to 15-20 seconds for large books. This only happens the first time the book is opened, and the results are saved for the future."
    })
end

function M:showUnitScanWrittenNumbersCard()
    local XRaySettingsCard = require(plugin_path .. "xray_settings_card")
    local enabled_text = self.loc:t("unit_scan_written_enabled") or "Enabled"
    local disabled_text = self.loc:t("unit_scan_written_disabled") or "Disabled"
    XRaySettingsCard.show(self, {
        title = self.loc:t("unit_scan_written_numbers_title") or "Scan Written Numbers",
        description = self.loc:t("unit_scan_written_numbers_desc") or "Scan for spelled-out numbers (e.g. 'five miles'):",
        options = {
            { text = enabled_text, value = true },
            { text = disabled_text, value = false },
        },
        get_current_func = function()
            local settings = self.ai_helper.settings
            if settings.unit_scan_written_numbers ~= nil then
                return settings.unit_scan_written_numbers == true
            end
            local xray_utils = require(plugin_path .. "xray_utils")
            return not xray_utils:isLowPowerForScan()
        end,
        save_func = function(val)
            self.ai_helper:saveSettings({ unit_scan_written_numbers = val })
            if self.scanBookForUnits then self:scanBookForUnits() end
        end,
        about_text = self.loc:t("unit_scan_written_numbers_about") or "Scanning written-out numbers (like 'five miles') requires a second full-text pass. Skipping this pass on lower-powered devices (Kindle, Kobo, PocketBook) provides a 4x to 5x scan speedup and prevents startup freezes. On faster platforms like Android or desktops, there is no noticeable slowdown."
    })
end

function M:showPopupFontSizeCard()
    local XRaySettingsCard = require(plugin_path .. "xray_settings_card")
    XRaySettingsCard.show(self, {
        title = self.loc:t("menu_popup_font_size") or "Popup Font Size",
        description = self.loc:t("popup_font_size_desc") or "Adjust font size for footnote popups and detail dialogs:",
        options = {
            { text = self.loc:t("popup_font_size_auto") or "Auto (Recommended)", value = "auto" },
            { text = self.loc:t("popup_font_size_small") or "Small", value = "small" },
            { text = self.loc:t("popup_font_size_normal") or "Normal", value = "normal" },
            { text = self.loc:t("popup_font_size_large") or "Large", value = "large" },
            { text = self.loc:t("popup_font_size_xlarge") or "Extra Large", value = "xlarge" },
        },
        get_current_func = function()
            local s = self.ai_helper and self.ai_helper.settings
            return (s and s.popup_font_size) or "auto"
        end,
        save_func = function(val)
            if self.ai_helper then
                if self.ai_helper.saveSettings then
                    self.ai_helper:saveSettings({ popup_font_size = val })
                elseif self.ai_helper.settings then
                    self.ai_helper.settings.popup_font_size = val
                end
            end
        end,
        about_text = self.loc:t("popup_font_size_about") or "Popup font sizes automatically adjust based on your current book font size and optimize for languages with complex scripts like Arabic. Use this setting to adjust the overall display to your reading preference."
    })
end

-- Resolves the exact touch menu path (e.g. "4.1.8.6") to an X-Ray submenu
local function findXRayMenuPath(self, target_key)
    if not self.ui or not self.ui.menu then return nil end
    if not target_key or target_key == "xray" then
        return "xray"
    end
    local reader_menu = self.ui.menu
    if not reader_menu.tab_item_table then
        reader_menu:setUpdateItemTable()
    end
    local tab_item_table = reader_menu.tab_item_table
    if not tab_item_table then return nil end

    local function searchMenu(items, current_path)
        for idx, item in ipairs(items) do
            local path = current_path == "" and tostring(idx) or (current_path .. "." .. idx)
            if target_key == "unit_converter" and item.is_unit_converter then
                return path
            elseif target_key == "entity_footnotes" and item.is_entity_footnotes then
                return path
            elseif target_key == "api_keys" and (item.is_api_keys or (item.text and item.text:find("API Keys"))) then
                return path
            end
            local submenu = item.sub_item_table
            if not submenu and type(item.sub_item_table_func) == "function" then
                submenu = item.sub_item_table_func()
            end
            if submenu then
                local found = searchMenu(submenu, path)
                if found then
                    return found
                end
            end
        end
        return nil
    end

    for tab_idx, tab_items in ipairs(tab_item_table) do
        for item_idx, item in ipairs(tab_items) do
            if item.id == "xray" then
                local submenu = item.sub_item_table
                if not submenu and type(item.sub_item_table_func) == "function" then
                    submenu = item.sub_item_table_func()
                end
                if submenu then
                    local sub_path = searchMenu(submenu, "")
                    if sub_path then
                        local path = string.format("%d.%d.%s", tab_idx, item_idx, sub_path)
                        self:log("XRayPlugin: findXRayMenuPath resolved path: " .. tostring(path))
                        return path
                    end
                end
            end
        end
    end
    self:log("XRayPlugin: findXRayMenuPath failed to resolve path for " .. tostring(target_key))
    return nil
end

function M:openReaderMenuToPath(target_key)
    local UIManager = require("ui/uimanager")
    if self.xray_menu then
        pcall(function() UIManager:close(self.xray_menu) end)
        self.xray_menu = nil
    end

    UIManager:scheduleIn(0.1, function()
        if self.destroyed or not self.ui or not self.ui.document then return end
        if not (self.ui and self.ui.menu) then
            if self.showFullXRayMenuStandalone then
                self:showFullXRayMenuStandalone()
            end
            return
        end

        local reader_menu = self.ui.menu
        if not reader_menu.tab_item_table then
            reader_menu:setUpdateItemTable()
        end
        local tab_item_table = reader_menu.tab_item_table
        if not tab_item_table then
            if self.showFullXRayMenuStandalone then
                self:showFullXRayMenuStandalone()
            end
            return
        end

        local xray_tab_idx, xray_item_idx, xray_item
        for tab_idx, tab_items in ipairs(tab_item_table) do
            for item_idx, item in ipairs(tab_items) do
                if item.id == "xray" then
                    xray_tab_idx = tab_idx
                    xray_item_idx = item_idx
                    xray_item = item
                    break
                end
            end
            if xray_tab_idx then break end
        end

        if not xray_tab_idx or not xray_item then
            self:log("XRayPlugin: Unable to locate X-Ray in reader menu, falling back to standalone menu")
            if self.showFullXRayMenuStandalone then
                self:showFullXRayMenuStandalone()
            end
            return
        end

        if not reader_menu.menu_container then
            reader_menu:onShowMenu(xray_tab_idx)
        end

        local touch_menu = reader_menu.menu_container and reader_menu.menu_container[1]
        if not touch_menu then return end

        if not target_key or target_key == "xray" then
            if touch_menu.switchMenuTab then
                touch_menu:switchMenuTab(xray_tab_idx)
                if touch_menu.bar and touch_menu.bar.switchToTab then
                    touch_menu.bar:switchToTab(xray_tab_idx)
                end
            end
            xray_item.idx = xray_item.idx or xray_item_idx
            if touch_menu.onMenuSelect then
                touch_menu:onMenuSelect(xray_item)
            end
        else
            local path = findXRayMenuPath(self, target_key)
            if path and touch_menu.openMenu then
                touch_menu:openMenu(path, false)
            end
        end
    end)
end

findUnitConverterMenuPath = function(self)
    return findXRayMenuPath(self, "unit_converter")
end

-- Shows the "New Feature" promotion card for the Unit Converter
function M:showUnitConverterNewFeatureCard()
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
    local xray_theme = require(plugin_path .. "xray_theme")

    local function sc(val)
        return Screen:scaleBySize(val)
    end

    local sw = Screen:getWidth()
    local sh = Screen:getHeight()
    local dialog_w = math.min(sw - sc(20), sc(460))

    local fs = 20
    if G_reader_settings then
        fs = G_reader_settings:readSetting("cre_font_size") or 20
    end
    local ui_font_size = math.max(14, math.min(fs, 24))
    local title_font_size = math.max(10, math.min(fs - 5, 15))

    local overlay
    local settings = self.ai_helper and self.ai_helper.settings or {}
    local is_enabled = settings.unit_converter_enabled ~= false
    local selected_action = is_enabled and "keep_enabled" or "disable"
    local focused_index = 1

    local function span()
        return VerticalSpan:new{ width = xray_theme.gap }
    end

    -- 2. Main layout loop
    local function renderCard()
        local title_label = TextWidget:new{
            text = (self.loc:t("new_feature") or "New Feature"):upper(),
            face = Font:getFace("infofont", title_font_size),
            fgcolor = xray_theme.color_label_dim or Blitbuffer.Color8(120),
        }

        local headline_label = TextWidget:new{
            text = self.loc:t("unit_conv_headline") or "Unit Converter",
            face = Font:getFace("cfont", ui_font_size + 2),
            bold = true,
            fgcolor = Blitbuffer.COLOR_BLACK,
        }

        local description_box = TextBoxWidget:new{
            text = self.loc:t("unit_conv_new_feature_desc") or "X-Ray now detects measurements (lengths, weights, temperature) in your books and highlights them with a subtle underline. Tap any highlighted unit to see its converted value in a popup tooltip.\n\nNote: A scan is required the first time a book is opened.",
            face = Font:getFace("cfont", ui_font_size),
            width = dialog_w - sc(32),
            alignment = self:isRTL() and "right" or "left",
        }

        -- Construct live preview widget elements
        local Widget = require("ui/widget/widget")
        local OverlapGroup = require("ui/widget/overlapgroup")
        local RenderText = require("ui/rendertext")

        local settings = self.ai_helper and self.ai_helper.settings or {}
        local underline_style = settings.unit_underline_style or "wavy"
        local underline_thickness = tonumber(settings.unit_underline_thickness) or 2
        local underline_intensity = settings.unit_underline_intensity or "light"

        local UnderlinePreview = Widget:extend{
            width = 0,
            height = 0,
            underline_style = underline_style,
            underline_thickness = underline_thickness,
            underline_color_val = nil,
            plugin = nil,
        }
        function UnderlinePreview:getSize()
            return Geom:new{ w = self.width, h = self.height }
        end
        function UnderlinePreview:paintTo(bb, x, y)
            local plugin = self.plugin
            if plugin and plugin._draw_underline then
                local grey = 150
                if underline_intensity == "light" then
                    grey = 200
                elseif underline_intensity == "dark" then
                    grey = 30
                end
                local thickness = Screen:scaleBySize(self.underline_thickness)
                local box = { x = x, y = y, w = self.width, h = self.height }
                plugin._draw_underline(bb, box, self.underline_style, grey, thickness, self.underline_thickness, plugin.path)
            end
        end

        local preview_face = Font:getFace("cfont", ui_font_size + 2)
        local sample_text = TextWidget:new{
            text = "walked 2 miles today",
            face = preview_face,
            alignment = "center",
        }
        local sample_size = (sample_text.getSize and sample_text:getSize()) or Geom:new{ w = sc(200), h = sc(24) }

        local underline_color_val
        if underline_intensity == "light" then
            underline_color_val = Blitbuffer.Color8(200)
        elseif underline_intensity == "dark" then
            underline_color_val = Blitbuffer.Color8(30)
        else
            underline_color_val = Blitbuffer.Color8(120)
        end

        local w_walked = RenderText:sizeUtf8Text(0, 9999, preview_face, "walked ", false, false).x
        local w_miles = RenderText:sizeUtf8Text(0, 9999, preview_face, "2 miles", false, false).x

        local underline_widget = UnderlinePreview:new{
            width = w_miles,
            height = sample_size.h,
            underline_style = underline_style,
            underline_thickness = underline_thickness,
            underline_color_val = underline_color_val,
            overlap_offset = { w_walked, 0 },
            plugin = self,
        }

        local preview_example = OverlapGroup:new{
            dimen = sample_size,
            sample_text,
            underline_widget,
        }

        local tooltip_text = "3.22 km"
        local tooltip_face = Font:getFace("cfont", fs)
        local pad_h = 28
        local pad_v = math.floor(fs * 0.55)
        local text_size = RenderText:sizeUtf8Text(0, 9999, tooltip_face, tooltip_text, false, false)
        local text_w = text_size.x
        local tooltip_max_w = dialog_w - sc(64)
        local popup_w = math.min(tooltip_max_w, text_w + pad_h * 2)

        local tb = TextWidget:new{
            text = tooltip_text,
            face = tooltip_face,
        }

        local border_sz = sc(2)
        local preview_tooltip = FrameContainer:new{
            background = Blitbuffer.COLOR_WHITE,
            bordersize = border_sz,
            color = Blitbuffer.COLOR_DARK_GRAY,
            radius = 0,
            padding_top = pad_v,
            padding_bottom = pad_v,
            padding_left = pad_h,
            padding_right = pad_h,
            width = popup_w,
            VerticalGroup:new{
                align = "center",
                tb
            }
        }

        local card_size = (preview_tooltip.getSize and preview_tooltip:getSize()) or Geom:new{ w = popup_w, h = sc(50) }
        local card_h = card_size.h

        local arrow_w = sc(16)
        local arrow_h = sc(8)
        local _PointerArrow = self._PointerArrow
        local preview_arrow = _PointerArrow:new{
            width = arrow_w,
            height = arrow_h,
            direction = "down",
            apex_offset = arrow_w / 2,
            border_size = border_sz,
            border_color = Blitbuffer.COLOR_DARK_GRAY,
            fill_color = Blitbuffer.COLOR_WHITE,
        }
        preview_arrow.overlap_offset = { math.floor((popup_w - arrow_w) / 2), card_h - border_sz }

        local tooltip_with_arrow = OverlapGroup:new{
            dimen = Geom:new{ w = popup_w, h = card_h + arrow_h - border_sz },
            preview_tooltip,
            preview_arrow,
        }

        local preview_panel = FrameContainer:new{
            padding = sc(8),
            radius = xray_theme.radius_window,
            bordersize = xray_theme.border_preview,
            color = xray_theme.color_border,
            background = Blitbuffer.COLOR_WHITE,
            width = dialog_w - sc(32),
            VerticalGroup:new{
                align = "center",
                HorizontalGroup:new{
                    align = "center",
                    tooltip_with_arrow
                },
                VerticalSpan:new{ width = sc(2) },
                CenterContainer:new{
                    dimen = Geom:new{ w = dialog_w - sc(48), h = sample_size.h },
                    preview_example
                }
            }
        }

        local content_vg = VerticalGroup:new{
            align = "left",
            title_label,
            span(),
            headline_label,
            span(),
            description_box,
            span(),
            preview_panel,
            span(),
        }

        local choices = {
            { text = self.loc:t("unit_action_configure") or "Configure Settings...", value = "configure" },
            { text = self.loc:t("unit_action_keep") or "Keep Enabled (Default)", value = "keep_enabled" },
            { text = self.loc:t("unit_action_disable") or "Disable Feature", value = "disable" },
        }

        for idx, choice in ipairs(choices) do
            local is_selected = (choice.value == selected_action)
            local is_focused = (idx == focused_index)
            local dot_char = is_selected and "●" or "○"

            local row_content = HorizontalGroup:new{ align = "center" }
            if self:isRTL() then
                table.insert(row_content, TextBoxWidget:new{
                    text = choice.text,
                    face = Font:getFace("cfont", ui_font_size),
                    fgcolor = Blitbuffer.COLOR_BLACK,
                    width = dialog_w - sc(72),
                    alignment = "right",
                })
                table.insert(row_content, WidgetContainer:new{ dimen = Geom:new{ w = sc(6), h = 1 } })
                table.insert(row_content, TextWidget:new{
                    text = dot_char,
                    face = Font:getFace("cfont", ui_font_size),
                })
            else
                table.insert(row_content, TextWidget:new{
                    text = dot_char,
                    face = Font:getFace("cfont", ui_font_size),
                })
                table.insert(row_content, WidgetContainer:new{ dimen = Geom:new{ w = sc(6), h = 1 } })
                table.insert(row_content, TextBoxWidget:new{
                    text = choice.text,
                    face = Font:getFace("cfont", ui_font_size),
                    fgcolor = Blitbuffer.COLOR_BLACK,
                    width = dialog_w - sc(72),
                    alignment = "left",
                })
            end

            local frame = FrameContainer:new{
                bordersize = is_focused and (xray_theme.border_focus or sc(2)) or (is_selected and xray_theme.border_btn or sc(1)),
                radius = xray_theme.radius_btn,
                padding = sc(6),
                color = is_focused and (xray_theme.color_focus_border or Blitbuffer.COLOR_BLACK) or (is_selected and xray_theme.color_border or xray_theme.color_section_rule),
                background = is_focused and (xray_theme.color_focus_bg or Blitbuffer.Color8(230)) or xray_theme.color_bg,
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
                focused_index = idx
                selected_action = choice.value
                renderCard()
                return true
            end

            table.insert(content_vg, item)
            table.insert(content_vg, WidgetContainer:new{ dimen = Geom:new{ w = 1, h = sc(4) } })
        end

        table.insert(content_vg, span())
        table.insert(content_vg, LineWidget:new{
            dimen = Geom:new{ w = dialog_w - sc(32), h = sc(1) },
            background = xray_theme.color_section_rule,
        })
        table.insert(content_vg, span())

        local is_later_focused = (focused_index == 4)
        local is_confirm_focused = (focused_index == 5)

        -- Action Buttons (Confirm & Ask Later)
        local confirm_btn = Button:new{
            text = self.loc:t("confirm") or "Confirm",
            face = Font:getFace("cfont", ui_font_size),
            width = (dialog_w - sc(40)) / 2,
            height = sc(42),
            bordersize = is_confirm_focused and (xray_theme.border_focus or sc(2)) or xray_theme.border_btn,
            background = is_confirm_focused and (xray_theme.color_focus_bg or Blitbuffer.Color8(230)) or nil,
            radius = xray_theme.radius_btn,
            callback = function()
                if overlay then
                    UIManager:close(overlay, "ui")
                    overlay = nil
                end

                if selected_action == "configure" then
                    self.ai_helper:saveSettings({
                        unit_new_feature_prompt_seen = true,
                        unit_converter_enabled = true,
                    })
                    if self.scanBookForUnits then self:scanBookForUnits() end
                    
                    UIManager:scheduleIn(0.1, function()
                        if self.destroyed or not self.ui or not self.ui.document then return end
                        if self.ui and self.ui.menu then
                            if not self.ui.menu.menu_container then
                                self.ui.menu:onShowMenu()
                            end
                            local touch_menu = self.ui.menu.menu_container and self.ui.menu.menu_container[1]
                            if touch_menu then
                                local path = findUnitConverterMenuPath(self)
                                if path then
                                    touch_menu:openMenu(path, false)
                                end
                            end
                        end
                    end)
                elseif selected_action == "keep_enabled" then
                    self.ai_helper:saveSettings({
                        unit_new_feature_prompt_seen = true,
                        unit_converter_enabled = true,
                    })
                    if self.scanBookForUnits then self:scanBookForUnits() end
                elseif selected_action == "disable" then
                    self.ai_helper:saveSettings({
                        unit_new_feature_prompt_seen = true,
                        unit_converter_enabled = false,
                    })
                    if self.clearUnitUnderlines then self:clearUnitUnderlines() end
                else
                    self.ai_helper:saveSettings({ unit_new_feature_prompt_seen = true })
                end
            end
        }

        local later_btn = Button:new{
            text = self.loc:t("ask_later") or "Ask Later",
            face = Font:getFace("cfont", ui_font_size),
            width = (dialog_w - sc(40)) / 2,
            height = sc(42),
            bordersize = is_later_focused and (xray_theme.border_focus or sc(2)) or xray_theme.border_btn,
            background = is_later_focused and (xray_theme.color_focus_bg or Blitbuffer.Color8(230)) or nil,
            radius = xray_theme.radius_btn,
            callback = function()
                if overlay then
                    UIManager:close(overlay, "ui")
                    overlay = nil
                end
                if self.scanBookForUnits and (self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.unit_converter_enabled ~= false) then
                    self:scanBookForUnits()
                end
            end
        }

        local btn_row = HorizontalGroup:new{
            align = "center",
            later_btn,
            WidgetContainer:new{ dimen = Geom:new{ w = sc(8), h = 1 } },
            confirm_btn,
        }
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

        local main_center = CenterContainer:new{
            dimen = Geom:new{ w = sw, h = sh },
            MovableContainer:new{ card_outer }
        }

        if overlay then
            overlay[1] = main_center
            UIManager:setDirty(overlay, "ui")
        else
            overlay = InputContainer:new{
                key_events = {
                    FocusUp = {
                        { "Up" },
                        { "PrevPage" },
                    },
                    FocusDown = {
                        { "Down" },
                        { "NextPage" },
                    },
                    FocusLeft = {
                        { "Left" },
                    },
                    FocusRight = {
                        { "Right" },
                    },
                    Select = {
                        { "Return" },
                        { "KP_Enter" },
                        { "Enter" },
                        { "Press" },
                        { "Select" },
                        { "Space" },
                    },
                    Close = {
                        { "Escape" },
                        { "Back" },
                        { "q" },
                        { "Q" },
                    },
                },
                main_center
            }

            if Device and Device.input and Device.input.group then
                if Device.input.group.Enter then table.insert(overlay.key_events.Select, { Device.input.group.Enter }) end
                if Device.input.group.Select then table.insert(overlay.key_events.Select, { Device.input.group.Select }) end
                if Device.input.group.Back then table.insert(overlay.key_events.Close, { Device.input.group.Back }) end
            end

            overlay.onFocusUp = function()
                if focused_index > 1 then
                    focused_index = focused_index - 1
                else
                    focused_index = 5
                end
                renderCard()
                return true
            end

            overlay.onFocusDown = function()
                if focused_index < 5 then
                    focused_index = focused_index + 1
                else
                    focused_index = 1
                end
                renderCard()
                return true
            end

            overlay.onFocusLeft = function()
                if focused_index == 5 then
                    focused_index = 4
                    renderCard()
                end
                return true
            end

            overlay.onFocusRight = function()
                if focused_index == 4 then
                    focused_index = 5
                    renderCard()
                end
                return true
            end

            overlay.onSelect = function()
                if focused_index >= 1 and focused_index <= 3 then
                    selected_action = choices[focused_index].value
                    renderCard()
                elseif focused_index == 4 then
                    later_btn.callback()
                elseif focused_index == 5 then
                    confirm_btn.callback()
                end
                return true
            end

            overlay.onClose = function()
                if overlay then
                    UIManager:close(overlay, "ui")
                    overlay = nil
                end
                if self.scanBookForUnits and (self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.unit_converter_enabled ~= false) then
                    self:scanBookForUnits()
                end
                return true
            end

            overlay.handleEvent = function(this, ev)
                if ev.type == "Key" or ev.type == "KeyPress" or ev.type == "KeyDown" then
                    local key = ev.key or ev.name or ev.sym
                    if key == "Return" or key == "KP_Enter" or key == "Enter" or key == "Select" or key == "Space" or key == "Press" then
                        return this:onSelect()
                    elseif key == "Up" or key == "PrevPage" or key == "PageUp" then
                        return this:onFocusUp()
                    elseif key == "Down" or key == "NextPage" or key == "PageDown" then
                        return this:onFocusDown()
                    elseif key == "Left" then
                        return this:onFocusLeft()
                    elseif key == "Right" then
                        return this:onFocusRight()
                    elseif key == "Escape" or key == "Back" or key == "q" or key == "Q" then
                        return this:onClose()
                    end
                end
                return InputContainer.handleEvent(this, ev)
            end

            UIManager:show(overlay, "ui")
        end
    end

    renderCard()
end

-- --- Entity Footnotes UI & Settings Cards ---

function M:showEntityPopupStyleCard()
    local XRaySettingsCard = require(plugin_path .. "xray_settings_card")
    XRaySettingsCard.show(self, {
        title = self.loc:t("entity_popup_style_title") or "Popup Display Style",
        description = "Select how entity details are displayed when tapping an underlined entity in the book:",
        options = {
            { text = self.loc:t("entity_popup_style_footnote") or "Footnote Panel (Full Actions)", value = "footnote" },
            { text = self.loc:t("entity_popup_style_tooltip") or "Compact Tooltip (Bubble)", value = "tooltip" },
        },
        get_current_func = function()
            return self.ai_helper.settings.entity_popup_style or "footnote"
        end,
        save_func = function(val)
            self.ai_helper:saveSettings({ entity_popup_style = val })
        end,
        about_text = "• [B]Footnote Panel (Full Actions):[/B] Opens the standard X-Ray bottom panel with actions for Occurrences, Timeline, Story Arc, Wikipedia, and AI Ask.\n\n• [B]Compact Tooltip (Bubble):[/B] Displays a pointing arrow bubble directly over/under the tapped name with an auto-dismiss timer.",
    })
end

function M:showEntityMentionModeCard()
    local XRaySettingsCard = require(plugin_path .. "xray_settings_card")
    XRaySettingsCard.show(self, {
        title = self.loc:t("entity_mention_mode_title") or "Mention Display Mode",
        description = "Select how often entity mentions are underlined on each page:",
        options = {
            { text = self.loc:t("entity_mention_mode_all") or "All Mentions per Page", value = "all" },
            { text = self.loc:t("entity_mention_mode_first") or "First Mention per Page Only", value = "first" },
        },
        get_current_func = function()
            return self.ai_helper.settings.entity_mention_mode or "all"
        end,
        save_func = function(val)
            self.ai_helper:saveSettings({ entity_mention_mode = val })
            self._entity_box_cache_sig = nil
            if self.ui and self.ui.view and self.ui.view.dialog then
                UIManager:setDirty(self.ui.view.dialog, "ui")
            end
        end,
        about_text = "• [B]All Mentions per Page:[/B] Underlines every occurrence of recognized characters, locations, and terms on each page.\n\n• [B]First Mention per Page Only:[/B] Underlines only the first appearance of each unique entity per page, preventing repeated names from cluttering paragraphs.",
    })
end

function M:showEntityStyleCard()
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
    local MovableContainer = require("ui/widget/container/movablecontainer")
    local GestureRange = require("ui/gesturerange")
    local VerticalSpan = require("ui/widget/verticalspan")
    local WidgetContainer = require("ui/widget/container/widgetcontainer")
    local RenderText = require("ui/rendertext")
    local OverlapGroup = require("ui/widget/overlapgroup")
    local LineWidget = require("ui/widget/linewidget")
    local Widget = require("ui/widget/widget")
    local Device = require("device")

    local xray_theme = require(plugin_path .. "xray_theme")

    local function sc(val)
        return Screen:scaleBySize(val)
    end

    local sw = Screen:getWidth()
    local sh = Screen:getHeight()
    local dialog_w = math.min(sw - sc(20), sc(380))

    local fs = 20
    if G_reader_settings then
        fs = G_reader_settings:readSetting("cre_font_size") or 20
    end
    -- Clamp UI fonts to reasonable sizes based on reader settings
    local ui_font_size = math.max(14, math.min(fs, 24))
    local label_font_size = math.max(11, math.min(fs - 4, 18))
    local title_font_size = math.max(10, math.min(fs - 5, 15))

    local overlay
    local focused_row = 1
    local focused_col = 1
    local refresh

    local row_definitions = {}

    refresh = function()
        local settings = self.ai_helper.settings or {}
        local underline_style = settings.entity_underline_style or "wavy"
        local underline_thickness = tonumber(settings.entity_underline_thickness) or 2
        local underline_intensity = settings.entity_underline_intensity or "light"
        local tooltip_timeout = tonumber(settings.entity_tooltip_timeout) or 4

        local function saveSetting(key, val)
            self.ai_helper:saveSettings({ [key] = val })
            self._entity_box_cache_sig = nil
            if self.ui and self.ui.view and self.ui.view.dialog then
                UIManager:setDirty(self.ui.view.dialog, "ui")
            end
            refresh()
        end

        row_definitions = {
            {
                key = "entity_underline_style",
                options = {
                    { text = self.loc:t("unit_underline_solid") or "Solid", value = "solid" },
                    { text = self.loc:t("unit_underline_wavy") or "Wavy", value = "wavy" }
                },
                current = underline_style,
            },
            {
                key = "entity_underline_style",
                options = {
                    { text = self.loc:t("unit_underline_dotted") or "Dotted", value = "dotted" },
                    { text = self.loc:t("unit_underline_dashed") or "Dashed", value = "dashed" }
                },
                current = underline_style,
            },
            {
                key = "entity_underline_style",
                options = {
                    { text = self.loc:t("unit_underline_double") or "Double", value = "double" },
                    { text = self.loc:t("unit_underline_invisible") or "Invisible", value = "invisible" }
                },
                current = underline_style,
            },
            {
                key = "entity_underline_thickness",
                options = {
                    { text = "1px", value = 1 },
                    { text = "2px", value = 2 },
                    { text = "3px", value = 3 }
                },
                current = underline_thickness,
            },
            {
                key = "entity_underline_intensity",
                options = {
                    { text = self.loc:t("unit_intensity_light") or "Light", value = "light" },
                    { text = self.loc:t("unit_intensity_medium") or "Medium", value = "medium" },
                    { text = self.loc:t("unit_intensity_dark") or "Dark", value = "dark" }
                },
                current = underline_intensity,
            },
            {
                key = "entity_tooltip_timeout",
                options = {
                    { text = "2s", value = 2 },
                    { text = "4s", value = 4 },
                    { text = "8s", value = 8 },
                    { text = self.loc:t("unit_timeout_never") or "Never", value = 0 }
                },
                current = tooltip_timeout,
            },
            {
                key = "close",
                options = {
                    { text = self.loc:t("close") or "Close", value = "close" }
                },
                current = nil,
            }
        }

        local num_rows = #row_definitions
        if focused_row > num_rows then focused_row = num_rows end
        if focused_row < 1 then focused_row = 1 end

        local cur_row_opts = row_definitions[focused_row].options
        if focused_col > #cur_row_opts then focused_col = #cur_row_opts end
        if focused_col < 1 then focused_col = 1 end

        local function option_row(row_idx)
            local rdef = row_definitions[row_idx]
            local options = rdef.options
            local current = rdef.current
            local key = rdef.key

            local row = { align = "center" }
            for col_i, opt in ipairs(options) do
                if col_i > 1 then
                    table.insert(row, WidgetContainer:new{ dimen = Geom:new{ w = sc(12), h = 1 } })
                end
                local value = opt.value
                local is_selected = (value == current)
                local is_focused = (row_idx == focused_row and col_i == focused_col)
                local dot_char = is_selected and "●" or "○"

                local frame = FrameContainer:new{
                    bordersize = is_focused and (xray_theme.border_focus or sc(3)) or (is_selected and (xray_theme.border_btn or sc(1)) or sc(1)),
                    radius = xray_theme.radius_btn,
                    padding = sc(6),
                    color = is_focused and (xray_theme.color_focus_border or Blitbuffer.COLOR_BLACK) or (is_selected and xray_theme.color_border or xray_theme.color_section_rule),
                    background = is_focused and (xray_theme.color_focus_bg or Blitbuffer.Color8(215)) or (is_selected and Blitbuffer.Color8(240) or xray_theme.color_bg),
                    HorizontalGroup:new{
                        align = "center",
                        TextWidget:new{ text = dot_char, face = Font:getFace("cfont", ui_font_size), bold = is_focused or is_selected },
                        WidgetContainer:new{ dimen = Geom:new{ w = sc(4), h = 1 } },
                        TextWidget:new{ text = opt.text, face = Font:getFace("cfont", ui_font_size), bold = is_focused or is_selected },
                    }
                }
                local item = InputContainer:new{ frame }
                item.ges_events = {
                    Tap = {
                        GestureRange:new{
                            ges = "tap",
                            range = function() return frame.dimen end
                        }
                    }
                }
                item.onTap = function()
                    focused_row = row_idx
                    focused_col = col_i
                    saveSetting(key, value)
                    return true
                end
                table.insert(row, item)
            end
            return HorizontalGroup:new(row)
        end

        local UnderlinePreview = Widget:extend{
            width = 0,
            height = 0,
            underline_style = underline_style,
            underline_thickness = underline_thickness,
            underline_color_val = nil,
            plugin = nil,
        }
        function UnderlinePreview:getSize()
            return Geom:new{ w = self.width, h = self.height }
        end
        function UnderlinePreview:paintTo(bb, x, y)
            local plugin = self.plugin
            local draw_fn = plugin and plugin._draw_underline or (require(plugin_path .. "xray_unitscanner")._draw_underline)
            if draw_fn and self.underline_style ~= "invisible" then
                local grey = 150
                if underline_intensity == "light" then
                    grey = 200
                elseif underline_intensity == "dark" then
                    grey = 30
                end
                local ok_ui, UIManager = pcall(require, "ui/uimanager")
                local raw_th = tonumber(self.underline_thickness) or 2
                local thickness = Screen:scaleBySize(raw_th)
                local box = { x = x, y = y, w = self.width, h = self.height }
                draw_fn(bb, box, self.underline_style, grey, thickness, raw_th, plugin and plugin.path)
            end
        end

        local preview_face = Font:getFace("cfont", ui_font_size + 2)
        local before_text = TextWidget:new{
            text = "with ",
            face = preview_face,
        }
        local entity_text = TextWidget:new{
            text = "Sherlock Holmes",
            face = preview_face,
        }
        local after_text = TextWidget:new{
            text = " here",
            face = preview_face,
        }

        local entity_size = (entity_text.getSize and entity_text:getSize()) or Geom:new{ w = sc(120), h = sc(24) }
        local underline_color_val
        if underline_intensity == "light" then
            underline_color_val = Blitbuffer.Color8(200)
        elseif underline_intensity == "dark" then
            underline_color_val = Blitbuffer.Color8(30)
        else
            underline_color_val = Blitbuffer.Color8(120)
        end

        local underline_widget = UnderlinePreview:new{
            width = entity_size.w,
            height = entity_size.h,
            underline_style = underline_style,
            underline_thickness = underline_thickness,
            underline_color_val = underline_color_val,
            plugin = self,
        }

        local entity_with_underline = OverlapGroup:new{
            dimen = entity_size,
            entity_text,
            underline_widget,
        }

        local preview_example = HorizontalGroup:new{
            align = "center",
            before_text,
            entity_with_underline,
            after_text,
        }

        local tooltip_text = "Sherlock Holmes"
        local tooltip_face = Font:getFace("cfont", fs)
        local pad_h = 28
        local pad_v = math.floor(fs * 0.55)
        local text_size = RenderText and RenderText.sizeUtf8Text and RenderText:sizeUtf8Text(0, 9999, tooltip_face, tooltip_text, false, false)
        local text_w = text_size and text_size.x or 70
        local tooltip_max_w = dialog_w - sc(64)
        local popup_w = math.min(tooltip_max_w, text_w + pad_h * 2)

        local tb = TextWidget:new{
            text = tooltip_text,
            face = tooltip_face,
        }

        local border_sz = sc(2)
        local preview_tooltip = FrameContainer:new{
            background = Blitbuffer.COLOR_WHITE,
            bordersize = border_sz,
            color = Blitbuffer.COLOR_DARK_GRAY,
            radius = 0,
            padding_top = pad_v,
            padding_bottom = pad_v,
            padding_left = pad_h,
            padding_right = pad_h,
            width = popup_w,
            VerticalGroup:new{
                align = "center",
                tb
            }
        }

        local card_size = (preview_tooltip.getSize and preview_tooltip:getSize()) or Geom:new{ w = popup_w, h = sc(50) }
        local card_h = card_size.h

        local arrow_w = sc(16)
        local arrow_h = sc(8)
        local _PointerArrow = self._PointerArrow or (require(plugin_path .. "xray_unitscanner")._PointerArrow)
        local preview_arrow = _PointerArrow and _PointerArrow:new{
            width = arrow_w,
            height = arrow_h,
            direction = "down",
            apex_offset = arrow_w / 2,
            border_size = border_sz,
            border_color = Blitbuffer.COLOR_DARK_GRAY,
            fill_color = Blitbuffer.COLOR_WHITE,
        }
        if preview_arrow then
            preview_arrow.overlap_offset = { math.floor((popup_w - arrow_w) / 2), card_h - border_sz }
        end

        local tooltip_with_arrow
        if preview_arrow then
            tooltip_with_arrow = OverlapGroup:new{
                dimen = Geom:new{ w = popup_w, h = card_h + arrow_h - border_sz },
                preview_tooltip,
                preview_arrow,
            }
        else
            tooltip_with_arrow = preview_tooltip
        end

        local preview_panel = FrameContainer:new{
            padding = sc(8),
            radius = xray_theme.radius_window,
            bordersize = xray_theme.border_preview,
            color = xray_theme.color_border,
            background = Blitbuffer.COLOR_WHITE,
            width = dialog_w - sc(28),
            VerticalGroup:new{
                align = "center",
                HorizontalGroup:new{
                    align = "center",
                    tooltip_with_arrow
                },
                VerticalSpan:new{ width = sc(2) },
                CenterContainer:new{
                    dimen = Geom:new{ w = dialog_w - sc(44), h = entity_size.h },
                    preview_example
                }
            }
        }

        local title_label = TextWidget:new{
            text = self.loc:t("unit_style_preview_title") or "STYLE PREVIEW",
            face = Font:getFace("cfont", ui_font_size - 1),
            bold = true,
            fgcolor = Blitbuffer.COLOR_BLACK,
        }

        local function label(str)
            return TextWidget:new{
                text = str,
                face = Font:getFace("cfont", ui_font_size - 2),
                bold = true,
                fgcolor = Blitbuffer.COLOR_BLACK,
            }
        end

        local function span()
            return VerticalSpan:new{ width = sc(6) }
        end

        local function divider()
            return LineWidget:new{
                dimen = Geom:new{ w = dialog_w - sc(28), h = xray_theme.border_line_h },
                background = xray_theme.color_section_rule,
            }
        end

        local style_row_1 = option_row(1)
        local style_row_2 = option_row(2)
        local style_row_3 = option_row(3)
        local thickness_row = option_row(4)
        local intensity_row = option_row(5)
        local timeout_row = option_row(6)

        local is_close_focused = (focused_row == 7)
        local close_btn = Button:new{
            text = self.loc:t("close") or "Close",
            face = Font:getFace("cfont", ui_font_size),
            bold = is_close_focused,
            width = dialog_w - sc(32),
            height = sc(42),
            bordersize = is_close_focused and (xray_theme.border_focus or sc(3)) or xray_theme.border_btn,
            color = is_close_focused and (xray_theme.color_focus_border or Blitbuffer.COLOR_BLACK) or xray_theme.color_border,
            background = is_close_focused and (xray_theme.color_focus_bg or Blitbuffer.Color8(215)) or nil,
            radius = xray_theme.radius_btn,
            callback = function()
                if overlay then overlay:onClose() end
            end
        }

        local card = FrameContainer:new{
            padding = sc(12),
            radius = xray_theme.radius_window,
            bordersize = sc(2),
            color = Blitbuffer.COLOR_BLACK,
            background = xray_theme.color_bg,
            width = dialog_w - sc(2),
            VerticalGroup:new{
                align = "left",
                title_label,
                span(),
                preview_panel,
                span(),
                label(self.loc:t("unit_underline_style_label") or "Underline Style"),
                style_row_1,
                WidgetContainer:new{ dimen = Geom:new{ w = 1, h = sc(4) } },
                style_row_2,
                WidgetContainer:new{ dimen = Geom:new{ w = 1, h = sc(4) } },
                style_row_3,
                span(),
                label(self.loc:t("unit_underline_thickness_label") or "Underline Thickness"),
                thickness_row,
                span(),
                label(self.loc:t("unit_underline_intensity_label") or "Underline Intensity"),
                intensity_row,
                span(),
                label(self.loc:t("unit_tooltip_timeout_label") or "Tooltip Timeout"),
                timeout_row,
                span(),
                divider(),
                span(),
                close_btn,
            }
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
        if self._entity_styling_offset then
            movable:setMovedOffset(self._entity_styling_offset)
        end

        local orig_handleEvent = movable.handleEvent
        movable.handleEvent = function(this, ev)
            local res = orig_handleEvent(this, ev)
            if ev.type == "Gesture" or ev.type == "Pan" or ev.type == "Hold" then
                self._entity_styling_offset = this.moved_offset
            end
            return res
        end

        local main_center = CenterContainer:new{
            dimen = Geom:new{ w = sw, h = sh },
            movable
        }

        if overlay then
            overlay[1] = main_center
            UIManager:setDirty(overlay, "ui")
        else
            overlay = InputContainer:new{
                key_events = {
                    FocusUp = {
                        { "Up" },
                        { "PrevPage" },
                    },
                    FocusDown = {
                        { "Down" },
                        { "NextPage" },
                    },
                    FocusLeft = {
                        { "Left" },
                    },
                    FocusRight = {
                        { "Right" },
                    },
                    Select = {
                        { "Return" },
                        { "KP_Enter" },
                        { "Enter" },
                        { "Press" },
                        { "Select" },
                        { "Space" },
                    },
                    Close = {
                        { "Escape" },
                        { "Back" },
                        { "q" },
                        { "Q" },
                    },
                },
                main_center
            }

            if Device and Device.input and Device.input.group then
                if Device.input.group.Enter then table.insert(overlay.key_events.Select, { Device.input.group.Enter }) end
                if Device.input.group.Select then table.insert(overlay.key_events.Select, { Device.input.group.Select }) end
                if Device.input.group.Back then table.insert(overlay.key_events.Close, { Device.input.group.Back }) end
            end

            overlay.onFocusUp = function()
                if focused_row > 1 then
                    focused_row = focused_row - 1
                else
                    focused_row = num_rows
                end
                local opts = row_definitions[focused_row].options
                if focused_col > #opts then focused_col = #opts end
                refresh()
                return true
            end

            overlay.onFocusDown = function()
                if focused_row < num_rows then
                    focused_row = focused_row + 1
                else
                    focused_row = 1
                end
                local opts = row_definitions[focused_row].options
                if focused_col > #opts then focused_col = #opts end
                refresh()
                return true
            end

            overlay.onFocusLeft = function()
                local opts = row_definitions[focused_row].options
                if focused_col > 1 then
                    focused_col = focused_col - 1
                else
                    focused_col = #opts
                end
                refresh()
                return true
            end

            overlay.onFocusRight = function()
                local opts = row_definitions[focused_row].options
                if focused_col < #opts then
                    focused_col = focused_col + 1
                else
                    focused_col = 1
                end
                refresh()
                return true
            end

            overlay.onSelect = function()
                if focused_row <= 6 then
                    local rdef = row_definitions[focused_row]
                    local opt = rdef.options[focused_col]
                    if opt then
                        saveSetting(rdef.key, opt.value)
                    end
                else
                    overlay:onClose()
                end
                return true
            end

            function overlay:onClose()
                self._entity_styling_offset = nil
                UIManager:close(overlay, "ui")
                return true
            end

            overlay.handleEvent = function(this, ev)
                if ev.type == "Key" or ev.type == "KeyPress" or ev.type == "KeyDown" then
                    local key = ev.key or ev.name or ev.sym
                    if key == "Return" or key == "KP_Enter" or key == "Enter" or key == "Select" or key == "Space" or key == "Press" then
                        return this:onSelect()
                    elseif key == "Up" or key == "PrevPage" or key == "PageUp" then
                        return this:onFocusUp()
                    elseif key == "Down" or key == "NextPage" or key == "PageDown" then
                        return this:onFocusDown()
                    elseif key == "Left" then
                        return this:onFocusLeft()
                    elseif key == "Right" then
                        return this:onFocusRight()
                    elseif key == "Escape" or key == "Back" or key == "q" or key == "Q" then
                        return this:onClose()
                    end
                end
                return InputContainer.handleEvent(this, ev)
            end

            UIManager:show(overlay, "ui")
        end
    end

    refresh()
end

function M:showEntityFootnotesNewFeatureCard()
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
    local VerticalSpan = require("ui/widget/verticalspan")
    local WidgetContainer = require("ui/widget/container/widgetcontainer")
    local MovableContainer = require("ui/widget/container/movablecontainer")
    local TextBoxWidget = require("ui/widget/textboxwidget")
    local LineWidget = require("ui/widget/linewidget")
    local xray_theme = require(plugin_path .. "xray_theme")

    local function sc(val) return Screen:scaleBySize(val) end
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    local dialog_w = math.min(sw - sc(20), sc(440))

    local fs = 20
    if G_reader_settings then
        fs = G_reader_settings:readSetting("cre_font_size") or 20
    end
    local ui_font_size = math.max(13, math.min(fs, 20))
    local title_font_size = math.max(10, math.min(fs - 5, 13))

    local overlay
    local focused_btn = nil -- nil initially so both buttons have crisp borders without pre-selection grey

    local function renderCard()
        local content_vg = VerticalGroup:new{ align = "left", width = dialog_w - sc(24) }

        table.insert(content_vg, TextWidget:new{
            text = (self.loc:t("new_feature") or "New Feature"):upper(),
            face = Font:getFace("infofont", title_font_size),
            fgcolor = xray_theme.color_label_dim,
        })
        table.insert(content_vg, VerticalSpan:new{ width = sc(2) })

        table.insert(content_vg, TextWidget:new{
            text = self.loc:t("entity_new_feature_title") or "Entity Underlining",
            face = Font:getFace("cfont", ui_font_size + 2),
            bold = true,
            fgcolor = Blitbuffer.COLOR_BLACK,
        })
        table.insert(content_vg, VerticalSpan:new{ width = sc(6) })

        table.insert(content_vg, TextBoxWidget:new{
            text = self.loc:t("entity_new_feature_desc") or "X-Ray can underline characters, historical figures, locations, and terms in your books. Tap any underlined name for an instant description popup without leaving your page.\n\nCustomizable in settings: underline style, popup type (tooltip bubble or bottom panel), mentions frequency, and entity categories.",
            face = Font:getFace("cfont", ui_font_size - 2),
            width = dialog_w - sc(24),
        })
        table.insert(content_vg, VerticalSpan:new{ width = sc(6) })

        -- Construct live preview widget elements
        local Widget = require("ui/widget/widget")
        local OverlapGroup = require("ui/widget/overlapgroup")
        local RenderText = require("ui/rendertext")

        local settings = self.ai_helper and self.ai_helper.settings or {}
        local underline_style = settings.entity_underline_style or "solid"
        local underline_thickness = tonumber(settings.entity_underline_thickness) or 2
        local underline_intensity = settings.entity_underline_intensity or "light"

        local UnderlinePreview = Widget:extend{
            width = 0,
            height = 0,
            underline_style = underline_style,
            underline_thickness = underline_thickness,
            underline_intensity = underline_intensity,
            plugin = nil,
        }
        function UnderlinePreview:getSize()
            return Geom:new{ w = self.width, h = self.height }
        end
        function UnderlinePreview:paintTo(bb, x, y)
            local plugin = self.plugin
            if plugin and plugin._draw_underline then
                local grey = 150
                if self.underline_intensity == "light" then
                    grey = 200
                elseif self.underline_intensity == "dark" then
                    grey = 30
                end
                local thickness = Screen:scaleBySize(self.underline_thickness)
                local box = { x = x, y = y, w = self.width, h = self.height }
                plugin._draw_underline(bb, box, self.underline_style, grey, thickness, self.underline_thickness, plugin.path)
            end
        end

        local preview_face = Font:getFace("cfont", ui_font_size - 1)
        local before_text = TextWidget:new{
            text = "with ",
            face = preview_face,
        }
        local entity_text = TextWidget:new{
            text = "Sherlock Holmes",
            face = preview_face,
        }
        local after_text = TextWidget:new{
            text = " here",
            face = preview_face,
        }

        local entity_size = (entity_text.getSize and entity_text:getSize()) or Geom:new{ w = sc(120), h = sc(20) }

        local underline_widget = UnderlinePreview:new{
            width = entity_size.w,
            height = entity_size.h,
            underline_style = underline_style,
            underline_thickness = underline_thickness,
            underline_intensity = underline_intensity,
            plugin = self,
        }

        local entity_with_underline = OverlapGroup:new{
            dimen = entity_size,
            entity_text,
            underline_widget,
        }

        local sample_line = HorizontalGroup:new{
            align = "center",
            before_text,
            entity_with_underline,
            after_text,
        }

        local popup_w = math.min(dialog_w - sc(40), sc(260))
        local preview_tooltip = FrameContainer:new{
            background = Blitbuffer.COLOR_WHITE,
            bordersize = sc(1),
            color = Blitbuffer.COLOR_DARK_GRAY,
            radius = sc(3),
            padding_top = sc(5),
            padding_bottom = sc(5),
            padding_left = sc(10),
            padding_right = sc(10),
            width = popup_w,
            VerticalGroup:new{
                align = "left",
                TextWidget:new{
                    text = "Sherlock Holmes",
                    face = Font:getFace("cfont", ui_font_size - 2),
                    bold = true,
                },
                TextWidget:new{
                    text = "CHARACTER",
                    face = Font:getFace("infofont", math.max(9, ui_font_size - 6)),
                    fgcolor = Blitbuffer.Color8(120),
                },
                VerticalSpan:new{ width = sc(2) },
                TextBoxWidget:new{
                    text = "Consulting detective in London",
                    face = Font:getFace("cfont", ui_font_size - 4),
                    width = popup_w - sc(20),
                },
            }
        }

        local card_size = (preview_tooltip.getSize and preview_tooltip:getSize()) or Geom:new{ w = popup_w, h = sc(45) }
        local card_h = card_size.h

        local arrow_w = sc(12)
        local arrow_h = sc(6)
        local border_sz = sc(1)
        local _PointerArrow = self._PointerArrow or (require(plugin_path .. "xray_unitscanner")._PointerArrow)
        local preview_arrow = _PointerArrow and _PointerArrow:new{
            width = arrow_w,
            height = arrow_h,
            direction = "down",
            apex_offset = arrow_w / 2,
            border_size = border_sz,
            border_color = Blitbuffer.COLOR_DARK_GRAY,
            fill_color = Blitbuffer.COLOR_WHITE,
        }
        if preview_arrow then
            preview_arrow.overlap_offset = { math.floor((popup_w - arrow_w) / 2), card_h - border_sz }
        end

        local tooltip_with_arrow
        if preview_arrow then
            tooltip_with_arrow = OverlapGroup:new{
                dimen = Geom:new{ w = popup_w, h = card_h + arrow_h - border_sz },
                preview_tooltip,
                preview_arrow,
            }
        else
            tooltip_with_arrow = preview_tooltip
        end

        local preview_panel = FrameContainer:new{
            padding = sc(6),
            radius = xray_theme.radius_window,
            bordersize = xray_theme.border_preview,
            color = xray_theme.color_border,
            background = Blitbuffer.COLOR_WHITE,
            width = dialog_w - sc(24),
            VerticalGroup:new{
                align = "center",
                HorizontalGroup:new{
                    align = "center",
                    tooltip_with_arrow
                },
                VerticalSpan:new{ width = sc(2) },
                CenterContainer:new{
                    dimen = Geom:new{ w = dialog_w - sc(36), h = entity_size.h },
                    sample_line
                }
            }
        }

        table.insert(content_vg, preview_panel)
        table.insert(content_vg, VerticalSpan:new{ width = sc(8) })

        table.insert(content_vg, LineWidget:new{
            dimen = Geom:new{ w = dialog_w - sc(24), h = sc(1) },
            background = xray_theme.color_section_rule or Blitbuffer.Color8(200),
        })
        table.insert(content_vg, VerticalSpan:new{ width = sc(8) })

        local btn_w = math.floor((dialog_w - sc(24) - sc(10)) / 2)

        local is_enable_focused = (focused_btn == 1)
        local enable_btn = Button:new{
            text = self.loc:t("entity_new_feature_enable") or "Enable Underlining",
            face = Font:getFace("cfont", ui_font_size),
            bold = is_enable_focused,
            width = btn_w,
            height = sc(38),
            bordersize = is_enable_focused and (xray_theme.border_focus or sc(3)) or sc(1),
            radius = xray_theme.radius_btn or sc(4),
            callback = function()
                self.ai_helper:saveSettings({
                    entity_footnotes_enabled = true,
                    entity_new_feature_prompt_seen = true,
                })
                if overlay then
                    UIManager:close(overlay, "ui")
                    overlay = nil
                end
                if self.scanBookForEntities then self:scanBookForEntities(true) end
                self:openReaderMenuToPath("entity_footnotes")
            end
        }

        local is_disable_focused = (focused_btn == 2)
        local disable_btn = Button:new{
            text = self.loc:t("entity_new_feature_keep_disabled") or "Keep Disabled",
            face = Font:getFace("cfont", ui_font_size),
            bold = is_disable_focused,
            width = btn_w,
            height = sc(38),
            bordersize = is_disable_focused and (xray_theme.border_focus or sc(3)) or sc(1),
            radius = xray_theme.radius_btn or sc(4),
            callback = function()
                self.ai_helper:saveSettings({
                    entity_footnotes_enabled = false,
                    entity_new_feature_prompt_seen = true,
                })
                if overlay then
                    UIManager:close(overlay, "ui")
                    overlay = nil
                end
            end
        }

        local btn_row = HorizontalGroup:new{
            align = "center",
            disable_btn,
            WidgetContainer:new{ dimen = Geom:new{ w = sc(10), h = 1 } },
            enable_btn,
        }
        table.insert(content_vg, btn_row)

        local card = FrameContainer:new{
            padding = sc(10),
            radius = xray_theme.radius_window,
            bordersize = sc(2),
            color = Blitbuffer.COLOR_BLACK,
            background = xray_theme.color_bg,
            width = dialog_w,
            content_vg
        }

        local movable = MovableContainer:new{
            card,
            overlap_offset = { 0, 0 }
        }

        local main_center = CenterContainer:new{
            dimen = Geom:new{ w = sw, h = sh },
            movable
        }

        if overlay then
            overlay[1] = main_center
            UIManager:setDirty(overlay, "ui")
        else
            overlay = InputContainer:new{
                main_center,
                key_events = {
                    FocusLeft = { { "Left" } },
                    FocusRight = { { "Right" } },
                    Select = { { "Return" }, { "KP_Enter" }, { "Enter" }, { "Select" }, { "Space" } },
                    Close = { { "Escape" }, { "Back" }, { "q" }, { "Q" } },
                }
            }

            overlay.onFocusLeft = function()
                focused_btn = 1
                renderCard()
                return true
            end

            overlay.onFocusRight = function()
                focused_btn = 2
                renderCard()
                return true
            end

            overlay.onSelect = function()
                if focused_btn == 1 then
                    enable_btn.callback()
                else
                    disable_btn.callback()
                end
                return true
            end

            overlay.onClose = function()
                disable_btn.callback()
                return true
            end

            UIManager:show(overlay, "ui")
        end
    end

    renderCard()
end


return M
