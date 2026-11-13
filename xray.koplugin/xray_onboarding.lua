--[[
    xray_onboarding.lua
    Welcome onboarding card, API key manager dialogs, setup guide, and provider model pickers for KOReader X-Ray Plugin.
--]]

local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local ButtonDialog = require("ui/widget/buttondialog")
local Menu = require("ui/widget/menu")

local plugin_path = ((...) or ""):match("(.-)[^%.]+$") or ""
local utils = require(plugin_path .. "xray_utils")
local xray_theme = require(plugin_path .. "xray_theme")

local M = {}

function M:showWelcomeCard(force)
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
    local TextBoxWidget = require("ui/widget/textboxwidget")
    local Button = require("ui/widget/button")
    local GestureRange = require("ui/gesturerange")
    local VerticalSpan = require("ui/widget/verticalspan")
    local WidgetContainer = require("ui/widget/container/widgetcontainer")
    local LineWidget = require("ui/widget/linewidget")
    local MovableContainer = require("ui/widget/container/movablecontainer")
    local Device = require("device")
    local Screen = Device.screen
    local xray_theme = require(plugin_path .. "xray_theme")

    local function sc(val)
        return Screen:scaleBySize(val)
    end

    local sw = Screen:getWidth()
    local sh = Screen:getHeight()
    local dialog_w = math.min(sw - sc(16), sc(490))

    local fs = 20
    if G_reader_settings then
        fs = G_reader_settings:readSetting("cre_font_size") or 20
    end
    local ui_font_size = math.max(15, math.min(fs, 19))
    local desc_font_size = math.max(12, ui_font_size - 2)

    local overlay
    local selected_action = "phone_pc"
    local is_touch = false
    local ok_dev, Dev = pcall(require, "device")
    if ok_dev and Dev then
        if type(Dev.isTouchDevice) == "function" then
            local ok2, res = pcall(Dev.isTouchDevice, Dev)
            if ok2 and res ~= nil then is_touch = (res == true) end
        elseif Dev.isTouchDevice ~= nil then
            is_touch = (Dev.isTouchDevice == true)
        end
    end
    local focus_visible = not is_touch
    local focused_index = focus_visible and 1 or nil
    local total_items = 7

    local function span(h)
        return VerticalSpan:new{ width = h or sc(4) }
    end

    local choices = {
        {
            value = "phone_pc",
            title = self.loc:t("welcome_opt_phone_title") or "Set from Phone/PC (Recommended)",
            desc = self.loc:t("welcome_opt_phone_desc") or "Scan a QR code to enter your key online via Cloud Relay or local Wi-Fi.",
        },
        {
            value = "ereader",
            title = self.loc:t("welcome_opt_ereader_title") or "Enter Key on E-Reader",
            desc = self.loc:t("welcome_opt_ereader_desc") or "Type or paste your API key directly using the on-screen keyboard.",
        },
        {
            value = "file_config",
            title = self.loc:t("welcome_opt_file_title") or "Import via Text File (xray_key.txt) or Config",
            desc = self.loc:t("welcome_opt_file_desc") or "Place key in koreader/settings/xray_key.txt or select existing configured provider.",
        },
        {
            value = "skip",
            title = self.loc:t("welcome_opt_skip_title") or "Skip for Now (Offline Features Only)",
            desc = self.loc:t("welcome_opt_skip_desc") or "Use local word counts, reading metrics, and cached series info without AI.",
        },
    }

    local buildWelcomeCard
    local refreshUI

    buildWelcomeCard = function()
        local headline_label = TextWidget:new{
            text = self.loc:t("welcome_headline") or "Set Up AI Provider",
            face = Font:getFace("cfont", ui_font_size + 3),
            bold = true,
            fgcolor = Blitbuffer.COLOR_BLACK,
        }

        local description_box = TextBoxWidget:new{
            text = self.loc:t("welcome_desc") or "To get started, choose how you would like to connect your API key:",
            face = Font:getFace("cfont", ui_font_size),
            width = dialog_w - sc(24),
            alignment = self:isRTL() and "right" or "left",
        }

        local content_vg = VerticalGroup:new{
            align = self:isRTL() and "right" or "left",
            span(sc(2)),
            headline_label,
            span(sc(4)),
            description_box,
            span(sc(6)),
        }

        for idx, choice in ipairs(choices) do
            local is_selected = (choice.value == selected_action)
            local is_focused = focus_visible and (idx == focused_index)
            local dot_char = is_selected and "●" or "○"

            local text_widget = TextBoxWidget:new{
                text = choice.title,
                bold = is_selected,
                face = Font:getFace("cfont", ui_font_size),
                fgcolor = Blitbuffer.COLOR_BLACK,
                width = dialog_w - sc(60),
                alignment = self:isRTL() and "right" or "left",
            }
            local subtext_widget = TextBoxWidget:new{
                text = choice.desc,
                face = Font:getFace("cfont", desc_font_size),
                fgcolor = Blitbuffer.Color8(75),
                width = dialog_w - sc(60),
                alignment = self:isRTL() and "right" or "left",
            }
            local choice_text_vg = VerticalGroup:new{
                align = self:isRTL() and "right" or "left",
                text_widget,
                span(sc(2)),
                subtext_widget,
            }

            local row_elements = HorizontalGroup:new{
                align = "top",
            }
            if self:isRTL() then
                table.insert(row_elements, choice_text_vg)
                table.insert(row_elements, WidgetContainer:new{ dimen = Geom:new{ w = sc(8), h = 1 } })
                table.insert(row_elements, TextWidget:new{
                    text = dot_char,
                    face = Font:getFace("cfont", ui_font_size),
                    bold = true,
                    fgcolor = Blitbuffer.COLOR_BLACK,
                })
            else
                table.insert(row_elements, TextWidget:new{
                    text = dot_char,
                    face = Font:getFace("cfont", ui_font_size),
                    bold = true,
                    fgcolor = Blitbuffer.COLOR_BLACK,
                })
                table.insert(row_elements, WidgetContainer:new{ dimen = Geom:new{ w = sc(8), h = 1 } })
                table.insert(row_elements, choice_text_vg)
            end

            local frame = FrameContainer:new{
                padding = sc(8),
                padding_h = sc(12),
                bordersize = is_focused and (xray_theme.border_focus or sc(2)) or 0,
                color = is_focused and (xray_theme.color_focus_border or Blitbuffer.COLOR_BLACK) or nil,
                background = is_focused and (xray_theme.color_focus_bg or Blitbuffer.Color8(230)) or nil,
                radius = xray_theme.radius_card or sc(4),
                width = dialog_w - sc(24),
                row_elements,
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
                                w = dialog_w - sc(24),
                                h = frame.dimen.h
                            }
                        end
                    }
                }
            }
            item.onTap = function()
                selected_action = choice.value
                if is_touch then
                    focus_visible = false
                    focused_index = nil
                else
                    focused_index = idx
                end
                refreshUI()
                return true
            end

            table.insert(content_vg, item)
            table.insert(content_vg, WidgetContainer:new{ dimen = Geom:new{ w = 1, h = sc(3) } })
        end

        table.insert(content_vg, span(sc(4)))
        table.insert(content_vg, LineWidget:new{
            dimen = Geom:new{ w = dialog_w - sc(24), h = sc(1) },
            background = xray_theme.color_section_rule or Blitbuffer.Color8(200),
        })
        table.insert(content_vg, span(sc(5)))

        -- Action Buttons
        local is_continue_focused = focus_visible and (focused_index == 5)
        local is_ask_later_focused = focus_visible and (focused_index == 6)
        local is_dont_ask_focused = focus_visible and (focused_index == 7)

        local continue_btn = Button:new{
            text = self.loc:t("welcome_action_continue") or "Continue",
            face = Font:getFace("cfont", ui_font_size),
            width = dialog_w - sc(24),
            height = sc(44),
            bordersize = is_continue_focused and (xray_theme.border_focus or sc(2)) or xray_theme.border_btn or sc(1),
            background = is_continue_focused and (xray_theme.color_focus_bg or Blitbuffer.Color8(230)) or nil,
            radius = xray_theme.radius_btn or sc(4),
            callback = function()
                if overlay then
                    UIManager:close(overlay, "ui")
                    overlay = nil
                end
                self:handleWelcomeAction(selected_action)
            end
        }
        table.insert(content_vg, continue_btn)
        table.insert(content_vg, span(sc(5)))

        local sec_btn_w = (dialog_w - sc(32)) / 2
        local ask_later_btn = Button:new{
            text = self.loc:t("welcome_action_ask_later") or "Ask Me Later",
            face = Font:getFace("cfont", desc_font_size),
            width = sec_btn_w,
            height = sc(38),
            bordersize = is_ask_later_focused and (xray_theme.border_focus or sc(2)) or xray_theme.border_btn or sc(1),
            background = is_ask_later_focused and (xray_theme.color_focus_bg or Blitbuffer.Color8(230)) or nil,
            radius = xray_theme.radius_btn or sc(4),
            callback = function()
                if overlay then
                    UIManager:close(overlay, "ui")
                    overlay = nil
                end
            end
        }

        local dont_ask_btn = Button:new{
            text = self.loc:t("welcome_action_dont_ask") or "Don't Ask Again",
            face = Font:getFace("cfont", desc_font_size),
            width = sec_btn_w,
            height = sc(38),
            bordersize = is_dont_ask_focused and (xray_theme.border_focus or sc(2)) or xray_theme.border_btn or sc(1),
            background = is_dont_ask_focused and (xray_theme.color_focus_bg or Blitbuffer.Color8(230)) or nil,
            radius = xray_theme.radius_btn or sc(4),
            callback = function()
                if overlay then
                    UIManager:close(overlay, "ui")
                    overlay = nil
                end
                if self.ai_helper and self.ai_helper.saveSettings then
                    self.ai_helper:saveSettings({ welcome_wizard_dont_ask = true, welcome_wizard_dismissed = true })
                end
            end
        }

        local sec_buttons_row = HorizontalGroup:new{
            align = "center",
            ask_later_btn,
            WidgetContainer:new{ dimen = Geom:new{ w = sc(8), h = 1 } },
            dont_ask_btn,
        }
        table.insert(content_vg, sec_buttons_row)
        table.insert(content_vg, span(sc(4)))

        local card_frame = FrameContainer:new{
            padding = sc(12),
            bordersize = xray_theme.border_dialog or sc(1),
            color = Blitbuffer.COLOR_BLACK,
            background = Blitbuffer.COLOR_WHITE,
            radius = xray_theme.radius_dialog or sc(8),
            width = dialog_w,
            content_vg,
        }
        return card_frame
    end

    refreshUI = function()
        if not overlay then return end
        overlay[1] = MovableContainer:new{
            CenterContainer:new{
                dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh },
                buildWelcomeCard()
            }
        }
        UIManager:setDirty(overlay, "ui")
    end

    overlay = InputContainer:new{
        dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh },
        key_events = {
            FocusUp = { { "Up" }, { "PrevPage" } },
            FocusDown = { { "Down" }, { "NextPage" } },
            FocusLeft = { { "Left" } },
            FocusRight = { { "Right" } },
            Select = { { "Return" }, { "KP_Enter" }, { "Select" }, { "Space" } },
            Close = { { "Escape" }, { "Back" }, { "q" }, { "Q" } },
        },
        MovableContainer:new{
            CenterContainer:new{
                dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh },
                buildWelcomeCard()
            }
        }
    }

    overlay.onFocusUp = function()
        focus_visible = true
        if not focused_index then
            focused_index = total_items
        elseif focused_index > 1 then
            focused_index = focused_index - 1
        else
            focused_index = total_items
        end
        refreshUI()
        return true
    end

    overlay.onFocusDown = function()
        if focused_index < total_items then
            focused_index = focused_index + 1
        else
            focused_index = 1
        end
        refreshUI()
        return true
    end

    overlay.onFocusLeft = function()
        if focused_index == 7 then
            focused_index = 6
            refreshUI()
        elseif focused_index > 1 and focused_index <= 4 then
            focused_index = focused_index - 1
            refreshUI()
        end
        return true
    end

    overlay.onFocusRight = function()
        if focused_index == 6 then
            focused_index = 7
            refreshUI()
        elseif focused_index < 4 then
            focused_index = focused_index + 1
            refreshUI()
        end
        return true
    end

    overlay.onSelect = function()
        if focused_index >= 1 and focused_index <= 4 then
            selected_action = choices[focused_index].value
            refreshUI()
        elseif focused_index == 5 then
            if overlay then
                UIManager:close(overlay, "ui")
                overlay = nil
            end
            self:handleWelcomeAction(selected_action)
        elseif focused_index == 6 then
            if overlay then
                UIManager:close(overlay, "ui")
                overlay = nil
            end
        elseif focused_index == 7 then
            if overlay then
                UIManager:close(overlay, "ui")
                overlay = nil
            end
            self.ai_helper:saveSettings({ welcome_wizard_dont_ask = true, welcome_wizard_dismissed = true })
        end
        return true
    end

    overlay.onClose = function()
        if overlay then
            UIManager:close(overlay, "ui")
            overlay = nil
        end
        return true
    end

    UIManager:show(overlay, "ui")
end

function M:refreshAPIKeysMenu()
    UIManager:setDirty(nil, "ui")
end

function M:handleWelcomeAction(action)
    local Device = require("device")
    local Screen = Device.screen
    local InfoMessage = require("ui/widget/infomessage")
    if action == "phone_pc" then
        local WebSetup = require(plugin_path .. "xray_websetup")
        WebSetup:startCloudRelay(self.ai_helper, self.loc, function()
            self.ai_helper:init(self.path)
            self:refreshAPIKeysMenu()
        end)

    elseif action == "ereader" then
        self:showEnterKeyProviderDialog()

    elseif action == "file_config" then
        self:showConfigFileGuide()

    elseif action == "skip" then
        if self.ai_helper and self.ai_helper.saveSettings then
            self.ai_helper:saveSettings({ welcome_wizard_dismissed = true })
        end

    elseif action == "all_providers" then
        if self.openReaderMenuToPath then
            self:openReaderMenuToPath("api_keys")
        else
            self:showFullXRayMenu()
        end
    end
end

function M:showEnterKeyProviderDialog()
    local ButtonDialog = require("ui/widget/buttondialog")
    local dlg
    local providers = {
        { id = "gemini", name = "Google Gemini (Free / Recommended)" },
        { id = "chatgpt", name = "OpenAI ChatGPT" },
        { id = "deepseek", name = "DeepSeek" },
        { id = "claude", name = "Anthropic Claude" },
        { id = "custom1", name = "Custom / OpenRouter" },
    }
    local buttons = {}
    for _, p in ipairs(providers) do
        table.insert(buttons, {
            {
                text = p.name,
                callback = function()
                    UIManager:close(dlg)
                    self:promptProviderKeyEntry(p.id, p.name)
                end,
            }
        })
    end
    table.insert(buttons, {
        {
            text = self.loc:t("cancel") or "Cancel",
            id = "close",
            callback = function()
                UIManager:close(dlg)
            end,
        }
    })

    dlg = ButtonDialog:new{
        modal = true,
        title = self.loc:t("welcome_select_provider") or "Select AI Provider",
        buttons = buttons,
    }
    UIManager:show(dlg)
end

function M:promptProviderKeyEntry(provider, provider_name)
    local Device = require("device")
    local InputDialog = require("ui/widget/inputdialog")
    local InfoMessage = require("ui/widget/infomessage")

    if provider:find("custom") then
        local ui_key = (self.ai_helper and self.ai_helper.settings) and self.ai_helper.settings[provider .. "_api_key"] or ""
        local function promptModel(endpoint, key)
            local current_model = (self.ai_helper and self.ai_helper.settings) and self.ai_helper.settings[provider .. "_model"] or ""
            local model_dialog
            model_dialog = InputDialog:new{
                title = self.loc:t("custom_api_model_title", provider:sub(-1)),
                input = current_model,
                input_hint = self.loc:t("custom_api_model_hint") or "e.g., google/gemini-2.5-flash or openai/gpt-4o",
                buttons = {
                    {
                        { text = self.loc:t("cancel"), callback = function() UIManager:close(model_dialog) end },
                        { text = self.loc:t("save"), is_enter_default = true, callback = function()
                            local model = model_dialog:getInputText()
                            UIManager:close(model_dialog)
                            self.ai_helper:setCustomAPIConfig(provider, key, endpoint, model)
                            self.ai_helper:init(self.path)
                            UIManager:show(InfoMessage:new{ text = self.loc:t("custom_api_saved", provider:sub(-1)), timeout = 3 })
                            UIManager:setDirty(nil, "ui")
                        end }
                    }
                }
            }
            UIManager:show(model_dialog)
            model_dialog:onShowKeyboard()
        end

        local function promptKey(endpoint)
            local key_dialog
            local key_buttons = {
                { text = self.loc:t("cancel"), callback = function() UIManager:close(key_dialog) end }
            }
            if Device.hasClipboard and Device:hasClipboard() then
                table.insert(key_buttons, {
                    text = self.loc:t("btn_paste") or "Paste",
                    callback = function()
                        local ok, clip = pcall(function() return Device:getClipboardText() end)
                        if ok and clip and #clip > 0 then
                            key_dialog:setInputText(clip:match("^%s*(.-)%s*$"))
                        end
                    end
                })
            end
            table.insert(key_buttons, {
                text = self.loc:t("next") or "Next",
                is_enter_default = true,
                callback = function()
                    local key = key_dialog:getInputText()
                    UIManager:close(key_dialog)
                    promptModel(endpoint, key)
                end
            })

            key_dialog = InputDialog:new{
                title = self.loc:t("custom_api_key_title", provider:sub(-1)),
                input = ui_key,
                buttons = { key_buttons }
            }
            UIManager:show(key_dialog)
            key_dialog:onShowKeyboard()
        end

        local current_endpoint = (self.ai_helper and self.ai_helper.settings) and self.ai_helper.settings[provider .. "_endpoint"] or "https://openrouter.ai/api/v1/chat/completions"
        local endpoint_dialog
        endpoint_dialog = InputDialog:new{
            title = self.loc:t("custom_api_endpoint_title", provider:sub(-1)),
            input = current_endpoint,
            input_hint = self.loc:t("custom_api_endpoint_hint") or "e.g., https://openrouter.ai/api/v1/chat/completions",
            buttons = {
                {
                    { text = self.loc:t("cancel"), callback = function() UIManager:close(endpoint_dialog) end },
                    { text = self.loc:t("next") or "Next", is_enter_default = true, callback = function()
                        local endpoint = endpoint_dialog:getInputText()
                        UIManager:close(endpoint_dialog)
                        promptKey(endpoint)
                    end }
                }
            }
        }
        UIManager:show(endpoint_dialog)
        endpoint_dialog:onShowKeyboard()
        return
    end

    local ui_key = (self.ai_helper and self.ai_helper.settings) and self.ai_helper.settings[provider .. "_api_key"] or ""
    local title = provider_name .. " API Key"
    local description = nil
    if provider == "gemini" then
        description = self.loc:t("gemini_key_hint") or "Enter your free Gemini key from Google AI Studio (starts with AQ. or AIzaSy...):"
    elseif provider == "chatgpt" then
        description = "Enter your OpenAI API key (starts with sk-...):"
    elseif provider == "deepseek" then
        description = "Enter your DeepSeek API key (starts with sk-...):"
    elseif provider == "claude" then
        description = "Enter your Anthropic Claude API key (starts with sk-ant-...):"
    end

    local input_dialog
    local dlg_buttons = {
        { text = self.loc:t("cancel"), callback = function() UIManager:close(input_dialog) end }
    }
    if Device.hasClipboard and Device:hasClipboard() then
        table.insert(dlg_buttons, {
            text = self.loc:t("btn_paste") or "Paste",
            callback = function()
                local ok, clip = pcall(function() return Device:getClipboardText() end)
                if ok and clip and #clip > 0 then
                    input_dialog:setInputText(clip:match("^%s*(.-)%s*$"))
                end
            end
        })
    end
    table.insert(dlg_buttons, {
        text = self.loc:t("save"),
        is_enter_default = true,
        callback = function()
            local key = input_dialog:getInputText()
            UIManager:close(input_dialog)
            if key and #key > 0 then
                local trimmed_key = key:match("^%s*(.-)%s*$")
                self.ai_helper:saveSettings({ 
                    [provider .. "_api_key"] = trimmed_key,
                    [provider .. "_use_ui_key"] = true
                })
                self.ai_helper:updateConfigKey(provider .. "_api_key", trimmed_key)
                self.ai_helper:init(self.path)
                UIManager:show(InfoMessage:new{ text = self.loc:t("key_saved") or "API key saved!", timeout = 3 })
                UIManager:setDirty(nil, "ui")
            end
        end
    })

    input_dialog = InputDialog:new{
        title = title,
        description = description,
        input = ui_key,
        buttons = { dlg_buttons }
    }
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

function M:showConfigFileGuide()
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
    local InfoMessage = require("ui/widget/infomessage")
    local xray_theme = require(plugin_path .. "xray_theme")

    local function sc(val) return Screen:scaleBySize(val) end
    local sw = Screen:getWidth()
    local sh = Screen:getHeight()
    local dialog_w = math.min(sw - sc(20), sc(460))

    local fs = 20
    if G_reader_settings then
        fs = G_reader_settings:readSetting("cre_font_size") or 20
    end
    local ui_font_size = math.max(14, math.min(fs, 20))
    local title_font_size = math.max(10, math.min(fs - 5, 14))

    local overlay
    local focused_btn = 1 -- 1: Import Now, 2: Close

    local function span()
        return VerticalSpan:new{ width = xray_theme.gap }
    end

    local function buildGuideCard()
        local title_label = TextWidget:new{
            text = (self.loc:t("welcome_tag") or "WELCOME TO X-RAY"):upper(),
            face = Font:getFace("cfont", title_font_size),
            bold = true,
            fgcolor = Blitbuffer.COLOR_BLACK,
        }

        local headline_label = TextWidget:new{
            text = self.loc:t("welcome_file_guide_title") or "Config & Text File Setup",
            face = Font:getFace("cfont", ui_font_size + 2),
            bold = true,
            fgcolor = Blitbuffer.COLOR_BLACK,
        }

        local instructions_text = self.loc:t("welcome_file_guide_desc") or "How to configure API keys via text file:\n\n1. Create a file named 'xray_key.txt' on your device or computer.\n2. Place it in your KOReader folder (e.g. koreader/ or koreader/settings/).\n3. Add your key inside on a single line:\n   • Gemini: gemini = YOUR_KEY (or simply paste raw key)\n   • OpenAI: openai = sk-...\n   • DeepSeek / Claude: deepseek = ..., claude = ...\n4. Tap 'Import Now' below to load your keys.\n\nManual Config: You can also edit koreader/plugins/xray.koplugin/xray_config.lua."

        local description_box = TextBoxWidget:new{
            text = instructions_text,
            face = Font:getFace("cfont", ui_font_size),
            width = dialog_w - sc(32),
            alignment = self:isRTL() and "right" or "left",
        }

        local content_vg = VerticalGroup:new{
            align = "left",
            title_label,
            span(),
            headline_label,
            span(),
            description_box,
            span(),
        }

        local wiki_url = "https://github.com/ultimatejimmy/xray.koplugin/wiki/2.-API-Key-Setup-Options"
        local qr_size = math.max(100, math.min(math.floor((dialog_w - sc(32)) * 0.35), 140))
        local ok_qr, QRWidget = pcall(require, "ui/widget/qrwidget")
        if ok_qr and QRWidget then
            local qr_widget = QRWidget:new{
                text = wiki_url,
                width = qr_size,
                height = qr_size,
            }
            local qr_frame = FrameContainer:new{
                background = Blitbuffer.COLOR_WHITE,
                padding = sc(4),
                bordersize = 1,
                margin = 0,
                qr_widget,
            }
            table.insert(content_vg, CenterContainer:new{
                dimen = Geom:new{ w = dialog_w - sc(32), h = qr_size + sc(12) },
                qr_frame,
            })
            table.insert(content_vg, WidgetContainer:new{ dimen = Geom:new{ w = 1, h = sc(4) } })
            table.insert(content_vg, TextBoxWidget:new{
                text = self.loc:t("welcome_file_guide_scan") or "Scan QR to view API Key Setup wiki guide",
                face = Font:getFace("cfont", math.max(11, ui_font_size - 3)),
                fgcolor = Blitbuffer.COLOR_BLACK,
                width = dialog_w - sc(32),
                alignment = "center",
            })
            table.insert(content_vg, span())
        end

        table.insert(content_vg, LineWidget:new{
            dimen = Geom:new{ w = dialog_w - sc(32), h = sc(1) },
            background = xray_theme.color_section_rule,
        })
        table.insert(content_vg, span())

        local is_import_focused = (focused_btn == 1)
        local is_close_focused = (focused_btn == 2)

        local import_btn = Button:new{
            text = self.loc:t("welcome_btn_import_now") or "Import Now",
            face = Font:getFace("cfont", ui_font_size),
            bold = true,
            width = (dialog_w - sc(40)) / 2,
            height = sc(42),
            bordersize = is_import_focused and (xray_theme.border_focus or sc(2)) or xray_theme.border_btn,
            background = is_import_focused and (xray_theme.color_focus_bg or Blitbuffer.Color8(230)) or nil,
            radius = xray_theme.radius_btn,
            callback = function()
                local ok, count, path = self.ai_helper:importFromTextFile(true)
                if ok and count > 0 then
                    self.ai_helper:init(self.path)
                    if overlay then
                        UIManager:close(overlay, "ui")
                        overlay = nil
                    end
                    UIManager:show(InfoMessage:new{
                        text = string.format("Imported %d API key(s) from %s", count, tostring(path)),
                        timeout = 4
                    })
                    UIManager:setDirty(nil, "ui")
                else
                    UIManager:show(InfoMessage:new{
                        text = self.loc:t("welcome_no_file_found") or "No xray_key.txt found in KOReader directory.",
                        timeout = 4
                    })
                end
            end
        }

        local close_btn = Button:new{
            text = self.loc:t("close") or "Close",
            face = Font:getFace("cfont", ui_font_size),
            width = (dialog_w - sc(40)) / 2,
            height = sc(42),
            bordersize = is_close_focused and (xray_theme.border_focus or sc(2)) or xray_theme.border_btn,
            background = is_close_focused and (xray_theme.color_focus_bg or Blitbuffer.Color8(230)) or nil,
            radius = xray_theme.radius_btn,
            callback = function()
                if overlay then
                    UIManager:close(overlay, "ui")
                    overlay = nil
                end
            end
        }

        local btn_row = HorizontalGroup:new{
            align = "center",
            import_btn,
            WidgetContainer:new{ dimen = Geom:new{ w = sc(8), h = 1 } },
            close_btn,
        }
        table.insert(content_vg, btn_row)

        local inner_card = FrameContainer:new{
            padding = sc(12),
            radius = xray_theme.radius_window,
            bordersize = sc(2),
            color = Blitbuffer.COLOR_BLACK,
            background = xray_theme.color_bg,
            width = dialog_w - sc(2),
            content_vg
        }

        return FrameContainer:new{
            bordersize = sc(1),
            color = Blitbuffer.Color8(180),
            padding = 0,
            background = xray_theme.color_bg,
            radius = xray_theme.radius_window,
            width = dialog_w,
            inner_card
        }
    end

    local card = buildGuideCard()

    local movable = MovableContainer:new{
        CenterContainer:new{
            dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh },
            card
        }
    }

    overlay = InputContainer:new{
        dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh },
        key_events = {
            PrevButton = {
                { "Left" },
                { "Up" },
                { "PrevPage" },
            },
            NextButton = {
                { "Right" },
                { "Down" },
                { "NextPage" },
            },
            Select = {
                { "Return" },
                { "KP_Enter" },
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
        movable
    }

    local function refreshUI()
        overlay[1] = MovableContainer:new{
            CenterContainer:new{
                dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh },
                buildGuideCard()
            }
        }
        UIManager:setDirty(overlay, "ui")
    end

    overlay.onPrevButton = function()
        focused_btn = (focused_btn == 1) and 2 or 1
        refreshUI()
        return true
    end

    overlay.onNextButton = function()
        focused_btn = (focused_btn == 1) and 2 or 1
        refreshUI()
        return true
    end

    overlay.onSelect = function()
        if focused_btn == 1 then
            local ok, count, path = self.ai_helper:importFromTextFile(true)
            if ok and count > 0 then
                self.ai_helper:init(self.path)
                if overlay then
                    UIManager:close(overlay, "ui")
                    overlay = nil
                end
                UIManager:show(InfoMessage:new{
                    text = string.format("Imported %d API key(s) from %s", count, tostring(path)),
                    timeout = 4
                })
                UIManager:setDirty(nil, "ui")
            else
                UIManager:show(InfoMessage:new{
                    text = self.loc:t("welcome_no_file_found") or "No xray_key.txt found in KOReader directory.",
                    timeout = 4
                })
            end
        else
            if overlay then
                UIManager:close(overlay, "ui")
                overlay = nil
            end
        end
        return true
    end

    overlay.onClose = function()
        if overlay then
            UIManager:close(overlay, "ui")
            overlay = nil
        end
        return true
    end

    UIManager:show(overlay, "ui")
end

function M:getAPIKeysMenu()
    local menu_items = {}

    -- Option 1: Set Key from Phone/PC
    table.insert(menu_items, {
        text = (self.loc:t("menu_set_keys_device") or "Set API Key from Phone/PC") .. "...",
        keep_menu_open = true,
        callback = function()
            local WebSetup = require(plugin_path .. "xray_websetup")
            WebSetup:startCloudRelay(self.ai_helper, self.loc, function()
                self.ai_helper:init(self.path)
                self:refreshAPIKeysMenu()
            end)
        end,
    })

    -- Option 2: Config & Text File Guide
    table.insert(menu_items, {
        text = self.loc:t("welcome_file_guide_title") or "Config & Text File Setup...",
        keep_menu_open = true,
        callback = function()
            self:showConfigFileGuide()
        end,
    })

    -- Option 3: On-Demand Key Validation Button
    table.insert(menu_items, {
        text = self.loc:t("menu_validate_all_keys") or "Test & Validate All API Keys",
        keep_menu_open = true,
        callback = function()
            self:showValidateAllKeysDialog()
        end,
        separator = true,
    })

    -- Option 4: Dynamic Clipboard detection banner
    local Utils = require(plugin_path .. "xray_utils")
    local clip_prov, clip_key = Utils:getClipboardKey()
    if clip_prov and clip_key and #clip_key > 0 then
        local prov_label = clip_prov:upper()
        if clip_prov == "gemini" then prov_label = "Google Gemini"
        elseif clip_prov == "chatgpt" then prov_label = "OpenAI ChatGPT"
        elseif clip_prov == "deepseek" then prov_label = "DeepSeek"
        elseif clip_prov == "claude" then prov_label = "Anthropic Claude"
        end
        local preview = #clip_key > 8 and (clip_key:sub(1, 4) .. "••••" .. clip_key:sub(-4)) or "••••••••"
        table.insert(menu_items, {
            text = string.format(self.loc:t("menu_paste_clipboard") or "Paste %s Key from Clipboard", prov_label) .. " (" .. preview .. ")",
            keep_menu_open = true,
            callback = function()
                local ButtonDialog = require("ui/widget/buttondialog")
                local confirm_dlg
                confirm_dlg = ButtonDialog:new{
                    modal = true,
                    title = string.format(self.loc:t("paste_clipboard_confirm") or "Use the API key found in clipboard for %s?", prov_label) .. "\n\n" .. preview,
                    buttons = {
                        {
                            {
                                text = self.loc:t("cancel") or "Cancel",
                                id = "close",
                                callback = function()
                                    UIManager:close(confirm_dlg)
                                end,
                            },
                            {
                                text = self.loc:t("save") or "Save",
                                is_enter_default = true,
                                callback = function()
                                    UIManager:close(confirm_dlg)
                                    self.ai_helper:setAPIKey(clip_prov, clip_key)
                                    self.ai_helper:updateConfigKey(clip_prov .. "_api_key", clip_key)
                                    self.ai_helper:init(self.path)
                                    UIManager:setDirty(nil, "ui")
                                    UIManager:show(InfoMessage:new{ text = "Saved " .. prov_label .. " API key!", timeout = 3 })
                                end,
                            },
                        }
                    }
                }
                UIManager:show(confirm_dlg)
            end,
            separator = true,
        })
    end

    local providers = {
        { id = "gemini", name = "Google Gemini" },
        { id = "chatgpt", name = "OpenAI ChatGPT" },
        { id = "deepseek", name = "DeepSeek" },
        { id = "claude", name = "Anthropic Claude" },
        { id = "custom1", name = "Custom API 1" },
        { id = "custom2", name = "Custom API 2" },
    }
    for _, p in ipairs(providers) do
        local pid = p.id
        local pname = p.name
        local function getProviderText()
            local prov_data = self.ai_helper and self.ai_helper.providers and self.ai_helper.providers[pid]
            local active_val = prov_data and prov_data.api_key or ""
            local status
            if pid:find("custom") then
                local endpoint = prov_data and prov_data.endpoint or ""
                local host = endpoint:match("^https?://([^/]+)") or endpoint
                local model = prov_data and prov_data.model or ""
                if host ~= "" or model ~= "" then
                    status = (host ~= "" and host or "?") .. " | " .. (model ~= "" and model or "?")
                else
                    status = self.loc:t("custom_api_not_configured") or "(not configured — tap to set up)"
                end
            else
                status = (active_val ~= "") and (active_val:sub(1,6) .. "...") or "(None)"
            end
            local source = (prov_data and prov_data.ui_key_active) and "[UI]" or "[Config]"
            return pname .. " " .. source .. ": " .. status
        end

        table.insert(menu_items, {
            text = getProviderText(),
            text_func = getProviderText,
            keep_menu_open = true,
            sub_item_table_func = function() return self:getProviderKeySubMenu(pid, pname) end
        })
    end

    -- Clear All Configured Keys button
    table.insert(menu_items, {
        text = self.loc:t("menu_clear_all_keys") or "Clear All API Keys...",
        keep_menu_open = true,
        callback = function()
            local ButtonDialog = require("ui/widget/buttondialog")
            local confirm
            confirm = ButtonDialog:new{
                modal = true,
                title = self.loc:t("confirm_clear_all_keys") or "Are you sure you want to clear all configured API keys and custom endpoints?\n\nThis will remove all saved keys from this device.",
                buttons = {
                    {
                        {
                            text = self.loc:t("cancel") or "Cancel",
                            id = "close",
                            callback = function()
                                UIManager:close(confirm)
                            end,
                        },
                        {
                            text = self.loc:t("btn_clear_keys") or "Clear All Keys",
                            is_enter_default = true,
                            callback = function()
                                UIManager:close(confirm)
                                self.ai_helper:clearAllAPIKeys()
                                UIManager:show(InfoMessage:new{
                                    text = self.loc:t("keys_cleared") or "All API keys cleared.",
                                    timeout = 3
                                })
                                UIManager:setDirty(nil, "ui")
                            end,
                        },
                    }
                }
            }
            UIManager:show(confirm)
        end,
        separator = true,
    })

    return menu_items
end

function M:getProviderKeySubMenu(provider, provider_name)
    local config_key = (self.ai_helper and self.ai_helper.config_keys) and self.ai_helper.config_keys[provider] or ""
    local ui_key = (self.ai_helper and self.ai_helper.settings) and self.ai_helper.settings[provider .. "_api_key"] or ""
    local Device = require("device")
    
    local menu_items = {
        {
            text = self.loc:t("menu_test_key") or "Test Connection",
            keep_menu_open = true,
            callback = function()
                self:testSingleProviderConnection(provider, provider_name)
            end,
            separator = true,
        },
        {
            text = "Use key from config.lua: " .. (#config_key > 0 and (config_key:sub(1,6) .. "...") or "(Not set)"),
            text_func = function()
                local cfg_key = (self.ai_helper and self.ai_helper.config_keys) and self.ai_helper.config_keys[provider] or ""
                return "Use key from config.lua: " .. (#cfg_key > 0 and (cfg_key:sub(1,6) .. "...") or "(Not set)")
            end,
            checked_func = function() 
                if not self.ai_helper or not self.ai_helper.providers or not self.ai_helper.providers[provider] then return false end
                return not self.ai_helper.providers[provider].ui_key_active 
            end,
            callback = function()
                self.ai_helper:saveSettings({ [provider .. "_use_ui_key"] = false })
                self.ai_helper:init(self.path)
                UIManager:setDirty(nil, "ui")
            end
        },
        {
            text = "Use UI override key: " .. (#ui_key > 0 and (ui_key:sub(1,6) .. "...") or "(Not set)"),
            text_func = function()
                local u_key = (self.ai_helper and self.ai_helper.settings) and self.ai_helper.settings[provider .. "_api_key"] or ""
                return "Use UI override key: " .. (#u_key > 0 and (u_key:sub(1,6) .. "...") or "(Not set)")
            end,
            checked_func = function() 
                if not self.ai_helper or not self.ai_helper.providers or not self.ai_helper.providers[provider] then return false end
                return self.ai_helper.providers[provider].ui_key_active 
            end,
            callback = function()
                local u_key = (self.ai_helper and self.ai_helper.settings) and self.ai_helper.settings[provider .. "_api_key"] or ""
                -- If we have a UI key but it's not currently active, let's just activate it
                if #u_key > 0 and not self.ai_helper.providers[provider].ui_key_active then
                    self.ai_helper:saveSettings({ [provider .. "_use_ui_key"] = true })
                    self.ai_helper:init(self.path)
                    UIManager:setDirty(nil, "ui")
                    return
                end

                if provider:find("custom") then
                    local InputDialog = require("ui/widget/inputdialog")
                    local InfoMessage = require("ui/widget/infomessage")
                    
                    local function promptModel(endpoint, key)
                        local current_model = (self.ai_helper and self.ai_helper.settings) and self.ai_helper.settings[provider .. "_model"] or ""
                        local model_dialog
                        model_dialog = InputDialog:new{
                            title = self.loc:t("custom_api_model_title", provider:sub(-1)),
                            input = current_model,
                            input_hint = self.loc:t("custom_api_model_hint") or "e.g., google/gemini-2.5-flash or openai/gpt-4o",
                            buttons = {
                                {
                                    { text = self.loc:t("cancel"), callback = function() UIManager:close(model_dialog) end },
                                    { text = self.loc:t("save"), is_enter_default = true, callback = function()
                                        local model = model_dialog:getInputText()
                                        UIManager:close(model_dialog)
                                        self.ai_helper:setCustomAPIConfig(provider, key, endpoint, model)
                                        self.ai_helper:init(self.path)
                                        UIManager:show(InfoMessage:new{ text = self.loc:t("custom_api_saved", provider:sub(-1)), timeout = 3 })
                                        UIManager:setDirty(nil, "ui")
                                    end }
                                }
                            }
                        }
                        UIManager:show(model_dialog)
                        model_dialog:onShowKeyboard()
                    end

                    local function promptKey(endpoint)
                        local key_dialog
                        local key_buttons = {
                            { text = self.loc:t("cancel"), callback = function() UIManager:close(key_dialog) end }
                        }
                        if Device.hasClipboard and Device:hasClipboard() then
                            table.insert(key_buttons, {
                                text = self.loc:t("btn_paste") or "Paste",
                                callback = function()
                                    local ok, clip = pcall(function() return Device:getClipboardText() end)
                                    if ok and clip and #clip > 0 then
                                        key_dialog:setInputText(clip:match("^%s*(.-)%s*$"))
                                    end
                                end
                            })
                        end
                        table.insert(key_buttons, {
                            text = self.loc:t("next") or "Next",
                            is_enter_default = true,
                            callback = function()
                                local key = key_dialog:getInputText()
                                UIManager:close(key_dialog)
                                promptModel(endpoint, key)
                            end
                        })

                        key_dialog = InputDialog:new{
                            title = self.loc:t("custom_api_key_title", provider:sub(-1)),
                            input = ui_key,
                            buttons = { key_buttons }
                        }
                        UIManager:show(key_dialog)
                        key_dialog:onShowKeyboard()
                    end

                    local function promptEndpoint()
                        local current_endpoint = (self.ai_helper and self.ai_helper.settings) and self.ai_helper.settings[provider .. "_endpoint"] or "https://openrouter.ai/api/v1/chat/completions"
                        local endpoint_dialog
                        endpoint_dialog = InputDialog:new{
                            title = self.loc:t("custom_api_endpoint_title", provider:sub(-1)),
                            input = current_endpoint,
                            input_hint = self.loc:t("custom_api_endpoint_hint") or "e.g., https://openrouter.ai/api/v1/chat/completions",
                            buttons = {
                                {
                                    { text = self.loc:t("cancel"), callback = function() UIManager:close(endpoint_dialog) end },
                                    { text = self.loc:t("next") or "Next", is_enter_default = true, callback = function()
                                        local endpoint = endpoint_dialog:getInputText()
                                        UIManager:close(endpoint_dialog)
                                        promptKey(endpoint)
                                    end }
                                }
                            }
                        }
                        UIManager:show(endpoint_dialog)
                        endpoint_dialog:onShowKeyboard()
                    end
                    
                    promptEndpoint()
                    return
                end

                local InputDialog = require("ui/widget/inputdialog")
                local input_dialog
                local dlg_buttons = {
                    { text = self.loc:t("cancel"), callback = function() UIManager:close(input_dialog) end }
                }
                if Device.hasClipboard and Device:hasClipboard() then
                    table.insert(dlg_buttons, {
                        text = self.loc:t("btn_paste") or "Paste",
                        callback = function()
                            local ok, clip = pcall(function() return Device:getClipboardText() end)
                            if ok and clip and #clip > 0 then
                                input_dialog:setInputText(clip:match("^%s*(.-)%s*$"))
                            end
                        end
                    })
                end
                table.insert(dlg_buttons, {
                    text = self.loc:t("save"),
                    is_enter_default = true,
                    callback = function()
                        local key = input_dialog:getInputText()
                        UIManager:close(input_dialog)
                        if key and #key > 0 then
                            self.ai_helper:saveSettings({ 
                                [provider .. "_api_key"] = key,
                                [provider .. "_use_ui_key"] = true
                            })
                            self.ai_helper:updateConfigKey(provider .. "_api_key", key)
                            self.ai_helper:init(self.path)
                            self:refreshAPIKeysMenu()
                        end
                    end
                })

                input_dialog = InputDialog:new{
                    title = provider_name .. " API Key",
                    input = ui_key,
                    buttons = { dlg_buttons }
                }
                UIManager:show(input_dialog)
                input_dialog:onShowKeyboard()
            end
        }
    }

    -- For custom slots: add a toggle to mark the model as a reasoning model.
    -- When enabled, the plugin raises the output token ceiling to 32000 to accommodate
    -- reasoning chains that would otherwise consume the entire output budget.
    if provider:find("custom") then
        table.insert(menu_items, {
            text = self.loc:t("custom_api_is_reasoning") or "Is Reasoning Model (e.g. DeepSeek-R1)",
            keep_menu_open = true,
            checked_func = function()
                return (self.ai_helper and self.ai_helper.settings) and self.ai_helper.settings[provider .. "_is_reasoning"] or false
            end,
            callback = function()
                local current = (self.ai_helper and self.ai_helper.settings) and self.ai_helper.settings[provider .. "_is_reasoning"] or false
                self.ai_helper:saveSettings({ [provider .. "_is_reasoning"] = not current })
                self:refreshAPIKeysMenu()
            end
        })
    end

    -- Clear Single Provider Key button
    table.insert(menu_items, {
        text = string.format(self.loc:t("menu_clear_single_key") or "Clear %s Key...", provider_name),
        keep_menu_open = true,
        callback = function()
            local ButtonDialog = require("ui/widget/buttondialog")
            local confirm
            confirm = ButtonDialog:new{
                title = string.format(self.loc:t("confirm_clear_single_key") or "Clear the configured API key for %s?", provider_name),
                buttons = {
                    {
                        {
                            text = self.loc:t("cancel") or "Cancel",
                            id = "close",
                            callback = function()
                                UIManager:close(confirm)
                            end,
                        },
                        {
                            text = self.loc:t("btn_clear_key") or "Clear Key",
                            is_enter_default = true,
                            callback = function()
                                UIManager:close(confirm)
                                self.ai_helper:clearProviderKey(provider)
                                UIManager:show(InfoMessage:new{
                                    text = string.format(self.loc:t("single_key_cleared") or "%s API key cleared.", provider_name),
                                    timeout = 3
                                })
                                UIManager:setDirty(nil, "ui")
                            end,
                        },
                    }
                }
            }
            UIManager:show(confirm)
        end,
        separator = true,
    })

    return menu_items
end

function M:testSingleProviderConnection(provider, provider_name)
    local NetworkMgr = require("ui/network/manager")
    NetworkMgr:runWhenOnline(function()
        local InfoMessage = require("ui/widget/infomessage")
        local wait_msg = InfoMessage:new{ text = self.loc:t("testing_api_keys") or "Testing API key connection...", timeout = 10 }
        UIManager:show(wait_msg)
        
        local res = self.ai_helper:validateProviderKey(provider)
        UIManager:close(wait_msg)
        
        if res.ok then
            UIManager:show(InfoMessage:new{
                text = string.format("[OK] %s: %s (%d ms)", provider_name, "Connected successfully!", res.latency_ms or 0),
                timeout = 5
            })
        elseif res.not_configured then
            UIManager:show(InfoMessage:new{
                text = string.format("[--] %s: %s", provider_name, "No API key configured."),
                timeout = 4
            })
        else
            UIManager:show(InfoMessage:new{
                text = string.format("[ERR] %s: %s", provider_name, res.error or "Connection failed"),
                timeout = 6
            })
        end
    end)
end

function M:showValidateAllKeysDialog()
    local NetworkMgr = require("ui/network/manager")
    NetworkMgr:runWhenOnline(function()
        local InfoMessage = require("ui/widget/infomessage")
        local ButtonDialog = require("ui/widget/buttondialog")
        local VerticalGroup = require("ui/widget/verticalgroup")
        local TextBoxWidget = require("ui/widget/textboxwidget")
        local VerticalSpan = require("ui/widget/verticalspan")
        local Font = require("ui/font")
        local Device = require("device")
        local Screen = Device.screen
        local Size = require("ui/size")

        local wait_msg = InfoMessage:new{ text = self.loc:t("testing_api_keys") or "Testing API key connections...", timeout = 15 }
        UIManager:show(wait_msg)

        local results = self.ai_helper:validateAllConfiguredKeys()
        UIManager:close(wait_msg)

        local provider_names = {
            gemini = "Google Gemini",
            chatgpt = "OpenAI ChatGPT",
            deepseek = "DeepSeek",
            claude = "Anthropic Claude",
            custom1 = "Custom API 1",
            custom2 = "Custom API 2",
        }

        local dialog_width = math.floor(math.min(Screen:getWidth(), Screen:getHeight()) * 0.9)
        local border_window = 1
        local padding_button = 10
        local padding_default = 10
        local margin_default = 5
        pcall(function()
            if Size and Size.border and Size.border.window then border_window = Size.border.window end
            if Size and Size.padding and Size.padding.button then padding_button = Size.padding.button end
            if Size and Size.padding and Size.padding.default then padding_default = Size.padding.default end
            if Size and Size.margin and Size.margin.default then margin_default = Size.margin.default end
        end)
        local buttontable_width = dialog_width - 2 * border_window - 2 * padding_button
        local content_width = buttontable_width - 2 * (padding_default + margin_default)

        local base_fs = 15
        if G_reader_settings then
            local fs = G_reader_settings:readSetting("cre_font_size")
            if fs and type(fs) == "number" then
                base_fs = math.max(14, math.min(fs, 20))
            end
        end

        local vg_components = { align = "left" }

        -- Title
        table.insert(vg_components, TextBoxWidget:new{
            text = self.loc:t("validate_keys_title") or "API Key Status & Validation",
            face = Font:getFace("cfont", base_fs + 3),
            bold = true,
            width = content_width,
            alignment = "center",
        })
        table.insert(vg_components, VerticalSpan:new{ width = 10 })

        for _, id in ipairs({"gemini", "chatgpt", "deepseek", "claude", "custom1", "custom2"}) do
            local name = provider_names[id] or id
            local r = results[id]
            if r then
                local tag_text, desc_text
                if r.ok then
                    tag_text = "[OK]  " .. name
                    desc_text = string.format("Connected (%d ms)", r.latency_ms or 0)
                elseif r.not_configured then
                    tag_text = "[--]  " .. name
                    desc_text = "Not configured"
                else
                    tag_text = "[ERR] " .. name
                    desc_text = "Failed: " .. tostring(r.error or "Unknown error")
                end

                table.insert(vg_components, TextBoxWidget:new{
                    text = tag_text,
                    face = Font:getFace("cfont", base_fs),
                    bold = true,
                    width = content_width,
                    alignment = "left",
                })
                table.insert(vg_components, TextBoxWidget:new{
                    text = "       " .. desc_text,
                    face = Font:getFace("cfont", base_fs - 1),
                    width = content_width,
                    alignment = "left",
                })
                table.insert(vg_components, VerticalSpan:new{ width = 6 })
            end
        end

        local vg = VerticalGroup:new(vg_components)

        local result_dialog
        result_dialog = ButtonDialog:new{
            _added_widgets = { vg },
            buttons = {
                {
                    {
                        text = self.loc:t("menu_test_key") or "Re-test",
                        callback = function()
                            UIManager:close(result_dialog)
                            self:showValidateAllKeysDialog()
                        end
                    },
                    {
                        text = self.loc:t("close") or "Close",
                        is_enter_default = true,
                        callback = function()
                            UIManager:close(result_dialog)
                        end
                    }
                }
            }
        }
        UIManager:show(result_dialog)
    end)
end

function M:getAIModelSelectionMenu(setting_type)
    local providers = {
        {
            id = "gemini",
            display_name = "Gemini",
            models = {
                { id = "gemini-4-hydrogen", cost = "free" },
                { id = "gemini-3.8-flash", cost = "free" },
                { id = "gemini-3.6-flash", cost = "free" },
                { id = "gemini-3.5-flash-lite", cost = "free" },
                { id = "gemini-4-argon", cost = "paid" },
                { id = "gemini-3.1-pro-preview", cost = "paid" },
                { id = "gemini-2.5-pro", cost = "paid" },
            }
        },
        {
            id = "chatgpt",
            display_name = "ChatGPT",
            models = {
                { id = "gpt-6-luna", cost = "paid" },
                { id = "gpt-5.6-terra", cost = "paid" },
                { id = "gpt-5.6-luna", cost = "paid" },
                { id = "gpt-5.5", cost = "paid" },
                { id = "gpt-5.4-mini", cost = "paid" },
                { id = "gpt-5.4-nano", cost = "paid" },
            }
        },
        {
            id = "deepseek",
            display_name = "DeepSeek",
            models = {
                { id = "deepseek-flash", cost = "paid" },
                { id = "deepseek-v4-pro", cost = "paid" },
            }
        },
        {
            id = "claude",
            display_name = "Claude",
            models = {
                { id = "claude-sonnet-5-5", cost = "paid" },
                { id = "claude-sonnet-5", cost = "paid" },
                { id = "claude-sonnet-4-6", cost = "paid" },
                { id = "claude-haiku-5-5", cost = "paid" },
                { id = "claude-haiku-4-5", cost = "paid" },
            }
        }
    }
    
    -- Prefer the merged provider config: it covers models configured via
    -- xray_config.lua, not only those entered in the API Keys UI (issue #86).
    local function getCustomSlotModel(slot)
        local model = self.ai_helper and self.ai_helper.providers
            and self.ai_helper.providers[slot] and self.ai_helper.providers[slot].model
        if not model or model == "" then
            model = self.ai_helper and self.ai_helper.settings and self.ai_helper.settings[slot .. "_model"]
        end
        if model == "" then model = nil end
        return model
    end
    local custom1_model = getCustomSlotModel("custom1")
    local custom2_model = getCustomSlotModel("custom2")
    
    local menu_items = {}
    
    for _, p in ipairs(providers) do
        local provider_id = p.id
        local provider_name = p.display_name
        local provider_models = p.models
        table.insert(menu_items, {
            text = provider_name,
            keep_menu_open = true,
            checked_func = function()
                if not self.ai_helper or not self.ai_helper.settings then return false end
                local current = setting_type == "primary" and self.ai_helper.settings.primary_ai or self.ai_helper.settings.secondary_ai
                if type(current) ~= "table" then return false end
                return current.provider == provider_id
            end,
            sub_item_table_func = function()
                local sub_items = {}
                for _, m in ipairs(provider_models) do
                    local model_id = m.id
                    local model_cost = m.cost
                    table.insert(sub_items, {
                        text = model_id .. " [" .. (model_cost == "free" and self.loc:t("model_free") or self.loc:t("model_paid")) .. "]",
                        checked_func = function()
                            if not self.ai_helper or not self.ai_helper.settings then return false end
                            local current = setting_type == "primary" and self.ai_helper.settings.primary_ai or self.ai_helper.settings.secondary_ai
                            if type(current) ~= "table" then return false end
                            return current.provider == provider_id and current.model == model_id
                        end,
                        callback = function()
                            self.ai_helper:setUnifiedModel(setting_type, provider_id, model_id)
                            UIManager:setDirty(nil, "ui")
                        end
                    })
                end
                return sub_items
            end
        })
    end
    
    table.insert(menu_items, {
        text = "Custom API 1: " .. (custom1_model or "(configure in API Keys)"),
        checked_func = function()
            if not self.ai_helper or not self.ai_helper.settings then return false end
            local current = setting_type == "primary" and self.ai_helper.settings.primary_ai or self.ai_helper.settings.secondary_ai
            if type(current) ~= "table" then return false end
            return current.provider == "custom1" and current.model == (custom1_model or "custom1")
        end,
        callback = function()
            self.ai_helper:setUnifiedModel(setting_type, "custom1", custom1_model or "custom1")
            UIManager:setDirty(nil, "ui")
        end
    })
    table.insert(menu_items, {
        text = "Custom API 2: " .. (custom2_model or "(configure in API Keys)"),
        checked_func = function()
            if not self.ai_helper or not self.ai_helper.settings then return false end
            local current = setting_type == "primary" and self.ai_helper.settings.primary_ai or self.ai_helper.settings.secondary_ai
            if type(current) ~= "table" then return false end
            return current.provider == "custom2" and current.model == (custom2_model or "custom2")
        end,
        callback = function()
            self.ai_helper:setUnifiedModel(setting_type, "custom2", custom2_model or "custom2")
            UIManager:setDirty(nil, "ui")
        end,
        separator = true
    })
    table.insert(menu_items, {
        text = self.loc:t("menu_enter_custom_model") or "Enter custom model...",
        keep_menu_open = true,
        callback = function()
            local InputDialog = require("ui/widget/inputdialog")
            local input_dialog
            local current = (self.ai_helper and self.ai_helper.settings) and (setting_type == "primary" and self.ai_helper.settings.primary_ai or self.ai_helper.settings.secondary_ai) or nil
            input_dialog = InputDialog:new{
                title = (self.loc:t("menu_custom_model_title") or "Custom %s Model"):format(setting_type:gsub("^%l", string.upper)),
                input = current and current.model or "",
                input_hint = "e.g., gemini-2.5-pro",
                buttons = {
                    {
                        {
                            text = self.loc:t("cancel") or "Cancel",
                            callback = function() UIManager:close(input_dialog) end
                        },
                        {
                            text = self.loc:t("save") or "Save",
                            is_enter_default = true,
                            callback = function()
                                local custom_model = input_dialog:getInputText()
                                if custom_model and #custom_model > 0 then
                                    local provider = string.find(custom_model, "gpt") and "chatgpt" or "custom1"
                                    if string.find(custom_model, "deepseek") then provider = "deepseek" end
                                    if string.find(custom_model, "claude") then provider = "claude" end
                                    if string.find(custom_model, "gemini") then provider = "gemini" end
                                    self.ai_helper:setUnifiedModel(setting_type, provider, custom_model)
                                    UIManager:show(InfoMessage:new{ text = setting_type:gsub("^%l", string.upper) .. " AI set to " .. custom_model, timeout = 3 })
                                    UIManager:setDirty(nil, "ui")
                                end
                                UIManager:close(input_dialog)
                            end
                        }
                    }
                }
            }
            UIManager:show(input_dialog)
            input_dialog:onShowKeyboard()
        end
    })
    
    return menu_items
end


return M
