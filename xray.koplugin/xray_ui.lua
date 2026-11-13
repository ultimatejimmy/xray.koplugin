-- X-Ray UI and Menu Functions
local util = require("util")
local logger = require("logger")

local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local ButtonDialog = require("ui/widget/buttondialog")
local Menu = require("ui/widget/menu")
local Screen = require("device").screen
local gettext = require("gettext")
local orig_isRTL = gettext.isRTL
local plugin_instance
local B1 = "\xEF\xBF\xB2" -- PTF_BOLD_START
local B2 = "\xEF\xBF\xB3" -- PTF_BOLD_END

gettext.isRTL = function(...)
    if plugin_instance and plugin_instance:isRTL() and plugin_instance:isXRayUIActive() then
        return true
    end
    if orig_isRTL then
        return orig_isRTL(...)
    end
    return false
end

local _ = gettext
local plugin_path = ((...) or ""):match("(.-)[^%.]+$") or ""
local xray_units = require(plugin_path .. "xray_units")
local XRaySettingsCard = require(plugin_path .. "xray_settings_card")
local utils = require(plugin_path .. "xray_utils")
local SeriesManager = require(plugin_path .. "xray_seriesmanager")

local function bookHasEntities(b, sm)
    if not b or type(b) ~= "table" then return false end
    if sm and sm.hasBookEntities then return sm.hasBookEntities(b) end
    if SeriesManager and SeriesManager.hasBookEntities then return SeriesManager.hasBookEntities(b) end
    return ((b.characters and #b.characters > 0) or
            (b.locations and #b.locations > 0) or
            (b.terms and #b.terms > 0) or
            (b.timeline and #b.timeline > 0)) and true or false
end

local M = {}

local function safeRequireSubModule(name)
    local ok, sub_mod = pcall(require, plugin_path .. name)
    if ok and type(sub_mod) == "table" then
        for k, v in pairs(sub_mod) do
            M[k] = v
        end
    end
end
safeRequireSubModule("xray_duplicates")
safeRequireSubModule("xray_onboarding")
safeRequireSubModule("xray_horizon")
safeRequireSubModule("xray_images_ui")
safeRequireSubModule("xray_bottom_popup")
safeRequireSubModule("xray_log_viewer")
safeRequireSubModule("xray_series_ui")

-- ─────────────────────────────────────────────────────────────────────────────
-- Bottom-panel popup widget and imports for new UI
-- ─────────────────────────────────────────────────────────────────────────────
local Blitbuffer      = require("ffi/blitbuffer")
local Font            = require("ui/font")
local Geom            = require("ui/geometry")
local GestureRange    = require("ui/gesturerange")
local InputContainer  = require("ui/widget/container/inputcontainer")
local FrameContainer  = require("ui/widget/container/framecontainer")
local LeftContainer   = require("ui/widget/container/leftcontainer")
local RightContainer  = require("ui/widget/container/rightcontainer")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local TextBoxWidget   = require("ui/widget/textboxwidget")
local LineWidget      = require("ui/widget/linewidget")
local Button          = require("ui/widget/button")
local Size            = require("ui/size")
local CenterContainer = require("ui/widget/container/centercontainer")
local ImageWidget     = require("ui/widget/imagewidget")

local _asset_path_cache = {}
local function getAssetPath(filename)
    if _asset_path_cache[filename] then
        return _asset_path_cache[filename]
    end
    local info = debug.getinfo(1, "S")
    local file_dir = (info and info.source and info.source:match("^@?(.*[/\\])")) or ""
    local candidates = {
        file_dir .. "assets/" .. filename,
        file_dir .. "../assets/" .. filename,
        "plugins/xray.koplugin/assets/" .. filename,
        "./plugins/xray.koplugin/assets/" .. filename,
    }
    for _, path in ipairs(candidates) do
        local f = io.open(path, "r")
        if f then
            f:close()
            _asset_path_cache[filename] = path
            return path
        end
    end
    local fallback = "plugins/xray.koplugin/assets/" .. filename
    _asset_path_cache[filename] = fallback
    return fallback
end

local function makeMenuIcon(icon_file, icon_sz, container_w)
    local sz = icon_sz or (Screen.scaleBySize and Screen:scaleBySize(18) or 18)
    local w = container_w or (Screen.scaleBySize and Screen:scaleBySize(28) or 28)
    return CenterContainer:new{
        dimen = Geom:new{ w = w, h = Screen.scaleBySize and Screen:scaleBySize(36) or 36 },
        ImageWidget:new{
            file = getAssetPath(icon_file),
            width = sz,
            height = sz,
            scale_factor = 0,
            is_icon = true,
            alpha = true,
        }
    }
end

local DEFAULT_POPUP_FONT_SIZE = 22

-- Returns true if the text contains CJK characters (U+3000–U+9FFF, etc.)
local function _textHasCJK(text)
    return utils:textHasCJK(text)
end

-- Truncates a string to limit_en characters (scaled down to limit_en/3 if CJK)
-- only if the total length exceeds threshold_en (scaled down to threshold_en/3 if CJK).
-- Returns: truncated_text, is_truncated
local function _getTruncatedText(text, limit_en, threshold_en)
    return utils:getTruncatedText(text, limit_en, threshold_en)
end


-- Returns true if the font family name looks like a CJK font
local function _isCJKFontFamily(family)
    if not family then return false end
    local fl = family:lower()
    return (fl:find("cjk") or fl:find("han") or fl:find("wenquanyi")
        or fl:find("noto.*jp") or fl:find("noto.*sc") or fl:find("noto.*tc")
        or fl:find("noto.*kr") or fl:find("source han") or fl:find("adobe")
        or fl:find("kozuka") or fl:find("hiragino") or fl:find("meiryo")
        or fl:find("yugothic") or fl:find("simhei") or fl:find("simsun")
        or fl:find("mingliu") or fl:find("kaiti") or fl:find("fangzheng")) ~= nil
end

local function _getPopupFontSize(plugin)
    local p = (plugin and plugin.plugin) or plugin or plugin_instance
    local size
    if p and p.ui and p.ui.font and p.ui.font.configurable then
        size = p.ui.font.configurable.font_size
    elseif G_reader_settings then
        size = G_reader_settings:readSetting("cre_font_size")
              or G_reader_settings:readSetting("kopt_font_size")
    end
    if size then
        return size  -- raw pt value; Font:getFace will call scaleBySize internally
    end
    -- Absolute fallback when no book is open
    if Screen.scaleBySize then
        return Screen:scaleBySize(22)
    end
    return 22
end

local function formatDialogButtons(action_btns, close_btn, top_btn)
    local all_btns = {}
    for _, btn in ipairs(action_btns or {}) do
        table.insert(all_btns, btn)
    end
    table.insert(all_btns, close_btn)

    local rows = {}
    if top_btn then
        table.insert(rows, { top_btn })
    end

    local i = 1
    while i <= #all_btns do
        if i + 1 <= #all_btns then
            table.insert(rows, { all_btns[i], all_btns[i + 1] })
            i = i + 2
        else
            table.insert(rows, { all_btns[i] })
            i = i + 1
        end
    end
    return rows
end

-- Bottom popup widget extracted to xray_bottom_popup.lua
local function showBottomPopup(...)
    return M.showBottomPopup(...)
end

local function shouldUseBottomPopup(...)
    return M.shouldUseBottomPopup(...)
end

function M:showLanguageSelection()
    local Menu = require("ui/widget/menu")
    local settings_lang = (self.ai_helper and self.ai_helper.settings) and self.ai_helper.settings.language or "auto"
    
    local function changeLang(lang_code)
        UIManager:close(self.ldlg)
        self.ldlg = nil
        
        if self.ai_helper then
            self.ai_helper:saveSettings({ language = lang_code })
        end
        
        -- Apply the new setting immediately
        self:applyLanguageLogic()
        
        local msg = (self.loc and self.loc:t("language_changed_reopen")) or "Language changed. Reopen the menu to see the changes."
        
        -- Use the centralized silver-bullet clear
        self:closeAllMenus()
        
        UIManager:show(InfoMessage:new{
            text = "[OK] " .. msg,
            timeout = 3
        })
    end
    
    local items = {
        {
            text = (settings_lang == "auto" and "[✓] " or "[  ] ") .. (self.loc:t("lang_follow_system") or "Automatic (Follow System)"),
            callback = function() changeLang("auto") end
        },
        {
            text = (settings_lang == "book" and "[✓] " or "[  ] ") .. (self.loc:t("lang_follow_book") or "Automatic (Follow Book)"),
            callback = function() changeLang("book") end,
            separator = true
        }
    }
    
    local LANGUAGE_NAMES = {
        en = "English",
        de = "Deutsch",
        fr = "Français",
        ru = "Русский",
        zh_CN = "简体中文",
        ja = "日本語",
        tr = "Türkçe",
        pt_br = "Português",
        es = "Español",
        uk = "Українська",
        hu = "Magyar",
        nl = "Nederlands",
        pl = "Polski",
        id = "Bahasa Indonesia",
        ar = "العربية",
        it = "Italiano",
        sr = "Српски",
        sk = "Slovenčina",
        cs = "Čeština",
    }
    
    local langs = self.loc and self.loc.available_languages or { "en", "de", "fr", "ru", "zh_CN", "tr", "pt_br", "es", "uk", "hu" }
    for _, code in ipairs(langs) do
        local name = LANGUAGE_NAMES[code] or code:upper()
        table.insert(items, {
            text = (settings_lang == code and "[✓] " or "[  ] ") .. name,
            callback = function() changeLang(code) end
        })
    end
    
    local dialog_title = (self.loc and self.loc:t("menu_language")) or "Language Selection"
    self.ldlg = self:newMenu("ldlg", {
        title = dialog_title,
        item_table = items,
        is_borderless = true,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        on_close_callback = function()
            self.ldlg = nil
        end
    })
    UIManager:show(self.ldlg)
end

function M:resolveLanguage(code)
    local supported = {}
    if self.loc and self.loc.available_languages then
        for _, c in ipairs(self.loc.available_languages) do
            supported[c] = 1
        end
    else
        supported = { en=1, de=1, fr=1, ru=1, zh_CN=1, ja=1, tr=1, pt_br=1, es=1, uk=1, hu=1, nl=1, pl=1, id=1, ar=1, sr=1, sk=1, cs=1 }
    end
    
    if code == "auto" or not code then
        local gettext = require("gettext")
        local ko_lang = gettext.getLanguage and gettext.getLanguage()
        
        -- Fallback to G_reader_settings if gettext doesn't provide it
        if not ko_lang and G_reader_settings then
            ko_lang = G_reader_settings:readSetting("language")
        end
        
        if ko_lang then
            local lang = ko_lang:sub(1, 2):lower()
            if ko_lang:lower():find("zh_cn") or ko_lang:lower():find("zh-cn") then lang = "zh_CN"
            elseif ko_lang:lower():find("pt_br") or ko_lang:lower():find("pt-br") then lang = "pt_br" end
            if supported[lang] then return lang end
        end
        return "en"
    elseif code == "book" then
        if self.ui and self.ui.document then
            local props = self.ui.document:getProps()
            local book_lang = props.language
            if book_lang then
                local lang = book_lang:sub(1, 2):lower()
                local iso_lang = utils:languageFromIso639_2(book_lang)
                if iso_lang then lang = iso_lang
                elseif book_lang:lower():find("zh") then lang = "zh_CN"
                elseif book_lang:lower():find("pt") then lang = "pt_br"
                elseif book_lang:lower():find("ja") or book_lang:lower():find("jp") then lang = "ja" end
                if supported[lang] then return lang end
            end
        end
        return self:resolveLanguage("auto")
    end
    return code or "en"
end

function M:isRTL()
    local lang = self.ai_helper and self.ai_helper.current_language
    if not lang and self.ai_helper and self.ai_helper.settings then
        lang = self:resolveLanguage(self.ai_helper.settings.language)
    end
    return lang == "ar"
end

function M:isXRayUIActive()
    return self._menu_creating or self.xray_menu or self.char_menu or self.loc_menu or self.timeline_menu 
        or self.hf_menu or self.terms_menu or self.ldlg or self.active_related_menu or self.length_presets_menu
end

local xray_theme = require(plugin_path .. "xray_theme")

-- MenuItem is defined privately inside ui/widget/menu, not as a separate module.
-- We patch it lazily the first time an X-Ray menu is created, by extracting its
-- class from the first item in the menu's item_group via the Lua metatable.
local function _patchMenuItemClass(item_group)
    if not item_group or #item_group == 0 then return end
    local first_item = item_group[1]
    if not first_item then return end

    -- In KOReader's OOP, the class is at getmetatable(instance).__index
    local mt = getmetatable(first_item)
    local ItemClass = mt and mt.__index
    if not ItemClass or ItemClass._xray_focus_patched then return end

    ItemClass._xray_focus_patched = true

    local orig_paintTo = ItemClass.paintTo
    local orig_onFocus = ItemClass.onFocus
    local orig_onUnfocus = ItemClass.onUnfocus

    function ItemClass:onFocus()
        self._xray_focused = self.menu and self.menu._xray_highlight or false
        if orig_onFocus then orig_onFocus(self) end
        return true
    end

    function ItemClass:onUnfocus()
        self._xray_focused = false
        if orig_onUnfocus then orig_onUnfocus(self) end
        return true
    end

    function ItemClass:paintTo(bb, x, y)
        -- Draw full-width focus background before rendering item content
        if self._xray_focused and self.dimen then
            local bg = xray_theme.color_focus_bg or Blitbuffer.Color8(215)
            bb:paintRect(x, y, self.dimen.w, self.dimen.h, bg)
        end
        if orig_paintTo then
            orig_paintTo(self, bb, x, y)
        end
    end
end

local function _patchButtonDialog()
    local ok_btndlg, ButtonDialog = pcall(require, "ui/widget/buttondialog")
    if ok_btndlg and ButtonDialog and not ButtonDialog._xray_nontouch_patched then
        ButtonDialog._xray_nontouch_patched = true

        local orig_btndlg_init = ButtonDialog.init
        function ButtonDialog:init()
            if self._added_widgets then
                for _, w in ipairs(self._added_widgets) do
                    if w and w.not_focusable == nil then
                        w.not_focusable = true
                    end
                end
            end
            if orig_btndlg_init then
                orig_btndlg_init(self)
            end

            -- Ensure layout is always populated, even on non-DPad devices (where ButtonTable doesn't set self.layout)
            if (not self.layout or #self.layout == 0) and self.buttontable and self.buttontable.buttons_layout then
                self.layout = self.buttontable.buttons_layout
            end

            self.key_events = self.key_events or {}

            -- 1. Map Return, Enter, KP_Enter, Select, Space to Press so Enter activates focused button
            self.key_events.Press = self.key_events.Press or {}
            local enter_keys = { "Return", "KP_Enter", "Enter", "Select", "Space" }
            for _, k in ipairs(enter_keys) do
                table.insert(self.key_events.Press, { k })
            end

            -- 2. Map Escape, Back, q, Q to Close
            self.key_events.Close = self.key_events.Close or {}
            local close_keys = { "Escape", "Back", "q", "Q" }
            for _, k in ipairs(close_keys) do
                table.insert(self.key_events.Close, { k })
            end

            -- 3. Ensure arrow keys are always registered for navigation
            self.key_events.FocusUp = { { "Up" }, event = "FocusMove", args = {0, -1} }
            self.key_events.FocusDown = { { "Down" }, event = "FocusMove", args = {0, 1} }
            self.key_events.FocusLeft = { { "Left" }, event = "FocusMove", args = {-1, 0} }
            self.key_events.FocusRight = { { "Right" }, event = "FocusMove", args = {1, 0} }

            -- 4. Ingest device-specific groups if available
            local ok_dev, Device = pcall(require, "device")
            if ok_dev and Device and Device.input and Device.input.group then
                if Device.input.group.Enter then
                    table.insert(self.key_events.Press, { Device.input.group.Enter })
                end
                if Device.input.group.Select then
                    table.insert(self.key_events.Press, { Device.input.group.Select })
                end
                if Device.input.group.Back then
                    table.insert(self.key_events.Close, { Device.input.group.Back })
                end
            end

            -- 5. Trap events within the dialog so unhandled keys do not leak to background menus
            self.stop_events_propagation = true

            -- 6. Set initial default coordinates; immediately highlight ONLY on non-touch devices
            if self.layout and #self.layout > 0 and #self.layout[1] > 0 then
                local def_x, def_y = 1, 1
                local found_enter_default = false
                for y, row in ipairs(self.layout) do
                    for x, btn in ipairs(row) do
                        if btn and btn.is_enter_default then
                            def_x, def_y = x, y
                            found_enter_default = true
                            break
                        end
                    end
                    if found_enter_default then break end
                end
                if not found_enter_default then
                    -- Find first valid button in layout that can receive action
                    local found_btn = false
                    for y, row in ipairs(self.layout) do
                        for x, btn in ipairs(row) do
                            if btn and (btn.callback or btn.onTapSelectButton or btn.text) then
                                def_x, def_y = x, y
                                found_btn = true
                                break
                            end
                        end
                        if found_btn then break end
                    end
                end
                self.selected = { x = def_x, y = def_y }

                local is_touch = true
                local ok_dev_touch, DevTouch = pcall(require, "device")
                if ok_dev_touch and DevTouch then
                    if type(DevTouch.isTouchDevice) == "function" then
                        local ok2, res = pcall(DevTouch.isTouchDevice, DevTouch)
                        if ok2 and res ~= nil then is_touch = (res == true) end
                    elseif DevTouch.isTouchDevice ~= nil then
                        is_touch = (DevTouch.isTouchDevice == true)
                    end
                end

                if not is_touch then
                    local target_btn = self.layout[def_y] and self.layout[def_y][def_x]
                    if target_btn and target_btn.handleEvent then
                        local ok_ev, Event = pcall(require, "ui/event")
                        if ok_ev and Event then
                            target_btn:handleEvent(Event:new("Focus"))
                        end
                    end
                end
            end
        end

        local orig_btndlg_onPress = ButtonDialog.onPress
        function ButtonDialog:onPress()
            local item = (self.getFocusItem and self:getFocusItem())
            if not item or not (item.onTapSelectButton or item.callback) then
                if self.layout and self.selected and self.layout[self.selected.y] then
                    item = self.layout[self.selected.y][self.selected.x]
                end
            end
            if not item or not (item.onTapSelectButton or item.callback) then
                if self.layout then
                    for _, row in ipairs(self.layout) do
                        for _, btn in ipairs(row) do
                            if btn and (btn.onTapSelectButton or btn.callback) then
                                item = btn
                                break
                            end
                        end
                        if item then break end
                    end
                end
            end
            if item then
                if item.onTapSelectButton then
                    return item:onTapSelectButton()
                elseif item.callback then
                    item.callback()
                    return true
                end
            end
            if orig_btndlg_onPress then
                local ok, res = pcall(orig_btndlg_onPress, self)
                if ok then return res end
            end
            return true
        end
    end
end
_patchButtonDialog()

local function _attachMenuPaginationToLayout(menu)
    if not menu or not menu.layout then return end
    local orig_updateItems = menu.updateItems
    function menu:updateItems(select_number, no_paint)
        if orig_updateItems then
            orig_updateItems(self, select_number, no_paint)
        end
        if self.page_num and self.page_num > 1 and self.layout then
            local page_row = {}
            if self.page_info_first_chev and not self.page_info_first_chev.hidden then
                table.insert(page_row, self.page_info_first_chev)
            end
            if self.page_info_left_chev and not self.page_info_left_chev.hidden then
                table.insert(page_row, self.page_info_left_chev)
            end
            if self.page_info_text and not self.page_info_text.hidden then
                table.insert(page_row, self.page_info_text)
            end
            if self.page_info_right_chev and not self.page_info_right_chev.hidden then
                table.insert(page_row, self.page_info_right_chev)
            end
            if self.page_info_last_chev and not self.page_info_last_chev.hidden then
                table.insert(page_row, self.page_info_last_chev)
            end
            if #page_row > 0 then
                table.insert(self.layout, page_row)
            end
        end
    end

    -- Also append to initial layout if already populated
    if menu.page_num and menu.page_num > 1 and menu.layout then
        local page_row = {}
        if menu.page_info_first_chev and not menu.page_info_first_chev.hidden then
            table.insert(page_row, menu.page_info_first_chev)
        end
        if menu.page_info_left_chev and not menu.page_info_left_chev.hidden then
            table.insert(page_row, menu.page_info_left_chev)
        end
        if menu.page_info_text and not menu.page_info_text.hidden then
            table.insert(page_row, menu.page_info_text)
        end
        if menu.page_info_right_chev and not menu.page_info_right_chev.hidden then
            table.insert(page_row, menu.page_info_right_chev)
        end
        if menu.page_info_last_chev and not menu.page_info_last_chev.hidden then
            table.insert(page_row, menu.page_info_last_chev)
        end
        if #page_row > 0 then
            table.insert(menu.layout, page_row)
        end
    end

    -- Add key mappings for Page navigation
    menu.key_events = menu.key_events or {}
    menu.key_events.NextPage = menu.key_events.NextPage or {}
    table.insert(menu.key_events.NextPage, { "PageDown" })
    table.insert(menu.key_events.NextPage, { "]" })
    table.insert(menu.key_events.NextPage, { "RPgFwd" })
    table.insert(menu.key_events.NextPage, { "LPgFwd" })

    menu.key_events.PrevPage = menu.key_events.PrevPage or {}
    table.insert(menu.key_events.PrevPage, { "PageUp" })
    table.insert(menu.key_events.PrevPage, { "[" })
    table.insert(menu.key_events.PrevPage, { "RPgBack" })
    table.insert(menu.key_events.PrevPage, { "LPgBack" })

    local ok_dev, Device = pcall(require, "device")
    if ok_dev and Device and Device.input and Device.input.group then
        if Device.input.group.PgFwd then
            table.insert(menu.key_events.NextPage, { Device.input.group.PgFwd })
        end
        if Device.input.group.PgBack then
            table.insert(menu.key_events.PrevPage, { Device.input.group.PgBack })
        end
    end
end

function M:newMenu(var_name, args)
    self._menu_creating = true
    plugin_instance = self
    
    local orig_on_close = args.on_close_callback
    args.on_close_callback = function()
        if orig_on_close then
            orig_on_close()
        end
        if var_name then
            self[var_name] = nil
        end
    end
    
    args._xray_highlight = true
    local menu = Menu:new(args)
    menu._xray_highlight = true

    -- Ensure dynamic submenus with sub_item_table_func work in standalone Menu
    local orig_onMenuSelect = menu.onMenuSelect
    menu.onMenuSelect = function(this, item)
        if type(item.sub_item_table_func) == "function" then
            item.sub_item_table = item.sub_item_table_func()
        end
        if orig_onMenuSelect then
            return orig_onMenuSelect(this, item)
        end
        return true
    end

    -- Lazily patch the private MenuItem class via the live item_group
    _patchMenuItemClass(menu.item_group)
    -- Attach pagination buttons to FocusManager layout
    _attachMenuPaginationToLayout(menu)
    self._menu_creating = nil
    return menu
end

function M:applyLanguageLogic()
    local settings_lang = (self.ai_helper and self.ai_helper.settings) and self.ai_helper.settings.language or "auto"
    local resolved = self:resolveLanguage(settings_lang)
    
    self:log("XRayPlugin: Applying language logic. Settings: " .. tostring(settings_lang) .. ", Resolved: " .. tostring(resolved))
    
    if self.loc and self.loc.setLanguage then
        self.loc:setLanguage(resolved)
    end
    
    if self.ai_helper and (self.ai_helper.current_language ~= resolved or not self.ai_helper.prompts) then
        self.ai_helper.current_language = resolved
        self.ai_helper:loadLanguage()
    end
end

function M:checkBookLanguageMatch()
    local settings_lang = (self.ai_helper and self.ai_helper.settings) and self.ai_helper.settings.language or "auto"
    -- Only suggest if we are NOT in "Follow Book" mode already
    if settings_lang == "book" then return end
    
    if not self.ui or not self.ui.document then return end
    local props = self.ui.document:getProps()
    local book_lang = props.language
    if not book_lang or book_lang == "" then return end
    
    local lang = book_lang:sub(1, 2):lower()
    local iso_lang = utils:languageFromIso639_2(book_lang)
    if iso_lang then lang = iso_lang
    elseif book_lang:find("zh") then lang = "zh_CN"
    elseif book_lang:find("pt") then lang = "pt_br"
    elseif book_lang:find("ja") or book_lang:find("jp") then lang = "ja" end
    
    local LANGUAGE_NAMES = {
        en = "English",
        de = "Deutsch",
        fr = "Français",
        ru = "Русский",
        zh_CN = "简体中文",
        ja = "日本語",
        tr = "Türkçe",
        pt_br = "Português",
        es = "Español",
        uk = "Українська",
        hu = "Magyar",
        nl = "Nederlands",
        pl = "Polski",
        id = "Bahasa Indonesia",
        ar = "العربية",
        it = "Italiano",
        sr = "Српски",
        sk = "Slovenčina",
        cs = "Čeština",
    }
    
    local supported = {}
    if self.loc and self.loc.available_languages then
        for _, c in ipairs(self.loc.available_languages) do
            supported[c] = LANGUAGE_NAMES[c] or c:upper()
        end
    else
        for c, name in pairs(LANGUAGE_NAMES) do
            supported[c] = name
        end
    end
    
    if not supported[lang] then return end
    
    local current_lang = self.loc:getLanguage()
    if lang == current_lang then return end
    
    self.suggestion_dismissed = self.suggestion_dismissed or {}
    if self.suggestion_dismissed[self.ui.document.file] then return end
    
    -- Check if we should ignore this book (from cache)
    if not self.cache_manager then self.cache_manager = require(plugin_path .. "xray_cachemanager"):new() end
    local cache = self.book_data or self.cache_manager:loadCache(self.ui.document.file)
    if cache and cache.ignore_lang_mismatch then return end

    -- Show prompt
    local lang_name = supported[lang]
    local msg = self.loc:t("msg_suggest_lang", lang_name)
    
    local ButtonDialog = require("ui/widget/buttondialog")
    local mismatch_dialog
    mismatch_dialog = ButtonDialog:new{
        title = (self.loc:t("lang_mismatch_title") or "Language Mismatch") .. "\n\n" .. msg,
        text = msg,
        buttons = {
            {
                {
                    text = self.loc:t("yes") or "Yes",
                    is_enter_default = true,
                    callback = function()
                        if self.ai_helper then
                            self.ai_helper:saveSettings({ language = lang })
                            self:applyLanguageLogic()
                            UIManager:close(mismatch_dialog)
                            UIManager:show(InfoMessage:new{
                                text = self.loc:t("language_changed_reopen") or "Language changed.",
                                timeout = 3
                            })
                        end
                    end
                },
                {
                    text = self.loc:t("no") or "No",
                    callback = function()
                        self.suggestion_dismissed[self.ui.document.file] = true
                        UIManager:close(mismatch_dialog)
                    end
                }
            },
            {
                {
                    text = self.loc:t("dont_ask_again") or "Don't ask again",
                    callback = function()
                        local doc_file = self.ui and self.ui.document and self.ui.document.file
                        if not self.book_data then
                            self.book_data = (doc_file and self.cache_manager and self.cache_manager:loadCache(doc_file)) or {}
                        end
                        local current_cache = self.book_data
                        current_cache.ignore_lang_mismatch = true
                        if doc_file and self.cache_manager then
                            self.cache_manager:asyncSaveCache(doc_file, current_cache)
                        end
                        UIManager:close(mismatch_dialog)
                    end
                }
            }
        }
    }
    UIManager:show(mismatch_dialog)
end

function M:closeAllMenus()
    -- Mark as cancelled to stop background tasks
    self.is_cancelled = true
    
    if self.bg_scan_handle and self.bg_scan_handle.cancel then
        pcall(function() self.bg_scan_handle:cancel() end)
    end
    if self.active_mention_scan and self.active_mention_scan.cancel_handle then
        pcall(function() self.active_mention_scan.cancel_handle:cancel() end)
        self.active_mention_scan = nil
    end

    if self.clearHighlightOverlay then
        pcall(function() self:clearHighlightOverlay() end)
    end

    -- 1. Close all custom plugin modals instantly
    local function closeWidget(w)
        if w then pcall(function() UIManager:close(w) end) end
    end
    closeWidget(self.mentions_menu)
    closeWidget(self.char_menu)
    closeWidget(self.loc_menu)
    closeWidget(self.timeline_menu)
    closeWidget(self.hf_menu)
    closeWidget(self.xray_menu)
    closeWidget(self.terms_menu)
    closeWidget(self.active_details_dialog)
    closeWidget(self.return_banner)
    closeWidget(self.active_related_menu)

    self.mentions_menu = nil; self.char_menu = nil; self.loc_menu = nil
    self.timeline_menu = nil; self.hf_menu = nil; self.xray_menu = nil
    self.terms_menu = nil; self.active_details_dialog = nil; self.return_banner = nil
    self.active_related_menu = nil
    
    local function executeClear()
        -- 2. Dismiss native KOReader top menu stack
        if self.ui and self.ui.menu then
            pcall(function()
                if type(self.ui.menu.onCloseReaderMenu) == "function" then
                    self.ui.menu:onCloseReaderMenu()
                end
            end)
        end

        -- 3. Cleanup selection and highlights
        pcall(function()
            local Event = require("ui/event")
            local ok, DictQuickLookup = pcall(require, "ui/widget/dictquicklookup")
            if ok and DictQuickLookup and DictQuickLookup.window_list then
                for i = #DictQuickLookup.window_list, 1, -1 do
                    local window = DictQuickLookup.window_list[i]
                    if window and window.onClose then pcall(function() window:onClose() end) end
                end
            end
            if self.ui.highlight and self.ui.highlight.clear then
                pcall(function() self.ui.highlight:clear() end)
            end
            self.ui:handleEvent(Event:new("ClearSelection"))
        end)
    end
    
    -- Pass 1: Immediate
    executeClear()
    
    -- Pass 2: Staggered 100ms safety pass
    UIManager:scheduleIn(0.1, function()
        if self.destroyed then return end
        executeClear()
        -- Reset cancellation flag after all passes are done
        self.is_cancelled = false
    end)
end

function M:hasXRayData()
    if self.getMenuCounts then
        local counts = self:getMenuCounts()
        return counts.characters > 0
            or counts.timeline > 0
            or counts.locations > 0
            or counts.historical_figures > 0
            or counts.terms > 0
    end
    return (self.characters and #self.characters > 0)
        or (self.timeline and #self.timeline > 0)
        or (self.locations and #self.locations > 0)
        or (self.historical_figures and #self.historical_figures > 0)
        or (self.terms and #self.terms > 0)
end

function M:_promptNoDataFetch()
    local ButtonDialog = require("ui/widget/buttondialog")
    local dlg
    dlg = ButtonDialog:new{
        title = self.loc:t("no_data_prompt")
            or "No X-Ray data found for this book. Would you like to fetch it from AI now?",
        buttons = {{
            {
                text = self.loc:t("cancel") or "Cancel",
                callback = function() UIManager:close(dlg) end,
            },
            {
                text = self.loc:t("fetch_button") or "Fetch",
                is_enter_default = true,
                callback = function()
                    UIManager:close(dlg)
                    self:fetchFromAI()
                end,
            },
        }},
    }
    UIManager:show(dlg)
end

function M:showCharacters()
    self.characters = self.characters or {}

    if self.char_menu then
        UIManager:close(self.char_menu)
        self.char_menu = nil
    end

    local EntityListOverlay = require(plugin_path .. "xray_entity_list")
    self.char_menu = EntityListOverlay:new{
        plugin = self,
        mode = "characters",
        raw_items = self.characters,
    }
    UIManager:show(self.char_menu, "ui")

    UIManager:scheduleIn(0.3, function()
        if self.destroyed or not self.ui or not self.ui.document then return end
        if self.isAnthologyMode and self:isAnthologyMode() and self.pending_duplicate_review and self.pending_duplicate_review.story_id then
            local cs = self.getCurrentStory and self:getCurrentStory()
            if not cs or cs.story_id ~= self.pending_duplicate_review.story_id then
                self.pending_duplicate_review = nil
            end
        end
        if self.pending_duplicate_review and self.pending_duplicate_review.characters and #self.pending_duplicate_review.characters > 0 then
            local pairs = self:filterValidDuplicatePairs(self.characters, self.pending_duplicate_review.characters)
            self.pending_duplicate_review.characters = nil
            if #pairs > 0 then
                local ButtonDialog = require("ui/widget/buttondialog")
                local prompt_dlg
                prompt_dlg = ButtonDialog:new{
                    modal = true,
                    title = string.format(
                        self.loc:t("pending_duplicates_prompt") or
                        "AI found %d possible duplicate character(s) from the last fetch. Review now?",
                        #pairs
                    ),
                    buttons = {{
                        {
                            text = self.loc:t("later") or "Later",
                            callback = function()
                                UIManager:close(prompt_dlg)
                            end,
                        },
                        {
                            text = self.loc:t("review") or "Review",
                            is_enter_default = true,
                            callback = function()
                                UIManager:close(prompt_dlg)
                                self:log("XRayPlugin: User chose to review pending " .. tostring(#pairs) .. " duplicate(s) for characters")
                                self:walkDuplicatePairs(self.characters, "characters", pairs)
                            end,
                        },
                    }},
                }
                UIManager:show(prompt_dlg)
            end
        end
    end)
end

function M:findRelatedEntities(text, exclude_name, source_entity)
    if not text or text == "" then return {} end
    local related = {}
    local seen = {}
    if exclude_name then seen[exclude_name:lower()] = true end

    local target_story_id = nil
    if self.isAnthologyMode and self:isAnthologyMode() then
        if source_entity then
            target_story_id = source_entity.story_id or (self.resolveEntityStory and self:resolveEntityStory(source_entity))
        else
            local cur_st = self.getCurrentStory and self:getCurrentStory()
            target_story_id = cur_st and cur_st.story_id
        end
    end

    local lower_text = text:lower()

    -- Honorifics: fast-path blocklist for known titles.
    -- Tokens < 3 chars are already blocked by isTooGeneric's length check;
    -- 3-char titles (mr., mrs, sir, dr., etc.) are listed here since they can
    -- have plausible frequency ratios in densely character-focused descriptions.
    local honorifics = {
        ["mr"] = true, ["mr."] = true, ["mrs"] = true, ["mrs."] = true, ["ms"] = true, ["ms."] = true,
        ["dr"] = true, ["dr."] = true, ["sir"] = true, ["rev"] = true, ["rev."] = true, ["lt"] = true, ["lt."] = true,
        ["col"] = true, ["col."] = true, ["sgt"] = true, ["sgt."] = true, ["gen"] = true, ["gen."] = true,
        ["miss"] = true, ["lord"] = true, ["lady"] = true, ["dame"] = true, ["prof"] = true, ["prof."] = true,
        ["capt"] = true, ["capt."] = true, ["st"] = true, ["st."] = true, ["jr"] = true, ["jr."] = true,
        
        -- International
        ["m"] = true, ["m."] = true, ["mme"] = true, ["mme."] = true, ["mlle"] = true, ["mlle."] = true, ["mgr"] = true,
        ["herr"] = true, ["frau"] = true, ["hr"] = true, ["hr."] = true, ["fr"] = true, ["fr."] = true,
        ["sr"] = true, ["sr."] = true, ["sra"] = true, ["sra."] = true, ["don"] = true, ["dona"] = true, ["doña"] = true,
        ["bey"] = true, ["hanım"] = true,
        ["пан"] = true, ["пані"] = true, ["г-н"] = true, ["г-жа"] = true,
    }

    -- Frequency-ratio guard: if a candidate term appears 5× more often than the
    -- entity's full name in the text, it is too generic to be a useful identifier.
    -- This is language-agnostic — articles, stop words, and AI-hallucinated
    -- one-word aliases will all fail this test naturally.
    local function countInText(term)
        local escaped = term:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1")
        local pattern = escaped
        if #term < 4 then
            pattern = "%f[%w]" .. escaped .. "%f[%W]"
        end
        local _, n = lower_text:gsub(pattern, "")
        return n
    end
    local function isTooGeneric(term, entity_name)
        local term_l = term:lower()
        if #term < 2 or honorifics[term_l] then return true end
        local name_freq = math.max(1, countInText(entity_name:lower()))
        return countInText(term_l) > name_freq * 5
    end

    -- Check if a term appears in the text surrounded by non-word characters.
    -- Pads the text so names at the very start/end of a string also match.
    local function termFound(term)
        if not term or #term < 2 then return false end
        local escaped = term:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1")
        return (" " .. lower_text .. " "):find("[^%w]" .. escaped:lower() .. "[^%w]") ~= nil
    end

    local function scanList(list, type_name)
        if not list then return end
        for _, item in ipairs(list) do
            local pass_story = true
            if target_story_id then
                local it_st = item.story_id or (self.resolveEntityStory and self:resolveEntityStory(item))
                if it_st ~= target_story_id then pass_story = false end
            end
            local pass_vis = not self.isEntityVisibleAtCurrentPosition or self:isEntityVisibleAtCurrentPosition(item)
            local name = item.name
            if pass_story and pass_vis and name and not seen[name:lower()] then
                local found = false

                -- Strategy 1: Full name match
                if termFound(name) then
                    found = true
                end

                -- Strategy 2: Aliases (skip generic and honorific-only aliases)
                local unl_aliases = self.getUnlockedAliases and self:getUnlockedAliases(item) or item.aliases
                if not found and unl_aliases then
                    for _, alias in ipairs(unl_aliases) do
                        if type(alias) == "string"
                                  and not honorifics[alias:lower()]
                                  and not isTooGeneric(alias, name)
                                  and termFound(alias) then
                            found = true
                            break
                        end
                    end
                end

                if found then
                    seen[name:lower()] = true
                    table.insert(related, { item = item, type = type_name })
                end
            end
        end
    end

    scanList(self.characters, "character")
    scanList(self.locations, "location")
    scanList(self.historical_figures, "historical")
    scanList(self.terms, "term")

    return related
end

function M:showRelatedEntities(related, opts, source_entity)
    if self.active_details_dialog then
        local d = self.active_details_dialog
        self.active_details_dialog = nil
        pcall(function() UIManager:close(d) end)
    end

    if self.active_related_menu then
        local m = self.active_related_menu
        self.active_related_menu = nil
        pcall(function() UIManager:close(m) end)
    end

    local entity = source_entity or (opts and (opts.entity or opts.item))

    local EntityListOverlay = require(plugin_path .. "xray_entity_list")
    self.active_related_menu = EntityListOverlay:new{
        plugin = self,
        mode = "linked_entries",
        entity = entity,
        raw_items = related or {},
        opts = opts,
        on_close_callback = function()
            self.active_related_menu = nil
        end,
    }
    UIManager:show(self.active_related_menu, "ui")
end

function M:showCharacterDetails(character, opts)
    if shouldUseBottomPopup(self, opts) then
        showBottomPopup(self, character, opts)
        return
    end
    local metrics = self:calculatePopupFontMetrics(character)
    local fs = metrics.fs
    local fs_small = metrics.fs_small
    local border_window = (Size.border and Size.border.window) or 1
    local padding_button = (Size.padding and Size.padding.button) or 10
    local padding_default = (Size.padding and Size.padding.default) or 10
    local margin_default = (Size.margin and Size.margin.default) or 5

    local dialog_width = math.floor(math.min(Screen:getWidth(), Screen:getHeight()) * 0.9)
    local buttontable_width = dialog_width - 2 * border_window - 2 * padding_button
    local title_group_width = buttontable_width - 2 * (padding_default + margin_default)

    local align = self:isRTL() and "right" or "left"
    local vg_components = { align = align }

    -- 1. Bold Name (no label)
    table.insert(vg_components, TextBoxWidget:new{
        text = character.name or "???",
        face = Font:getFace("cfont", fs),
        width = title_group_width,
        bold = true,
        alignment = align,
    })

    -- 2. Aliases (with label, if present)
    local meaningful_aliases = {}
    local char_aliases = self.getUnlockedAliases and self:getUnlockedAliases(character) or character.aliases
    if char_aliases and type(char_aliases) == "table" and #char_aliases > 0 then
        local name_lower = (character.name or ""):lower()
        for _, alias in ipairs(char_aliases) do
            local al_lower = tostring(alias):lower()
            if #al_lower > 1 and not name_lower:find(al_lower, 1, true) then
                table.insert(meaningful_aliases, alias)
            end
        end
    end
    if #meaningful_aliases > 0 then
        table.insert(vg_components, VerticalSpan:new{ width = math.max(6, math.floor(fs * 0.3)) })
        table.insert(vg_components, TextBoxWidget:new{
            text = (self.loc:t("label_aliases") or "ALIASES") .. ": " .. table.concat(meaningful_aliases, ", "),
            face = Font:getFace("cfont", fs_small),
            width = title_group_width,
            alignment = align,
        })
    end

    -- 3. Combined attributes line (smaller, no label)
    local resolved_role, resolved_status, resolved_desc = self:resolveEntityState(character)
    resolved_desc = resolved_desc or self:resolveDescriptionForPage(character)
    resolved_desc = SeriesManager.reorderSeriesDescription(resolved_desc)

    local attrs = {}
    local seen_attrs = {}
    local function addAttr(val)
        if val and val ~= "" and val ~= "---" and not seen_attrs[val:lower()] then
            seen_attrs[val:lower()] = true
            table.insert(attrs, val)
        end
    end
    addAttr(resolved_role or character.role)
    local active_status = resolved_status or character.status
    if active_status and active_status ~= "alive" then
        addAttr(active_status)
    end
    addAttr(character.occupation)
    addAttr(character.gender)

    if #attrs > 0 then
        table.insert(vg_components, VerticalSpan:new{ width = math.max(6, math.floor(fs * 0.3)) })
        table.insert(vg_components, TextBoxWidget:new{
            text = table.concat(attrs, " | "),
            face = Font:getFace("cfont", fs_small),
            width = title_group_width,
            alignment = align,
        })
    end

    -- 4. AI Reasoning (if present)
    if character.ai_reasoning then
        table.insert(vg_components, VerticalSpan:new{ width = math.max(6, math.floor(fs * 0.3)) })
        table.insert(vg_components, TextBoxWidget:new{
            text = "[" .. (self.loc:t("label_reasoning") or "AI REASONING") .. "]",
            face = Font:getFace("cfont", fs),
            width = title_group_width,
            bold = true,
            alignment = align,
        })
        table.insert(vg_components, VerticalSpan:new{ width = math.max(4, math.floor(fs * 0.2)) })
        table.insert(vg_components, TextBoxWidget:new{
            text = character.ai_reasoning,
            face = Font:getFace("cfont", fs),
            width = title_group_width,
            alignment = align,
        })
    end

    -- 5. Description (no label)
    local display_desc = resolved_desc
    local is_truncated = false
    if resolved_desc and resolved_desc ~= "" and resolved_desc ~= "---" then
        display_desc, is_truncated = _getTruncatedText(resolved_desc, 450, 500)
        if is_truncated then
            local last_space = display_desc:match("^.*()%s")
            if last_space then
                display_desc = display_desc:sub(1, last_space - 1)
            end
            display_desc = display_desc .. " ..."
        end
        table.insert(vg_components, VerticalSpan:new{ width = math.max(6, math.floor(fs * 0.3)) })
        table.insert(vg_components, TextBoxWidget:new{
            text = display_desc,
            face = Font:getFace("cfont", fs),
            width = title_group_width,
            alignment = align,
        })
    end

    local vg = VerticalGroup:new(vg_components)
    vg.not_focusable = true

    local linked_enabled = self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.linked_entries_enabled ~= false
    local related = linked_enabled and self:findRelatedEntities(resolved_desc or "", character.name, character) or {}
    local mentions_enabled = self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.mentions_enabled ~= false
    
    local evolution_enabled = self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.evolution_enabled ~= false
    local has_evo = evolution_enabled and (((self.hasEntityEvolution and self:hasEntityEvolution(character)))
                    or (character.states and #character.states > 1) or (character.history and #character.history > 1))

    local action_btns = {}
    if has_evo and self.showPastEvolution then
        table.insert(action_btns, {
            text = self.loc:t("past_evolution") or "Story Arc",
            callback = function()
                if self.active_details_dialog then
                    UIManager:close(self.active_details_dialog)
                    self.active_details_dialog = nil
                end
                UIManager:nextTick(function()
                    self:showPastEvolution(character)
                end)
            end,
        })
    end
    if #related > 0 then
        table.insert(action_btns, {
            text = self.loc:t("linked_entries") or "Linked Entries",
            callback = function()
                if self.active_details_dialog then UIManager:close(self.active_details_dialog); self.active_details_dialog = nil end
                self:showRelatedEntities(related, opts, character)
            end,
        })
    end
    if mentions_enabled then
        table.insert(action_btns, {
            text = self.loc:t("find_mentions") or "Find Mentions",
            callback = function()
                if self.active_details_dialog then UIManager:close(self.active_details_dialog); self.active_details_dialog = nil end
                self:showMentionsForEntity(character)
            end,
        })
    end
    if opts and opts.restore_menu_cb then
        table.insert(action_btns, {
            text = self.loc:t("highlight_menu_btn") or "Highlight Menu",
            callback = function()
                if self.active_details_dialog then UIManager:close(self.active_details_dialog); self.active_details_dialog = nil end
                opts.restore_menu_cb()
            end,
        })
    end

    local close_btn = {
        text = self.loc:t("close") or "Close",
        is_enter_default = true,
        callback = function()
            if self.active_details_dialog then UIManager:close(self.active_details_dialog) end
            self.active_details_dialog = nil
        end,
    }

    local read_more_btn = nil
    if is_truncated then
        read_more_btn = {
            text = self.loc:t("read_more") or "Read More",
            keep_menu_open = true,
            callback = function()
                local TextViewer = require("ui/widget/textviewer")
                local full_text = character.name .. "\n"
                if #attrs > 0 then
                    full_text = full_text .. table.concat(attrs, " | ") .. "\n"
                end
                if #meaningful_aliases > 0 then
                    full_text = full_text .. (self.loc:t("label_aliases") or "Aliases") .. ": " .. table.concat(meaningful_aliases, ", ") .. "\n"
                end
                full_text = full_text .. "\n" .. resolved_desc
                if character.ai_reasoning then
                    full_text = full_text .. "\n\n[" .. (self.loc:t("label_reasoning") or "AI Reasoning") .. "]\n" .. character.ai_reasoning
                end
                local viewer = TextViewer:new{
                    modal = true,
                    title = character.name,
                    text = full_text,
                }
                UIManager:show(viewer)
            end,
        }
    end

    local buttons = formatDialogButtons(action_btns, close_btn, read_more_btn)

    self.active_details_dialog = ButtonDialog:new{
        modal = true,
        _added_widgets = { vg },
        buttons = buttons,
    }
    UIManager:show(self.active_details_dialog)
end

function M:showLocationDetails(loc_item, opts)
    if shouldUseBottomPopup(self, opts) then
        showBottomPopup(self, loc_item, opts)
        return
    end
    local metrics = self:calculatePopupFontMetrics(loc_item)
    local fs = metrics.fs
    local fs_small = metrics.fs_small
    local border_window = (Size.border and Size.border.window) or 1
    local padding_button = (Size.padding and Size.padding.button) or 10
    local padding_default = (Size.padding and Size.padding.default) or 10
    local margin_default = (Size.margin and Size.margin.default) or 5

    local dialog_width = math.floor(math.min(Screen:getWidth(), Screen:getHeight()) * 0.9)
    local buttontable_width = dialog_width - 2 * border_window - 2 * padding_button
    local title_group_width = buttontable_width - 2 * (padding_default + margin_default)

    local align = self:isRTL() and "right" or "left"
    local vg_components = { align = align }

    -- 1. Bold Name (no label)
    table.insert(vg_components, TextBoxWidget:new{
        text = loc_item.name or "???",
        face = Font:getFace("cfont", fs),
        width = title_group_width,
        bold = true,
        alignment = align,
    })

    -- 2. Description (no label)
    local desc = self:resolveDescriptionForPage(loc_item)
    if not desc or desc == "" or desc == "---" then
        local first_hist = loc_item.history and loc_item.history[1]
        desc = (first_hist and first_hist.description) or loc_item.description or ""
    end
    local display_desc = desc
    local is_truncated = false
    if desc and desc ~= "" then
        display_desc, is_truncated = _getTruncatedText(desc, 450, 500)
        if is_truncated then
            local last_space = display_desc:match("^.*()%s")
            if last_space then
                display_desc = display_desc:sub(1, last_space - 1)
            end
            display_desc = display_desc .. " ..."
        end
        table.insert(vg_components, VerticalSpan:new{ width = math.max(6, math.floor(fs * 0.3)) })
        table.insert(vg_components, TextBoxWidget:new{
            text = display_desc,
            face = Font:getFace("cfont", fs),
            width = title_group_width,
            alignment = align,
        })
    end

    local vg = VerticalGroup:new(vg_components)
    vg.not_focusable = true

    local linked_enabled = self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.linked_entries_enabled ~= false
    local related = linked_enabled and self:findRelatedEntities(desc, loc_item.name, loc_item) or {}
    local mentions_enabled = self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.mentions_enabled ~= false
    
    local evolution_enabled = self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.evolution_enabled ~= false
    local has_evo = evolution_enabled and (((self.hasEntityEvolution and self:hasEntityEvolution(loc_item)))
                    or (loc_item.states and #loc_item.states > 1) or (loc_item.history and #loc_item.history > 1))

    local action_btns = {}
    if has_evo and self.showPastEvolution then
        table.insert(action_btns, {
            text = self.loc:t("past_evolution") or "Story Arc",
            callback = function()
                if self.active_details_dialog then
                    UIManager:close(self.active_details_dialog)
                    self.active_details_dialog = nil
                end
                UIManager:nextTick(function()
                    self:showPastEvolution(loc_item)
                end)
            end,
        })
    end
    if #related > 0 then
        table.insert(action_btns, {
            text = self.loc:t("linked_entries") or "Linked Entries",
            callback = function()
                if self.active_details_dialog then UIManager:close(self.active_details_dialog); self.active_details_dialog = nil end
                self:showRelatedEntities(related, opts, loc_item)
            end,
        })
    end
    if mentions_enabled then
        table.insert(action_btns, {
            text = self.loc:t("find_mentions") or "Find Mentions",
            callback = function()
                if self.active_details_dialog then UIManager:close(self.active_details_dialog); self.active_details_dialog = nil end
                self:showMentionsForEntity(loc_item)
            end,
        })
    end
    if opts and opts.restore_menu_cb then
        table.insert(action_btns, {
            text = self.loc:t("highlight_menu_btn") or "Highlight Menu",
            callback = function()
                if self.active_details_dialog then UIManager:close(self.active_details_dialog); self.active_details_dialog = nil end
                opts.restore_menu_cb()
            end,
        })
    end

    local close_btn = {
        text = self.loc:t("close") or "Close",
        is_enter_default = true,
        callback = function()
            if self.active_details_dialog then UIManager:close(self.active_details_dialog) end
            self.active_details_dialog = nil
        end,
    }

    local read_more_btn = nil
    if is_truncated then
        read_more_btn = {
            text = self.loc:t("read_more") or "Read More",
            keep_menu_open = true,
            callback = function()
                local TextViewer = require("ui/widget/textviewer")
                local full_text = loc_item.name .. "\n\n" .. desc
                local viewer = TextViewer:new{
                    modal = true,
                    title = loc_item.name,
                    text = full_text,
                }
                UIManager:show(viewer)
            end,
        }
    end

    local buttons = formatDialogButtons(action_btns, close_btn, read_more_btn)

    self.active_details_dialog = ButtonDialog:new{
        modal = true,
        _added_widgets = { vg },
        buttons = buttons,
    }
    UIManager:show(self.active_details_dialog)
end

function M:showTermDetails(term, opts)
    if shouldUseBottomPopup(self, opts) then
        showBottomPopup(self, term, opts)
        return
    end
    local metrics = self:calculatePopupFontMetrics(term)
    local fs = metrics.fs
    local fs_small = metrics.fs_small
    local border_window = (Size.border and Size.border.window) or 1
    local padding_button = (Size.padding and Size.padding.button) or 10
    local padding_default = (Size.padding and Size.padding.default) or 10
    local margin_default = (Size.margin and Size.margin.default) or 5

    local dialog_width = math.floor(math.min(Screen:getWidth(), Screen:getHeight()) * 0.9)
    local buttontable_width = dialog_width - 2 * border_window - 2 * padding_button
    local title_group_width = buttontable_width - 2 * (padding_default + margin_default)

    local align = self:isRTL() and "right" or "left"
    local vg_components = { align = align }

    -- 1. Bold Name (no label)
    table.insert(vg_components, TextBoxWidget:new{
        text = term.name or "???",
        face = Font:getFace("cfont", fs),
        width = title_group_width,
        bold = true,
        alignment = align,
    })

    -- 2. Aliases (with label, if present)
    local meaningful_aliases = {}
    local term_aliases = self.getUnlockedAliases and self:getUnlockedAliases(term) or term.aliases
    if term_aliases and type(term_aliases) == "table" and #term_aliases > 0 then
        local name_lower = (term.name or ""):lower()
        for _, alias in ipairs(term_aliases) do
            local al_lower = tostring(alias):lower()
            if #al_lower > 1 and not name_lower:find(al_lower, 1, true) then
                table.insert(meaningful_aliases, alias)
            end
        end
    end
    if #meaningful_aliases > 0 then
        table.insert(vg_components, VerticalSpan:new{ width = math.max(6, math.floor(fs * 0.3)) })
        table.insert(vg_components, TextBoxWidget:new{
            text = (self.loc:t("label_aliases") or "ALIASES") .. ": " .. table.concat(meaningful_aliases, ", "),
            face = Font:getFace("cfont", fs_small),
            width = title_group_width,
            alignment = align,
        })
    end

    -- 3. Combined attributes
    local attrs = {}
    if term.expanded and term.expanded ~= "" and term.expanded ~= term.name then
        table.insert(attrs, term.expanded)
    end
    if term.category and term.category ~= "" then
        table.insert(attrs, term.category)
    end
    if #attrs > 0 then
        table.insert(vg_components, VerticalSpan:new{ width = math.max(6, math.floor(fs * 0.3)) })
        table.insert(vg_components, TextBoxWidget:new{
            text = table.concat(attrs, " | "),
            face = Font:getFace("cfont", fs_small),
            width = title_group_width,
            alignment = align,
        })
    end

    -- 4. Definition (no label)
    local resolved_definition = self:resolveDescriptionForPage(term)
    if not resolved_definition or resolved_definition == "---" then
        resolved_definition = term.definition
    end
    local display_definition = resolved_definition
    local is_truncated = false
    if resolved_definition and resolved_definition ~= "" and resolved_definition ~= "---" then
        display_definition, is_truncated = _getTruncatedText(resolved_definition, 450, 500)
        if is_truncated then
            local last_space = display_definition:match("^.*()%s")
            if last_space then
                display_definition = display_definition:sub(1, last_space - 1)
            end
            display_definition = display_definition .. " ..."
        end
        table.insert(vg_components, VerticalSpan:new{ width = math.max(6, math.floor(fs * 0.3)) })
        table.insert(vg_components, TextBoxWidget:new{
            text = display_definition,
            face = Font:getFace("cfont", fs),
            width = title_group_width,
            alignment = align,
        })
    end

    -- 5. Low confidence warning
    if opts and opts.low_confidence then
        local warning = self.loc:t("low_conf_match", term.name)
            or string.format("Partial match — showing '%s' for your query. Tap below to fetch the exact term.", term.name)
        table.insert(vg_components, VerticalSpan:new{ width = math.max(6, math.floor(fs * 0.3)) })
        table.insert(vg_components, TextBoxWidget:new{
            text = warning,
            face = Font:getFace("cfont", fs),
            width = title_group_width,
            alignment = align,
        })
    end

    local vg = VerticalGroup:new(vg_components)
    vg.not_focusable = true

    local linked_enabled = self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.linked_entries_enabled ~= false
    local related = linked_enabled and self:findRelatedEntities(term.definition or "", term.name, term) or {}
    local mentions_enabled = self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.mentions_enabled ~= false

    local function get_relookup_row()
        local safe_text = _getTruncatedText(opts.original_text, 30)
        return {
            {
                text = self.loc:t("relookup_button", safe_text)
                    or ("Re-lookup '" .. safe_text .. "'"),
                callback = function()
                    if self.active_details_dialog then UIManager:close(self.active_details_dialog); self.active_details_dialog = nil end
                    self:fetchSingleWord(opts.original_text, opts.pos0, opts.pos1)
                end,
            }
        }
    end

    local evolution_enabled = self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.evolution_enabled ~= false
    local has_evo = evolution_enabled and (((self.hasEntityEvolution and self:hasEntityEvolution(term)))
                    or (term.states and #term.states > 1) or (term.history and #term.history > 1))

    local action_btns = {}
    if has_evo and self.showPastEvolution then
        table.insert(action_btns, {
            text = self.loc:t("past_evolution") or "Story Arc",
            callback = function()
                if self.active_details_dialog then
                    UIManager:close(self.active_details_dialog)
                    self.active_details_dialog = nil
                end
                UIManager:nextTick(function()
                    self:showPastEvolution(term)
                end)
            end,
        })
    end
    if #related > 0 then
        table.insert(action_btns, {
            text = self.loc:t("linked_entries") or "Linked Entries",
            callback = function()
                if self.active_details_dialog then UIManager:close(self.active_details_dialog); self.active_details_dialog = nil end
                self:showRelatedEntities(related, opts, term)
            end,
        })
    end
    if mentions_enabled then
        table.insert(action_btns, {
            text = self.loc:t("find_mentions") or "Find Mentions",
            callback = function()
                if self.active_details_dialog then UIManager:close(self.active_details_dialog); self.active_details_dialog = nil end
                self:showMentionsForEntity(term)
            end,
        })
    end
    if opts and opts.restore_menu_cb then
        table.insert(action_btns, {
            text = self.loc:t("highlight_menu_btn") or "Highlight Menu",
            callback = function()
                if self.active_details_dialog then UIManager:close(self.active_details_dialog); self.active_details_dialog = nil end
                opts.restore_menu_cb()
            end,
        })
    end

    local close_btn = {
        text = self.loc:t("close") or "Close",
        is_enter_default = true,
        callback = function()
            if self.active_details_dialog then UIManager:close(self.active_details_dialog) end
            self.active_details_dialog = nil
        end,
    }

    local read_more_btn = nil
    if is_truncated then
        read_more_btn = {
            text = self.loc:t("read_more") or "Read More",
            keep_menu_open = true,
            callback = function()
                local TextViewer = require("ui/widget/textviewer")
                local full_text = term.name .. "\n"
                if #attrs > 0 then
                    full_text = full_text .. table.concat(attrs, " | ") .. "\n"
                end
                if #meaningful_aliases > 0 then
                    full_text = full_text .. (self.loc:t("label_aliases") or "Aliases") .. ": " .. table.concat(meaningful_aliases, ", ") .. "\n"
                end
                full_text = full_text .. "\n" .. resolved_definition
                local viewer = TextViewer:new{
                    modal = true,
                    title = term.name,
                    text = full_text,
                }
                UIManager:show(viewer)
            end
        }
    end

    local buttons = formatDialogButtons(action_btns, close_btn, read_more_btn)
    if opts and opts.low_confidence then
        table.insert(buttons, 1, get_relookup_row())
    end

    self.active_details_dialog = ButtonDialog:new{
        modal = true,
        _added_widgets = { vg },
        buttons = buttons,
    }
    UIManager:show(self.active_details_dialog)
end

function M:showTerms()
    self.terms = self.terms or {}

    if self.terms_menu then
        UIManager:close(self.terms_menu)
        self.terms_menu = nil
    end

    local EntityListOverlay = require(plugin_path .. "xray_entity_list")
    self.terms_menu = EntityListOverlay:new{
        plugin = self,
        mode = "terms",
        raw_items = self.terms,
    }
    UIManager:show(self.terms_menu, "ui")
end

function M:findTermByName(word)
    if not word or not self.terms then return nil end
    local query = utils:utf8Lower(word)
    for _, term in ipairs(self.terms) do
        if utils:utf8Lower(term.name or "") == query then
            return term
        end
        if term.aliases and type(term.aliases) == "table" then
            for _, alias in ipairs(term.aliases) do
                if utils:utf8Lower(tostring(alias)) == query then
                    return term
                end
            end
        end
    end
    return nil
end

function M:showTermSearch()
    if not self.terms or #self.terms == 0 then UIManager:show(InfoMessage:new{ text = self.loc:t("no_terms_data"), timeout = 3 }); return end
    local InputDialog = require("ui/widget/inputdialog")
    local input_dialog
    input_dialog = InputDialog:new{ 
        title = self.loc:t("search_term") or "Search Terms", 
        input = "", input_hint = self.loc:t("search_hint"), 
        buttons = {
            {{ text = self.loc:t("cancel"), callback = function() UIManager:close(input_dialog) end }, 
             { text = self.loc:t("search_button") or "Search", is_enter_default = true, 
               callback = function() 
                   local search_text = input_dialog:getInputText()
                   UIManager:close(input_dialog)
                   if search_text and #search_text > 0 then 
                       local found = self:findTermByName(search_text)
                        if found then self:showTermDetails(found, { source = "menu" }) 
                       else UIManager:show(InfoMessage:new{ text = self.loc:t("term_not_found", search_text) or "Term not found.", timeout = 3 }) end 
                   end 
               end 
             }}
        } 
    }
    UIManager:show(input_dialog); input_dialog:onShowKeyboard()
end

function M:showBookTypeSettings()
    local desc_str = self.loc:t("book_mode_desc") or "Select the type for this book:"
    if self:isAnthologyMode() then
        local ChapterAnalyzer = require(plugin_path .. "xray_chapteranalyzer")
        local ca = self.chapter_analyzer or ChapterAnalyzer:new{ plugin = self }
        local sm = ca:getStoryMap(self.ui)
        local scnt = sm and sm.stories and #sm.stories or 0
        desc_str = desc_str .. "\n\n" .. string.format(self.loc:t("anthology_detected_status") or "Currently active: Anthology Mode (%d stories detected)", scnt)
    end

    XRaySettingsCard.show(self, {
        title = self.loc:t("menu_book_mode") or "Book Type",
        description = desc_str,
        options = {
            { text = self.loc:t("book_type_auto") or "Auto-Detect", value = "auto" },
            { text = self.loc:t("book_type_fiction") or "Fiction", value = "fiction" },
            { text = self.loc:t("book_type_nonfiction") or "Non-Fiction", value = "non_fiction" },
            { text = self.loc:t("book_type_anthology") or "Anthology/Short Stories", value = "anthology" },
            { text = self.loc:t("book_type_redetect") or "Re-detect Anthology Structure", value = "redetect" },
        },
        get_current_func = function()
            local current = "auto"
            if not self.cache_manager then self.cache_manager = require(plugin_path .. "xray_cachemanager"):new() end
            local cache = self.book_data or self.cache_manager:loadCache(self.ui.document.file)
            if cache and cache.book_mode_override then
                current = cache.book_mode_override
            else
                current = self.ai_helper.settings.default_book_mode or "auto"
            end
            return current
        end,
        save_func = function(mode)
            local doc_file = self.ui and self.ui.document and self.ui.document.file
            if not self.cache_manager then self.cache_manager = require(plugin_path .. "xray_cachemanager"):new() end
            if not self.book_data then
                self.book_data = (doc_file and self.cache_manager:loadCache(doc_file)) or {}
            end
            local cache = self.book_data
            if mode == "redetect" then
                cache.book_mode_override = "auto"
                cache.anthology_detected = nil
                cache.anthology_type = nil
                self.book_type = nil
                if self.ensureAnthologyDecision then
                    self:ensureAnthologyDecision(function()
                        UIManager:setDirty(nil, "ui")
                    end)
                end
                return
            end

            cache.book_mode_override = mode
            if mode == "anthology" then
                cache.anthology_detected = true
                cache.book_type = "anthology"
            elseif mode == "fiction" or mode == "non_fiction" then
                cache.anthology_detected = false
                cache.book_type = mode
            elseif mode == "auto" then
                cache.anthology_detected = nil
                cache.book_type = nil
            end

            if doc_file and self.cache_manager then
                self.cache_manager:asyncSaveCache(doc_file, cache)
            end
            self.book_type = (mode == "auto") and nil or mode
            if self:isAnthologyMode() and self.retagEntitiesByStory then
                self:retagEntitiesByStory()
            end
            UIManager:setDirty(nil, "ui")
        end,
        about_text = self.loc:t("book_type_about") or "The Book Type determines which AI extraction strategy is used.\n\n[B]• Fiction:[/B] Focuses on characters, timeline, and world-building terms (factions, spells, lore, etc.).\n[B]• Non-Fiction:[/B] Focuses on technical terms, concepts, and historical figures.\n[B]• Anthology/Short Stories:[/B] Scopes AI extraction, entity lists, and duplicate merging to each individual story based on the Table of Contents.\n\n[B]Auto-Detect[/B] will let the AI decide after the [B]first[/B] fetch.\n\n[B]Note:[/B] This setting is saved [B]per book[/B]. A custom choice overrides default auto-detection or global settings.",
    })
end

function M:showAnthologyTocDepthSettings()
    XRaySettingsCard.show(self, {
        title = self.loc:t("menu_story_toc_depth") or "Anthology Story ToC Level",
        description = self.loc:t("story_toc_depth_desc") or "Select which Table of Contents level represents individual stories:",
        options = {
            { text = self.loc:t("story_toc_depth_auto") or "Auto-Detect (Recommended)", value = "auto" },
            { text = self.loc:t("story_toc_depth_1") or "Level 1 (Top-Level Entries)", value = 1 },
            { text = self.loc:t("story_toc_depth_2") or "Level 2 (Under Parts / Volumes)", value = 2 },
            { text = self.loc:t("story_toc_depth_3") or "Level 3", value = 3 },
        },
        get_current_func = function()
            local current = "auto"
            if not self.cache_manager then self.cache_manager = require(plugin_path .. "xray_cachemanager"):new() end
            local cache = self.book_data or self.cache_manager:loadCache(self.ui.document.file)
            if cache and cache.story_toc_depth then
                current = cache.story_toc_depth
            end
            return current
        end,
        save_func = function(depth)
            local doc_file = self.ui and self.ui.document and self.ui.document.file
            if not self.cache_manager then self.cache_manager = require(plugin_path .. "xray_cachemanager"):new() end
            if not self.book_data then
                self.book_data = (doc_file and self.cache_manager:loadCache(doc_file)) or {}
            end
            local cache = self.book_data
            cache.story_toc_depth = depth
            if doc_file and self.cache_manager then
                self.cache_manager:asyncSaveCache(doc_file, cache)
            end
            UIManager:setDirty(nil, "ui")
        end,
        about_text = "Controls which level of the Table of Contents defines individual story boundaries in Anthology mode.\n\n[B]• Auto-Detect (Recommended):[/B] Automatically detects whether top-level entries are stories or structural wrapper parts/volumes.\n[B]• Level 1:[/B] Top-level ToC entries are each treated as a story.\n[B]• Level 2:[/B] Entries nested under top-level parts/volumes are treated as stories.\n[B]• Level 3:[/B] For deeply nested collections.",
    })
end

function M:showMentionsSettings()
    local enabled_text = self.loc:t("mentions_enabled") or "Enabled"
    local disabled_text = self.loc:t("mentions_disabled") or "Disabled"
    XRaySettingsCard.show(self, {
        title = self.loc:t("mentions_setting_title") or "Mentions Settings",
        description = self.loc:t("mentions_preference_desc") or "Select your preference for character and location mentions:",
        options = {
            { text = enabled_text, value = true },
            { text = disabled_text, value = false },
        },
        get_current_func = function()
            return self.ai_helper.settings.mentions_enabled ~= false
        end,
        save_func = function(val)
            self.ai_helper:saveSettings({ mentions_enabled = val })
            UIManager:setDirty(nil, "ui")
        end,
        about_text = self.loc:t("mentions_setting_desc") or "Mentions scanning allows you to find every occurrence of a character or location in the book. This happens [B]automatically[/B] in the background to ensure the reader stays responsive.\n\nDisabling this will stop all background scanning and hide the [B]Find Mentions[/B] button.",
    })
end

function M:showAutoDupeCheckSettings()
    local enabled_text = self.loc:t("auto_dupe_check_enabled") or "Enabled"
    local disabled_text = self.loc:t("auto_dupe_check_disabled") or "Disabled"
    XRaySettingsCard.show(self, {
        title = self.loc:t("auto_dupe_check_setting_title") or "Duplicate Check",
        description = self.loc:t("auto_dupe_check_preference_desc") or "Select your preference for automatic AI duplicate detection:",
        options = {
            { text = enabled_text, value = true },
            { text = disabled_text, value = false },
        },
        get_current_func = function()
            return self.ai_helper.settings.auto_dupe_check_enabled ~= false
        end,
        save_func = function(val)
            self.ai_helper:saveSettings({ auto_dupe_check_enabled = val })
            UIManager:setDirty(nil, "ui")
        end,
        about_text = self.loc:t("auto_dupe_check_setting_desc") or "When enabled, X-Ray automatically asks the AI to check for duplicate characters and locations after every data fetch. If duplicates are detected, you will be prompted to review and merge them.\n\nDisabling this will stop all background duplicate scanning. You can still merge duplicates manually via the Characters or Locations menu.\n\n[B]Note:[/B] each check uses [B]one[/B] AI API call. Users on free-tier or quota-limited plans may prefer to disable this.",
    })
end

function M:showLinkedEntriesSettings()
    local enabled_text = self.loc:t("linked_entries_enabled") or "Enabled"
    local disabled_text = self.loc:t("linked_entries_disabled") or "Disabled"
    XRaySettingsCard.show(self, {
        title = self.loc:t("menu_linked_entries_settings") or "Linked Entries Settings",
        options = {
            { text = enabled_text, value = true },
            { text = disabled_text, value = false },
        },
        get_current_func = function()
            return self.ai_helper.settings.linked_entries_enabled ~= false
        end,
        save_func = function(val)
            self.ai_helper:saveSettings({ linked_entries_enabled = val })
            UIManager:setDirty(nil, "ui")
        end,
        about_text = self.loc:t("linked_entries_setting_desc") or "Linked Entries automatically connects characters, locations, and historical figures when they are mentioned in each other's descriptions.\n\nDisabling this will hide the [B]Linked Entries[/B] button from detail dialogs.",
    })
end

function M:showEvolutionSettings()
    local enabled_text = (self.loc and self.loc:t("evolution_enabled")) or "Enabled"
    local disabled_text = (self.loc and self.loc:t("evolution_disabled")) or "Disabled"
    XRaySettingsCard.show(self, {
        title = (self.loc and self.loc:t("menu_evolution_settings")) or "Story Arc Settings",
        options = {
            { text = enabled_text, value = true },
            { text = disabled_text, value = false },
        },
        get_current_func = function()
            return (self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.evolution_enabled ~= false)
        end,
        save_func = function(val)
            if self.ai_helper and self.ai_helper.saveSettings then
                self.ai_helper:saveSettings({ evolution_enabled = val })
            elseif self.ai_helper and self.ai_helper.settings then
                self.ai_helper.settings.evolution_enabled = val
            end
            UIManager:setDirty(nil, "ui")
        end,
        about_text = (self.loc and self.loc:t("evolution_setting_desc")) or "Story Arc tracks how characters, locations, and terms evolve across chapters and milestones.\n\nDisabling this will hide the Story Arc button from lookup popups and detail dialogs.",
    })
end

function M:showPopupFontSizeCard(...)
    local style_cards = require(plugin_path .. "xray_style_cards")
    return style_cards.showPopupFontSizeCard(self, ...)
end

function M:showAutoUpdateSettings()
    XRaySettingsCard.show(self, {
        title = (self.loc:t("auto_update_freq_label") or "Background Fetching Frequency"):gsub(":$", ""),
        description = self.loc:t("menu_auto_update_frequency") or "Auto X-Ray Settings",
        options = function()
            return {
                { text = self.loc:t("auto_update_ultra", self.ai_helper.settings and self.ai_helper.settings.auto_fetch_page_interval or 25) or ("Ultra: checks every " .. (self.ai_helper.settings and self.ai_helper.settings.auto_fetch_page_interval or 25) .. " pages"), value = "ultra" },
                { text = self.loc:t("auto_update_aggressive") or "Aggressive: checks every new chapter", value = "aggressive" },
                { text = self.loc:t("auto_update_balanced") or "Balanced: checks at most every 5 mins", value = "balanced" },
                { text = self.loc:t("auto_update_economical") or "Economical: checks at most every 15 mins", value = "economical" },
                { text = self.loc:t("auto_update_sparse") or "Sparse: checks at most every 30 mins", value = "sparse" },
                { text = self.loc:t("auto_update_disabled") or "Disabled", value = "disabled" },
            }
        end,
        get_current_func = function()
            local is_enabled = self.auto_fetch_enabled
            local current_cooldown = self.ai_helper.settings and self.ai_helper.settings.auto_fetch_cooldown or 300
            local page_interval = self.ai_helper.settings and self.ai_helper.settings.auto_fetch_page_interval
            local current = "disabled"
            if is_enabled then
                if page_interval ~= nil and page_interval > 0 then
                    current = "ultra"
                elseif current_cooldown == 0 then
                    current = "aggressive"
                elseif current_cooldown == 300 then
                    current = "balanced"
                elseif current_cooldown == 900 then
                    current = "economical"
                elseif current_cooldown == 1800 then
                    current = "sparse"
                end
            end
            return current
        end,
        save_func = function(val, refresh_card)
            local page_interval = self.ai_helper.settings and self.ai_helper.settings.auto_fetch_page_interval
            if val == "ultra" then
                local SpinWidget = require("ui/widget/spinwidget")
                local spin_dialog
                spin_dialog = SpinWidget:new{
                    title_text = self.loc:t("auto_fetch_page_interval_prompt") or "Page Interval",
                    value = page_interval or 25,
                    value_min = 5,
                    value_max = 200,
                    value_step = 5,
                    callback = function(spin)
                        local chosen = spin.value
                        self.auto_fetch_enabled = true
                        self.ai_helper:saveSettings({
                            auto_fetch_on_chapter = true,
                            auto_fetch_cooldown = 0,
                            auto_fetch_page_interval = chosen
                        })
                        UIManager:close(spin_dialog)
                        refresh_card()
                    end,
                    cancel_callback = function()
                        UIManager:close(spin_dialog)
                    end
                }
                UIManager:show(spin_dialog, "full")
                return true
            elseif val == "aggressive" then
                self.auto_fetch_enabled = true
                self.ai_helper:saveSettings({ auto_fetch_on_chapter = true, auto_fetch_cooldown = 0 }, { "auto_fetch_page_interval" })
            elseif val == "balanced" then
                self.auto_fetch_enabled = true
                self.ai_helper:saveSettings({ auto_fetch_on_chapter = true, auto_fetch_cooldown = 300 }, { "auto_fetch_page_interval" })
            elseif val == "economical" then
                self.auto_fetch_enabled = true
                self.ai_helper:saveSettings({ auto_fetch_on_chapter = true, auto_fetch_cooldown = 900 }, { "auto_fetch_page_interval" })
            elseif val == "sparse" then
                self.auto_fetch_enabled = true
                self.ai_helper:saveSettings({ auto_fetch_on_chapter = true, auto_fetch_cooldown = 1800 }, { "auto_fetch_page_interval" })
            elseif val == "disabled" then
                self.auto_fetch_enabled = false
                self.ai_helper:saveSettings({ auto_fetch_on_chapter = false }, { "auto_fetch_page_interval" })
            end
        end,
        about_text = self.loc:t("auto_update_freq_about") or "Auto-update checks for new chapter data in the background as you read.\n\n[B]Limits & Performance[/B]\nFrequent background requests can drain [B]battery life[/B] and may hit [B]AI provider rate limits[/B].\n\n[B]Note:[/B] skipped chapters will be automatically included in the next background update.",
    })
end

function M:showSpoilerSettings()
    XRaySettingsCard.show(self, {
        title = self.loc:t("spoiler_preference_title") or "Spoiler Settings",
        description = self.loc:t("spoiler_preference_desc") or "Select your spoiler preference for X-Ray data:",
        options = {
            { text = self.loc:t("spoiler_free_menu_option") or "Spoiler-free", value = "spoiler_free" },
            { text = self.loc:t("full_book_option") or "Full Book Mode", value = "full_book" },
        },
        get_current_func = function()
            return self.ai_helper.settings and self.ai_helper.settings.spoiler_setting or "spoiler_free"
        end,
        save_func = function(val)
            self.ai_helper:saveSettings({ spoiler_setting = val })
            if val == "full_book" and self.auto_fetch_enabled then
                if self.isCatchUpNeeded and self:isCatchUpNeeded() then
                    self.pending_background_fetch = true
                    self:scheduleBackgroundCatchUp(2)
                end
            end
            UIManager:setDirty(nil, "ui")
        end,
        about_text = self.loc:t("spoiler_free_about") or "Spoiler-free mode limits AI extraction to the pages you have already read (up to your current page), preventing spoilers from future chapters.\n\n[B]Full Book Mode:[/B] Analyzes the entire book, which [B]may contain spoilers[/B].",
    })
end

function M:showPrefetchHorizonSettings()
    local options = {
        { text = self.loc and self.loc:t("horizon_off") or "Off (Current Only)", value = 0 },
        { text = self.loc and self.loc:t("horizon_1") or "1 Chapter Ahead", value = 1 },
        { text = self.loc and self.loc:t("horizon_2") or "2 Chapters Ahead", value = 2 },
        { text = self.loc and self.loc:t("horizon_3") or "3 Chapters Ahead", value = 3 },
        { text = self.loc and self.loc:t("horizon_5") or "5 Chapters Ahead", value = 5 },
    }
    XRaySettingsCard.show(self, {
        title = self.loc and self.loc:t("menu_prefetch_horizon") or "Prefetch Horizon (Offline Readers)",
        description = self.loc and self.loc:t("prefetch_horizon_desc") or "Pre-generate upcoming chapters in the background while online, keeping descriptions spoiler-free until you reach them:",
        options = options,
        get_current_func = function()
            return (self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.prefetch_horizon_chapters) or 0
        end,
        save_func = function(val)
            if self.ai_helper then
                self.ai_helper:saveSettings({ prefetch_horizon_chapters = val })
            end
            if val > 0 and self.checkPrefetchHorizon then
                self:checkPrefetchHorizon()
            end
            UIManager:setDirty(nil, "ui")
        end,
        about_text = "When reading offline (airplane mode or commuting), X-Ray cannot query the AI. The Prefetch Horizon scans N chapters ahead in the background while connected to Wi-Fi. All future character states and events remain strictly hidden until you reach their respective chapters.",
    })
end

function M:startFullBookPreGeneration()
    if self.ai_helper and type(self.ai_helper.hasApiKey) == "function" and not self.ai_helper:hasApiKey() then
        if self.showWelcomeCard then self:showWelcomeCard() end
        return
    end

    if self.is_sequential_scan_active or (self.isSequentialChapterScanActive and self:isSequentialChapterScanActive()) then
        local done_ch = self.active_sequential_completed_chapters or self.active_sequential_completed or 0
        local total_ch = self.active_sequential_total_chapters or self.active_sequential_total or 0
        local done_seg = self.active_sequential_completed or 0
        local total_seg = self.active_sequential_total or 0
        local batch = self.active_sequential_current_batch or self.active_sequential_batch
        local batch_text = "Preparing next batch..."
        if batch and #batch > 0 then
            local titles = {}
            for _, b in ipairs(batch) do
                local title_str = b.title or "Untitled"
                if b.parent_title and b.is_virtual_segment and b.part_index and b.total_parts then
                    title_str = string.format("%s (Part %d/%d)", b.parent_title, b.part_index, b.total_parts)
                end
                table.insert(titles, string.format("Ch. %d: %s", b.parent_toc_index or b.toc_index or 1, title_str))
            end
            batch_text = table.concat(titles, "\n  • ")
        end
        local elapsed = 0
        if self.active_sequential_batch_start_time then
            elapsed = math.max(0, os.time() - self.active_sequential_batch_start_time)
        end
        local status_msg = self.active_sequential_status or "Working..."
        local ButtonDialog = require("ui/widget/buttondialog")
        local progress_line
        if total_seg > total_ch then
            progress_line = string.format("• Progress: Chapter %d of %d (%d of %d segments processed)", done_ch, total_ch, done_seg, total_seg)
        else
            progress_line = string.format("• Progress: %d of %d chapters processed", done_ch, total_ch)
        end
        local status_text = string.format(
            "Pre-generation is currently running in the background.\n\n" ..
            "%s\n" ..
            "• Current Batch:\n  • %s\n" ..
            "• Status: %s (%ds elapsed)\n",
            progress_line, batch_text, status_msg, elapsed
        )
        local dlg_title = self.loc and self.loc:t("menu_pregenerate_book") or "Pre-generate Entire Book"
        local status_dlg
        status_dlg = ButtonDialog:new{
            modal = true,
            title = dlg_title .. "\n\n" .. status_text,
            text = status_text,
            buttons = {
                {
                    {
                        text = self.loc and self.loc:t("stop_pregeneration") or "Stop Pre-generation",
                        callback = function()
                            UIManager:close(status_dlg)
                            if self.cancelSequentialChapterScan then
                                self:cancelSequentialChapterScan()
                            end
                            UIManager:show(InfoMessage:new{ text = self.loc and self.loc:t("pregeneration_stopped") or "Pre-generation stopped.", timeout = 3 })
                        end
                    },
                    {
                        text = self.loc and self.loc:t("refresh") or "Refresh",
                        callback = function()
                            UIManager:close(status_dlg)
                            self:startFullBookPreGeneration()
                        end
                    },
                    {
                        text = self.loc and self.loc:t("continue_in_background") or "Close",
                        is_enter_default = true,
                        callback = function()
                            UIManager:close(status_dlg)
                        end
                    }
                }
            }
        }
        UIManager:show(status_dlg)
        return
    end

    if not self.ui or not self.ui.document then
        UIManager:show(InfoMessage:new{ text = self.loc and self.loc:t("no_document") or "No document open.", timeout = 3 })
        return
    end

    if self._book_type_detecting and self.ai_helper and self.ai_helper.cancelAsyncChild then
        self:log("XRayPlugin: Pre-empting background book-type detection for manual pregeneration.")
        self.ai_helper:cancelAsyncChild()
        self._book_type_detecting = nil
    end

    local raw_toc
    pcall(function()
        if self.ui.document.getToc then raw_toc = self.ui.document:getToc() end
    end)
    local toc = utils:flattenTOC(raw_toc)
    if not toc or #toc == 0 then
        UIManager:show(InfoMessage:new{ text = self.loc and self.loc:t("no_toc_found") or "No table of contents found in this document.", timeout = 3 })
        return
    end

    local narrative_chapters = {}
    for i, ch in ipairs(toc) do
        local title = ch.title or ""
        local is_non = self.isNonNarrativeChapter and self:isNonNarrativeChapter(title)
        if not is_non then
            ch.toc_index = i
            table.insert(narrative_chapters, ch)
        end
    end
    local raw_chapter_count = #narrative_chapters

    local ChapterAnalyzer = require(plugin_path .. "xray_chapteranalyzer")
    local total_pages = self.ui and self.ui.document and self.ui.document.getPageCount and self.ui.document:getPageCount() or 0
    if ChapterAnalyzer and ChapterAnalyzer.expandOversizedTocChapters then
        narrative_chapters = ChapterAnalyzer:expandOversizedTocChapters(narrative_chapters, total_pages, 60)
    end

    if #narrative_chapters == 0 then
        UIManager:show(InfoMessage:new{ text = self.loc and self.loc:t("no_chapters_found") or "No narrative chapters found.", timeout = 3 })
        return
    end

    local already_fetched_count = 0
    local is_anthology = self.isAnthologyMode and self:isAnthologyMode()
    for _, candidate in ipairs(narrative_chapters) do
        local cand_idx = candidate.toc_index or 1
        local cand_id = (candidate.title or ("Chapter " .. tostring(cand_idx))) .. "_" .. tostring(candidate.page)
        local cand_already_fetched = self.chapters_fetched and self.chapters_fetched[cand_id]
        if not cand_already_fetched and self.timeline then
            for _, ev in ipairs(self.timeline) do
                local story_match = not is_anthology or not candidate.story_id or (ev.story_id == candidate.story_id)
                if story_match then
                    if (ev.chapter_index and ev.chapter_index == cand_idx) or
                       (ev.page and candidate.page and tonumber(ev.page) == tonumber(candidate.page)) then
                        cand_already_fetched = true
                        break
                    end
                end
            end
        end
        if cand_already_fetched then
            already_fetched_count = already_fetched_count + 1
        end
    end

    local ButtonDialog = require("ui/widget/buttondialog")
    local confirm_dlg
    local prompt_text
    local confirm_buttons

    local function startScan(force)
        if force then
            self:_clearAIData()
            local doc_file = self.ui and self.ui.document and self.ui.document.file
            if doc_file and self.cache_manager then
                self.cache_manager:clearCache(doc_file)
            end
        end
        UIManager:show(InfoMessage:new{
            text = self.loc and self.loc:t("pregeneration_started") or "Pre-generation started in background.",
            timeout = 3,
        })
        self:queueSequentialChapterScan(narrative_chapters, true, function(done, total, done_ch, total_ch)
            local cur_ch = done_ch or done or 0
            local max_ch = total_ch or total or 0
            self:log(string.format("XRayPlugin: Pre-generation progress: %d of %d chapters (%d of %d segments).", cur_ch, max_ch, done or 0, total or 0))
        end, function(success, err_msg, batches_processed)
            if success then
                if (batches_processed or 0) == 0 then
                    UIManager:show(InfoMessage:new{
                        text = self.loc and self.loc:t("pregeneration_already_up_to_date") or "All chapters are already up to date.",
                        timeout = 4,
                    })
                else
                    UIManager:show(InfoMessage:new{
                        text = self.loc and self.loc:t("pregeneration_complete") or "Pre-generation complete!",
                        timeout = 4,
                    })
                end
            else
                UIManager:show(InfoMessage:new{
                    text = "Pre-generation could not be completed: " .. tostring(err_msg or "AI request failed"),
                    timeout = 5,
                })
            end
        end, force)
    end

    if already_fetched_count >= #narrative_chapters then
        prompt_text = string.format(
            "All %d chapters (%d segments) have already been scanned and are stored in the X-Ray cache.\n\nWould you like to re-generate the entire book from scratch? (This will re-analyze all chapters with updated prompts and page gating)",
            raw_chapter_count, #narrative_chapters
        )
        confirm_buttons = {
            {
                {
                    text = self.loc and self.loc:t("cancel") or "Cancel",
                    callback = function() UIManager:close(confirm_dlg) end,
                },
                {
                    text = self.loc and self.loc:t("regenerate_all") or "Re-generate All (Fresh Scan)",
                    is_enter_default = true,
                    callback = function()
                        UIManager:close(confirm_dlg)
                        startScan(true)
                    end,
                },
            }
        }
    elseif already_fetched_count > 0 then
        local remaining = #narrative_chapters - already_fetched_count
        prompt_text = string.format(
            "%d of %d chapters have already been scanned (%d remaining).\n\nWould you like to resume scanning the remaining chapters, or re-generate all chapters from scratch?",
            already_fetched_count, raw_chapter_count, remaining
        )
        confirm_buttons = {
            {
                {
                    text = self.loc and self.loc:t("cancel") or "Cancel",
                    callback = function() UIManager:close(confirm_dlg) end,
                },
                {
                    text = string.format(self.loc and self.loc:t("resume_remaining") or "Resume (%d remaining)", remaining),
                    is_enter_default = true,
                    callback = function()
                        UIManager:close(confirm_dlg)
                        startScan(false)
                    end,
                },
                {
                    text = self.loc and self.loc:t("regenerate_all") or "Re-generate All",
                    callback = function()
                        UIManager:close(confirm_dlg)
                        startScan(true)
                    end,
                },
            }
        }
    else
        if #narrative_chapters > raw_chapter_count then
            prompt_text = string.format(
                "This will sequentially scan and analyze all %d chapters (%d segments) in the background. Newly discovered character states, locations, and glossary terms will remain spoiler-free until you reach them.\n\nContinue?",
                raw_chapter_count, #narrative_chapters
            )
        else
            prompt_text = (self.loc and self.loc:t("pregenerate_confirm_text") or "This will sequentially scan and analyze all %d chapters in the background. Newly discovered character states, locations, and glossary terms will remain spoiler-free until you reach them.\n\nContinue?"):format(raw_chapter_count)
        end
        confirm_buttons = {
            {
                {
                    text = self.loc and self.loc:t("cancel") or "Cancel",
                    callback = function() UIManager:close(confirm_dlg) end,
                },
                {
                    text = self.loc and self.loc:t("start") or "Start",
                    is_enter_default = true,
                    callback = function()
                        UIManager:close(confirm_dlg)
                        startScan(false)
                    end,
                },
            }
        }
    end

    local dlg_title = self.loc and self.loc:t("menu_pregenerate_book") or "Pre-generate Entire Book"
    confirm_dlg = ButtonDialog:new{
        modal = true,
        title = dlg_title .. "\n\n" .. prompt_text,
        text = prompt_text,
        buttons = confirm_buttons,
    }
    UIManager:show(confirm_dlg)
end

function M:showEntityLengthPresets(setting_key, entity_name, is_timeline)
    local defaults = {
        char_desc_len    = 200,
        loc_desc_len     = 100,
        timeline_event_len = 80,
        hist_fig_bio_len = 100,
    }

    local presets = {
        { name = self.loc:t("desc_len_short"),      val = is_timeline and 50  or (setting_key == "char_desc_len" and 80  or 50)  },
        { name = self.loc:t("desc_len_default"),    val = is_timeline and 80  or (setting_key == "char_desc_len" and 200 or 100) },
        { name = self.loc:t("desc_len_detailed"),   val = is_timeline and 150 or (setting_key == "char_desc_len" and 350 or 200) },
        { name = self.loc:t("desc_len_v_detailed"), val = is_timeline and 200 or (setting_key == "char_desc_len" and 500 or 300) },
    }

    local options = {}
    for _, p in ipairs(presets) do
        table.insert(options, { text = p.name, value = p.val })
    end

    local about_text
    if is_timeline then
        about_text = self.loc:t("desc_len_about_timeline") or "Controls how much detail the AI includes in each summary on the book timeline.\n\n[B]Size options[/B]\n• Short (~50 chars): Brief one-phrase summary.\n• Default (~80 chars): Standard summary.\n• Detailed (~150 chars): Includes context and consequences.\n\n[B]Note:[/B] the timeline always has exactly one entry per chapter, so there is no size trade-off."
    elseif setting_key == "char_desc_len" then
        about_text = self.loc:t("desc_len_about_chars") or "Controls how much detail the AI includes in each character's profile.\n\n[B]Size options[/B]\n• Short (~80 chars): Name, role, and a brief note.\n• Default (~200 chars): Standard analysis.\n• Detailed (~350 chars): Rich character study with traits and motivations.\n• Very Detailed (~500 chars): Full deep analysis.\n\n[B]Trade-off[/B]\nLonger descriptions consume more tokens, meaning [B]fewer[/B] characters are returned during initial fetches."
    elseif setting_key == "loc_desc_len" then
        about_text = self.loc:t("desc_len_about_locs") or "Controls how much detail the AI includes in each location's description.\n\n[B]Size options[/B]\n• Short (~50 chars): Place name and one-line context.\n• Default (~100 chars): Standard description.\n• Detailed (~200 chars): Atmosphere, significance, and events.\n• Very Detailed (~300 chars): Comprehensive description.\n\n[B]Trade-off[/B]\nLonger descriptions consume more tokens, meaning [B]fewer[/B] locations are returned during initial fetches."
    else
        about_text = self.loc:t("desc_len_about_hist") or "Controls how much detail the AI includes in each historical figure's biography.\n\n[B]Size options[/B]\n• Short (~50 chars): Name and primary role.\n• Default (~100 chars): Standard biography.\n• Detailed (~200 chars): Life, significance, and book context.\n• Very Detailed (~300 chars): Comprehensive biography.\n\n[B]Trade-off[/B]\nLonger biographies consume more tokens, meaning [B]fewer[/B] figures are returned during initial fetches."
    end

    XRaySettingsCard.show(self, {
        title = entity_name .. " — " .. (self.loc:t("menu_desc_length_settings") or "Description Length"),
        options = options,
        get_current_func = function()
            local current_s = self.ai_helper and self.ai_helper.settings or {}
            return current_s[setting_key] or (is_timeline and 80 or defaults[setting_key] or 100)
        end,
        save_func = function(pval)
            if self.ai_helper then
                local updates = {}
                updates[setting_key] = pval
                self.ai_helper:saveSettings(updates)
            end
        end,
        about_text = about_text,
    })
end

function M:showAuthorInfo()
    if not self.author_info or not self.author_info.description or self.author_info.description == "" or self.author_info.description == (self.loc:t("msg_no_bio") or "No biography available.") then
        local ButtonDialog = require("ui/widget/buttondialog")
        local ask_dialog
        ask_dialog = ButtonDialog:new{ modal = true, title = (self.loc:t("menu_fetch_author") or "Fetch Author Info") .. "\n\n" .. (self.loc:t("no_author_data_fetch") or "No author biography available. Fetch now?"), buttons = {{{ text = self.loc:t("cancel"), callback = function() UIManager:close(ask_dialog) end }, { text = self.loc:t("fetch_button") or "Fetch", is_enter_default = true, callback = function() UIManager:close(ask_dialog); UIManager:nextTick(function() self:fetchAuthorInfo() end) end }}} }
        UIManager:show(ask_dialog); return
    end

    local ButtonDialog = require("ui/widget/buttondialog")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local TextBoxWidget = require("ui/widget/textboxwidget")
    local VerticalSpan = require("ui/widget/verticalspan")
    local Font = require("ui/font")
    local Geom = require("ui/geometry")
    local Screen = require("device").screen
    
    local dialog_width = math.floor(math.min(Screen:getWidth(), Screen:getHeight()) * 0.9)
    local border_window = (Size.border and Size.border.window) or 1
    local padding_button = (Size.padding and Size.padding.button) or 10
    local padding_default = (Size.padding and Size.padding.default) or 10
    local margin_default = (Size.margin and Size.margin.default) or 5
    local buttontable_width = dialog_width - 2 * border_window - 2 * padding_button
    local title_group_width = buttontable_width - 2 * (padding_default + margin_default)

    local metrics = self:calculatePopupFontMetrics(self.author_info)
    local fs = metrics.fs
    local fs_small = metrics.fs_small
    local align = self:isRTL() and "right" or "left"
    local vg_components = { align = align }

    -- 1. Bold Name
    table.insert(vg_components, TextBoxWidget:new{
        text = self.author_info.name or "Unknown",
        face = Font:getFace("cfont", fs),
        width = title_group_width,
        bold = true,
        alignment = align,
    })

    -- 2. Metadata (Born / Died)
    local metadata = {}
    if self.author_info.birthDate and self.author_info.birthDate ~= "" and self.author_info.birthDate ~= "---" then
        table.insert(metadata, (self.loc:t("author_born") or "Born: ") .. self.author_info.birthDate)
    end
    if self.author_info.deathDate and self.author_info.deathDate ~= "" and self.author_info.deathDate ~= "---" then
        table.insert(metadata, (self.loc:t("author_died") or "Died: ") .. self.author_info.deathDate)
    end
    if #metadata > 0 then
        local xray_theme = require(plugin_path .. "xray_theme")
        table.insert(vg_components, VerticalSpan:new{ width = math.max(4, math.floor(fs * 0.2)) })
        table.insert(vg_components, TextBoxWidget:new{
            text = table.concat(metadata, "   "),
            face = Font:getFace("cfont", fs_small),
            fgcolor = xray_theme.color_label_dim,
            width = title_group_width,
            alignment = align,
        })
    end

    -- 3. Biography Description
    table.insert(vg_components, VerticalSpan:new{ width = math.max(6, math.floor(fs * 0.3)) })
    table.insert(vg_components, TextBoxWidget:new{
        text = self.author_info.description or "No biography available.",
        face = Font:getFace("cfont", fs),
        width = title_group_width,
        alignment = align,
    })

    local vg = VerticalGroup:new(vg_components)

    local buttons = {
        {
            {
                text = self.loc:t("close") or "Close",
                callback = function()
                    if self.active_details_dialog then UIManager:close(self.active_details_dialog) end
                    self.active_details_dialog = nil
                end,
            }
        }
    }

    self.active_details_dialog = ButtonDialog:new{
        modal = true,
        _added_widgets = { vg },
        buttons = buttons,
    }
    UIManager:show(self.active_details_dialog)
end

function M:showLocations()
    self.locations = self.locations or {}
    if not self:hasXRayData() then
        self:_promptNoDataFetch()
        return
    end
    if #self.locations == 0 then 
        local InfoMessage = require("ui/widget/infomessage")
        UIManager:show(InfoMessage:new{ text = self.loc:t("no_location_data"), timeout = 3 })
        return 
    end

    if self.loc_menu then
        UIManager:close(self.loc_menu)
        self.loc_menu = nil
    end

    local EntityListOverlay = require(plugin_path .. "xray_entity_list")
    self.loc_menu = EntityListOverlay:new{
        plugin = self,
        mode = "locations",
        raw_items = self.locations,
    }
    UIManager:show(self.loc_menu, "ui")

    UIManager:scheduleIn(0.3, function()
        if self.destroyed or not self.ui or not self.ui.document then return end
        if self.isAnthologyMode and self:isAnthologyMode() and self.pending_duplicate_review and self.pending_duplicate_review.story_id then
            local cs = self.getCurrentStory and self:getCurrentStory()
            if not cs or cs.story_id ~= self.pending_duplicate_review.story_id then
                self.pending_duplicate_review = nil
            end
        end
        if self.pending_duplicate_review and self.pending_duplicate_review.locations and #self.pending_duplicate_review.locations > 0 then
            local pairs = self:filterValidDuplicatePairs(self.locations, self.pending_duplicate_review.locations)
            self.pending_duplicate_review.locations = nil
            if #pairs > 0 then
                local ButtonDialog = require("ui/widget/buttondialog")
                local prompt_dlg
                prompt_dlg = ButtonDialog:new{
                    modal = true,
                    title = string.format(
                        self.loc:t("pending_duplicates_prompt") or
                        "AI found %d possible duplicate location(s) from the last fetch. Review now?",
                        #pairs
                    ),
                    buttons = {{
                        {
                            text = self.loc:t("later") or "Later",
                            callback = function()
                                UIManager:close(prompt_dlg)
                            end,
                        },
                        {
                            text = self.loc:t("review") or "Review",
                            is_enter_default = true,
                            callback = function()
                                UIManager:close(prompt_dlg)
                                self:log("XRayPlugin: User chose to review pending " .. tostring(#pairs) .. " duplicate(s) for locations")
                                self:walkDuplicatePairs(self.locations, "locations", pairs)
                            end,
                        },
                    }},
                }
                UIManager:show(prompt_dlg)
            end
        end
    end)
end

function M:showAbout()
    local meta = dofile(self.path .. "/_meta.lua")
    local version = meta.version or "?.?.?"
    local description = self.loc:t("plugin_description") or tostring(meta.description or "")

    local body = (meta.fullname or "X-Ray") .. " v" .. version .. "\n\n" .. description

    local ButtonDialog = require("ui/widget/buttondialog")
    local about_dlg
    about_dlg = ButtonDialog:new{
        modal = true,
        title = body,
        buttons = {{
            {
                text = self.loc:t("close") or "Close",
                callback = function()
                    UIManager:close(about_dlg)
                end,
            },
            {
                text = self.loc:t("updater_check") or "Check for Updates",
                is_enter_default = true,
                callback = function()
                    UIManager:close(about_dlg)
                    local updater = require(plugin_path .. "xray_updater")
                    updater.checkForUpdates(self.loc, self.ai_helper.settings.beta_channel_enabled)
                end,
            },
        }},
    }
    UIManager:show(about_dlg)
end

function M:_clearAIData()
    self.characters = {}
    self.locations = {}
    self.timeline = {}
    self.chapters_fetched = {}
    self.historical_figures = {}
    self.terms = {}
    self.terms_fetched = false
    self.author_info = nil
    if self.book_data then
        self.book_data.characters = {}
        self.book_data.locations = {}
        self.book_data.timeline = {}
        self.book_data.historical_figures = {}
        self.book_data.terms = {}
        self.book_data.last_fetch_page = nil
    end
end

function M:confirmAndRebuildXRay()
    local ButtonDialog = require("ui/widget/buttondialog")
    local dialog
    local dlg_title = self.loc:t("rebuild_confirm_title") or "Rebuild X-Ray Data"
    local dlg_text = self.loc:t("rebuild_confirm_text")
        or "This will discard all cached X-Ray data for this book and fetch fresh data from AI.\n\nContinue?"
    dialog = ButtonDialog:new{
        title = dlg_title .. "\n\n" .. dlg_text,
        text  = dlg_text,
        buttons = {{
            {
                text = self.loc:t("cancel") or "Cancel",
                callback = function() UIManager:close(dialog) end,
            },
            {
                text = self.loc:t("rebuild_confirm_btn") or "Rebuild",
                is_enter_default = true,
                callback = function()
                    UIManager:close(dialog)
                    self:_clearAIData()
                    UIManager:nextTick(function() self:fetchFromAI() end)
                end,
            },
        }},
    }
    UIManager:show(dialog)
end

function M:clearCache()
    if not self.cache_manager then self.cache_manager = require(plugin_path .. "xray_cachemanager"):new() end
    if self.ui and self.ui.document and self.ui.document.file then
        self.cache_manager:clearCache(self.ui.document.file)
    end
    self._pending_series_sync = nil
    self.characters = {}
    self.locations = {}
    self.timeline = {}
    self.chapters_fetched = {}
    self.historical_figures = {}
    self.terms = {}
    self.terms_fetched = false
    self.images = {}
    self.author_info = nil
    self.book_data = {}
    self.series_context_loaded = false
    self.xray_mode_enabled = false
    if self.image_manager and self.image_manager.clearSpineCache then
        self.image_manager:clearSpineCache()
    end
    if self.clearEntityUnderlines then
        self:clearEntityUnderlines()
    end
    local entity_cache_file = self._getEntityCachePath and self:_getEntityCachePath()
    if entity_cache_file then
        pcall(os.remove, entity_cache_file)
    end
    if self.clearUnitUnderlines then
        self:clearUnitUnderlines()
    end
    UIManager:show(InfoMessage:new{ text = self.loc:t("cache_cleared"), timeout = 3 })
end

function M:clearSeriesCache()
    local props = self.ui and self.ui.document and self.ui.document.getProps and self.ui.document:getProps() or {}
    local function sanitizeMetadata(val)
        if type(val) == "string" then return val
        elseif type(val) == "table" then return table.concat(val, ", ")
        else return "Unknown" end
    end
    local title = sanitizeMetadata(props.title)
    local author = sanitizeMetadata(props.authors)

    if not self.series_manager then
        self.series_manager = require(plugin_path .. "xray_seriesmanager"):new()
    end
    local series_info = self.series_manager.detectSeries and self.series_manager:detectSeries(props, title, author, nil)
    local slug = (self.book_data and self.book_data.series_slug) or (series_info and series_info.slug)
    local series_name = (series_info and series_info.name) or (self.book_data and self.book_data.series_slug)

    if not slug or slug == "" then
        UIManager:show(InfoMessage:new{
            text = self.loc:t("no_series_to_clear") or "No series detected for this book.",
            timeout = 3
        })
        return
    end

    local cache_path = self.series_manager.getSeriesCachePath and self.series_manager:getSeriesCachePath(slug)
    if cache_path then
        pcall(function() os.remove(cache_path) end)
    end

    self._pending_series_sync = nil
    self.series_context_loaded = false
    if self.book_data then
        self.book_data.series_context_loaded = nil
        self.book_data.series_context_dismissed = nil
        if self.cache_manager and self.ui and self.ui.document and self.ui.document.file then
            self.cache_manager:asyncSaveCache(self.ui.document.file, self.book_data)
        end
    end

    UIManager:show(InfoMessage:new{
        text = self.loc:t("series_cache_cleared", series_name or slug),
        timeout = 3
    })
end

-- Log viewer extracted to xray_log_viewer.lua

function M:toggleXRayMode()
    local button_text = self.loc:t("xray_mode_button_label") or "Button in Menu (Default)"
    local auto_popup_text = self.loc:t("xray_mode_auto_popup_label") or "Auto-Popup on Highlight"
    local disabled_text = self.loc:t("xray_disabled_label") or "Disabled"
    XRaySettingsCard.show(self, {
        title = self.loc:t("menu_xray_mode") or "X-Ray Mode Settings",
        description = self.loc:t("xray_mode_desc"),
        options = {
            { text = button_text, value = "button" },
            { text = auto_popup_text, value = "auto_popup" },
            { text = disabled_text, value = "disabled" },
        },
        get_current_func = function()
            if self.xray_mode_enabled == false then
                return "disabled"
            elseif self.xray_auto_popup == true then
                return "auto_popup"
            else
                return "button"
            end
        end,
        save_func = function(val)
            if val == "auto_popup" then
                self.xray_mode_enabled = true
                self.xray_auto_popup = true
                if self.ai_helper then
                    self.ai_helper:saveSettings({ xray_mode_enabled = true, xray_auto_popup = true })
                end
            elseif val == "button" or val == true then
                self.xray_mode_enabled = true
                self.xray_auto_popup = false
                if self.ai_helper then
                    self.ai_helper:saveSettings({ xray_mode_enabled = true, xray_auto_popup = false })
                end
            else
                self.xray_mode_enabled = false
                self.xray_auto_popup = false
                if self.ai_helper then
                    self.ai_helper:saveSettings({ xray_mode_enabled = false, xray_auto_popup = false })
                end
            end
            UIManager:setDirty(nil, "ui")
        end,
        about_text = self.loc:t("xray_mode_about") or "Controls how X-Ray integrates with text selection while reading:\n\n• [B]Button in Menu:[/B] Adds an 'X-Ray' button to KOReader's dictionary and highlight menus.\n• [B]Auto-Popup on Highlight:[/B] Immediately opens X-Ray when you select a word or name that has X-Ray data, skipping the highlight menu. If no X-Ray data matches, the regular menu is shown. Use the 'Highlight Menu' button inside the popup anytime to highlight or look up the word in the dictionary.\n• [B]Disabled:[/B] Hides in-text X-Ray lookup buttons.",
    })
end

function M:showTimeline()
    if not self:hasXRayData() then
        self:_promptNoDataFetch()
        return
    end
    if not self.timeline or #self.timeline == 0 then
        local InfoMessage = require("ui/widget/infomessage")
        UIManager:show(InfoMessage:new{ text = self.loc:t("no_timeline_data"), timeout = 3 })
        return
    end
    local utils = require(plugin_path .. "xray_utils")
    local toc = utils:flattenTOC(self.ui.document:getToc())
    self:assignTimelinePages(self.timeline, toc, true)
    if self.retagEntitiesByStory and self:isAnthologyMode() then
        self:retagEntitiesByStory()
    end
    if self.filterOrphanTimelineEvents then
        self.timeline = self:filterOrphanTimelineEvents(self.timeline, toc)
    end
    self:sortTimelineByTOC(self.timeline)

    if self.timeline_menu then
        UIManager:close(self.timeline_menu)
        self.timeline_menu = nil
    end

    local EntityListOverlay = require(plugin_path .. "xray_entity_list")
    self.timeline_menu = EntityListOverlay:new{
        plugin = self,
        mode = "timeline",
        raw_items = self.timeline,
    }
    UIManager:show(self.timeline_menu, "ui")
end

function M:showTimelineEventDetails(ev, opts)
    -- (A) Bottom-popup path (when enabled in settings)
    if shouldUseBottomPopup(self, opts) then
        -- Wrap the timeline event as a normalized entity for the existing popup
        local entity = {
            name        = ev.chapter or "",
            description = ev.event   or "",
            is_timeline = true,
        }
        showBottomPopup(self, entity)
        return
    end

    -- (B) ButtonDialog path
    local metrics = self:calculatePopupFontMetrics(ev)
    local fs = metrics.fs
    local fs_small = metrics.fs_small
    local border_window  = (Size.border  and Size.border.window)   or 1
    local padding_button = (Size.padding and Size.padding.button)   or 10
    local padding_default= (Size.padding and Size.padding.default)  or 10
    local margin_default = (Size.margin  and Size.margin.default)   or 5

    local dialog_width       = math.floor(math.min(Screen:getWidth(), Screen:getHeight()) * 0.9)
    local buttontable_width  = dialog_width - 2 * border_window - 2 * padding_button
    local content_width      = buttontable_width - 2 * (padding_default + margin_default)

    local align = self:isRTL() and "right" or "left"
    local vg_components = { align = align }

    -- 1. Chapter title (bold)
    table.insert(vg_components, TextBoxWidget:new{
        text      = ev.chapter or "",
        face      = Font:getFace("cfont", fs),
        width     = content_width,
        bold      = true,
        alignment = align,
    })

    -- 2. Event text (possibly truncated)
    local event_text   = ev.event or ""
    local display_text = event_text
    local is_truncated = false
    local TRUNCATE_AT  = 300   -- chars before we add Read More

    display_text, is_truncated = _getTruncatedText(event_text, TRUNCATE_AT)
    if is_truncated then
        local last_sp = display_text:match("^.*()%s")
        if last_sp then display_text = display_text:sub(1, last_sp - 1) end
        display_text  = display_text .. " ..."
    end

    if event_text ~= "" then
        table.insert(vg_components, VerticalSpan:new{
            width = math.max(6, math.floor(fs * 0.3))
        })
        table.insert(vg_components, TextBoxWidget:new{
            text      = display_text,
            face      = Font:getFace("cfont", fs),
            width     = content_width,
            alignment = align,
        })
    end

    local linked_enabled = self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.linked_entries_enabled ~= false
    local related = linked_enabled and self:findRelatedEntities(event_text, ev.chapter, ev) or {}

    local vg = VerticalGroup:new(vg_components)
    vg.not_focusable = true

    -- Buttons
    local buttons = {}
    if #related > 0 then
        buttons = {
            {
                {
                    text     = self.loc:t("linked_entries") or "Linked Entries",
                    callback = function()
                        if self.active_details_dialog then UIManager:close(self.active_details_dialog); self.active_details_dialog = nil end
                        self:showRelatedEntities(related, opts, ev)
                    end,
                },
                {
                    text     = self.loc:t("close") or "Close",
                    is_enter_default = true,
                    callback = function()
                        if self.active_details_dialog then
                            UIManager:close(self.active_details_dialog)
                        end
                        self.active_details_dialog = nil
                    end,
                }
            }
        }
    else
        buttons = {
            {
                {
                    text     = self.loc:t("close") or "Close",
                    is_enter_default = true,
                    callback = function()
                        if self.active_details_dialog then
                            UIManager:close(self.active_details_dialog)
                        end
                        self.active_details_dialog = nil
                    end,
                }
            }
        }
    end

    if is_truncated then
        table.insert(buttons, 1, {
            {
                text           = self.loc:t("read_more") or "Read More",
                keep_menu_open = true,
                callback       = function()
                    local TextViewer = require("ui/widget/textviewer")
                    local viewer = TextViewer:new{
                        modal     = true,
                        title     = ev.chapter or "",
                        text      = event_text,
                        text_type = "book_info",
                    }
                    UIManager:show(viewer)
                end,
            }
        })
    end

    self.active_details_dialog = ButtonDialog:new{
        modal          = true,
        _added_widgets = { vg },
        buttons        = buttons,
    }
    UIManager:show(self.active_details_dialog)
end

function M:showHistoricalFigureDetails(fig, opts)
    if shouldUseBottomPopup(self, opts) then
        showBottomPopup(self, fig, opts)
        return
    end
    local metrics = self:calculatePopupFontMetrics(fig)
    local fs = metrics.fs
    local fs_small = metrics.fs_small
    local border_window = (Size.border and Size.border.window) or 1
    local padding_button = (Size.padding and Size.padding.button) or 10
    local padding_default = (Size.padding and Size.padding.default) or 10
    local margin_default = (Size.margin and Size.margin.default) or 5

    local dialog_width = math.floor(math.min(Screen:getWidth(), Screen:getHeight()) * 0.9)
    local buttontable_width = dialog_width - 2 * border_window - 2 * padding_button
    local title_group_width = buttontable_width - 2 * (padding_default + margin_default)

    local align = self:isRTL() and "right" or "left"
    local vg_components = { align = align }

    -- 1. Bold Name (no label)
    table.insert(vg_components, TextBoxWidget:new{
        text = fig.name or "???",
        face = Font:getFace("cfont", fs),
        width = title_group_width,
        bold = true,
        alignment = align,
    })

    -- 2. Biography/Description (no label)
    local bio = self:resolveDescriptionForPage(fig)
    if not bio or bio == "" or bio == "---" then
        local first_hist = fig.history and fig.history[1]
        bio = (first_hist and (first_hist.biography or first_hist.description))
            or fig.biography or fig.description
            or self.loc:t("msg_no_bio") or "No biography available."
    end
    local display_bio = bio
    local is_truncated = false
    if bio and bio ~= "" then
        display_bio, is_truncated = _getTruncatedText(bio, 450, 500)
        if is_truncated then
            local last_space = display_bio:match("^.*()%s")
            if last_space then
                display_bio = display_bio:sub(1, last_space - 1)
            end
            display_bio = display_bio .. " ..."
        end
        table.insert(vg_components, VerticalSpan:new{ width = math.max(6, math.floor(fs * 0.3)) })
        table.insert(vg_components, TextBoxWidget:new{
            text = display_bio,
            face = Font:getFace("cfont", fs),
            width = title_group_width,
            alignment = align,
        })
    end

    local vg = VerticalGroup:new(vg_components)
    vg.not_focusable = true

    local linked_enabled = self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.linked_entries_enabled ~= false
    local related = linked_enabled and self:findRelatedEntities(bio, fig.name, fig) or {}
    local mentions_enabled = self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.mentions_enabled ~= false
    
    local evolution_enabled = self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.evolution_enabled ~= false
    local has_evo = evolution_enabled and (((self.hasEntityEvolution and self:hasEntityEvolution(fig)))
                    or (fig.states and #fig.states > 1) or (fig.history and #fig.history > 1))

    local action_btns = {}
    if has_evo and self.showPastEvolution then
        table.insert(action_btns, {
            text = self.loc:t("past_evolution") or "Story Arc",
            callback = function()
                if self.active_details_dialog then
                    UIManager:close(self.active_details_dialog)
                    self.active_details_dialog = nil
                end
                UIManager:nextTick(function()
                    self:showPastEvolution(fig)
                end)
            end,
        })
    end
    if #related > 0 then
        table.insert(action_btns, {
            text = self.loc:t("linked_entries") or "Linked Entries",
            callback = function()
                if self.active_details_dialog then UIManager:close(self.active_details_dialog); self.active_details_dialog = nil end
                self:showRelatedEntities(related, opts, fig)
            end,
        })
    end
    if mentions_enabled then
        table.insert(action_btns, {
            text = self.loc:t("find_mentions") or "Find Mentions",
            callback = function()
                if self.active_details_dialog then UIManager:close(self.active_details_dialog); self.active_details_dialog = nil end
                self:showMentionsForEntity(fig)
            end,
        })
    end
    if opts and opts.restore_menu_cb then
        table.insert(action_btns, {
            text = self.loc:t("highlight_menu_btn") or "Highlight Menu",
            callback = function()
                if self.active_details_dialog then UIManager:close(self.active_details_dialog); self.active_details_dialog = nil end
                opts.restore_menu_cb()
            end,
        })
    end

    local close_btn = {
        text = self.loc:t("close") or "Close",
        is_enter_default = true,
        callback = function()
            if self.active_details_dialog then UIManager:close(self.active_details_dialog) end
            self.active_details_dialog = nil
        end,
    }

    local read_more_btn = nil
    if is_truncated then
        read_more_btn = {
            text = self.loc:t("read_more") or "Read More",
            keep_menu_open = true,
            callback = function()
                local TextViewer = require("ui/widget/textviewer")
                local full_text = fig.name .. "\n\n" .. bio
                local viewer = TextViewer:new{
                    modal = true,
                    title = fig.name,
                    text = full_text,
                }
                UIManager:show(viewer)
            end
        }
    end

    local buttons = formatDialogButtons(action_btns, close_btn, read_more_btn)

    self.active_details_dialog = ButtonDialog:new{
        modal = true,
        _added_widgets = { vg },
        buttons = buttons,
    }
    UIManager:show(self.active_details_dialog)
end

function M:showHistoricalFigures()
    if not self:hasXRayData() then
        self:_promptNoDataFetch()
        return
    end
    if not self.historical_figures or #self.historical_figures == 0 then 
        local InfoMessage = require("ui/widget/infomessage")
        UIManager:show(InfoMessage:new{ text = self.loc:t("no_historical_data"), timeout = 3 })
        return 
    end

    if self.hf_menu then
        UIManager:close(self.hf_menu)
        self.hf_menu = nil
    end

    local EntityListOverlay = require(plugin_path .. "xray_entity_list")
    self.hf_menu = EntityListOverlay:new{
        plugin = self,
        mode = "historical_figures",
        raw_items = self.historical_figures,
    }
    UIManager:show(self.hf_menu, "ui")
end

function M:showQuickXRayMenu()
    if self.ai_helper and type(self.ai_helper.hasApiKey) == "function" and not self.ai_helper:hasApiKey() and not (self.book_data and self.book_data.characters and #self.book_data.characters > 0) then
        self:showWelcomeCard()
        return
    end
    self:showFullXRayMenu()
end

function M:showFullXRayMenu()
    if self.openReaderMenuToPath and self.ui and self.ui.menu then
        self:openReaderMenuToPath("xray")
        return
    end
    self:showFullXRayMenuStandalone()
end

function M:showFullXRayMenuStandalone()
    if self.xray_menu then UIManager:close(self.xray_menu); self.xray_menu = nil end
    self.xray_menu = self:newMenu("xray_menu", { 
        title = self.loc:t("menu_xray") or "X-Ray", 
        item_table = self:getSubMenuItems(), 
        is_borderless = true, 
        width = Screen:getWidth(), 
        height = Screen:getHeight() 
    })
    UIManager:show(self.xray_menu) 
end

-- Onboarding and API Key Management extracted to xray_onboarding.lua

function M:findCharacterByName(word)
    if not self.characters or not word then return nil end
    local word_lower = string.lower(word)
    for _, char in ipairs(self.characters) do
        local name_lower = string.lower(char.name or "")
        if name_lower == word_lower or string.find(name_lower, word_lower, 1, true) then
            return char
        end
        -- Also check aliases if primary name doesn't match
        if char.aliases and type(char.aliases) == "table" then
            for _, alias in ipairs(char.aliases) do
                local alias_lower = string.lower(tostring(alias))
                if alias_lower == word_lower or string.find(alias_lower, word_lower, 1, true) then
                    return char
                end
            end
        end
    end
    return nil
end

function M:showCharacterSearch()
    if not self.characters or #self.characters == 0 then UIManager:show(InfoMessage:new{ text = self.loc:t("no_character_data"), timeout = 3 }); return end
    local InputDialog = require("ui/widget/inputdialog")
    local input_dialog
    input_dialog = InputDialog:new{ title = self.loc:t("search_character_title"), input = "", input_hint = self.loc:t("search_hint"), buttons = {{{ text = self.loc:t("cancel"), callback = function() UIManager:close(input_dialog) end }, { text = self.loc:t("search_button"), is_enter_default = true, callback = function() local search_text = input_dialog:getInputText(); UIManager:close(input_dialog); if search_text and #search_text > 0 then local found_char = self:findCharacterByName(search_text); if found_char then self:showCharacterDetails(found_char, { source = "menu" }) else UIManager:show(InfoMessage:new{ text = self.loc:t("character_not_found", search_text), timeout = 3 }) end end end }}} }
    UIManager:show(input_dialog); input_dialog:onShowKeyboard()
end

function M:showConfigSummary()
    local primary = (self.ai_helper and self.ai_helper.settings) and self.ai_helper.settings.primary_ai or nil
    local secondary = (self.ai_helper and self.ai_helper.settings) and self.ai_helper.settings.secondary_ai or nil
    
    local primary_label = self.loc:t("menu_primary_ai_model") or "Primary AI Model"
    local secondary_label = self.loc:t("menu_secondary_ai_model") or "Secondary AI Model"
    local default_label = self.loc:t("config_default_gemini") or "Default (Gemini)"
    local set_label = self.loc:t("config_status_set") or "SET"
    local not_set_label = self.loc:t("config_status_not_set") or "NOT SET"

    local lines = {}
    table.insert(lines, "[B]AI Model Configurations[/B]")
    
    table.insert(lines, "• [B]" .. primary_label .. "[/B]:")
    if primary then
        table.insert(lines, "  " .. primary.provider .. " (" .. primary.model .. ")")
    else
        table.insert(lines, "  " .. default_label)
    end
    
    table.insert(lines, "• [B]" .. secondary_label .. "[/B]:")
    if secondary then
        table.insert(lines, "  " .. secondary.provider .. " (" .. secondary.model .. ")")
    else
        table.insert(lines, "  " .. default_label)
    end
    
    table.insert(lines, "")
    table.insert(lines, "[B]API Key Credentials[/B]")
    
    local function add(p, n)
        local c = self.ai_helper.providers[p]
        local is_set = c and c.api_key and #c.api_key > 0
        local status = is_set and "[B]" .. set_label .. "[/B]" or not_set_label
        table.insert(lines, "• " .. n .. ": " .. status)
    end
    add("gemini", "Google Gemini")
    add("chatgpt", "ChatGPT")
    add("deepseek", "DeepSeek")
    add("claude", "Anthropic Claude")
    add("custom1", "Custom API 1")
    add("custom2", "Custom API 2")

    local XRaySettingsCard = require("xray_settings_card")
    XRaySettingsCard.showAbout(self, self.loc:t("menu_view_config") or "View All Config Values", table.concat(lines, "\n"))
end

function M:showReasoningEffortSettings()
    XRaySettingsCard.show(self, {
        title = self.loc:t("menu_reasoning_effort") or "AI Model Reasoning Effort",
        description = "Controls internal 'thinking' time for supported reasoning models.",
        options = {
            { text = self.loc:t("reasoning_unset") or "Unset (Default)", value = "none" },
            { text = self.loc:t("reasoning_low") or "Low", value = "low" },
            { text = self.loc:t("reasoning_medium") or "Medium", value = "medium" },
            { text = self.loc:t("reasoning_high") or "High", value = "high" },
        },
        get_current_func = function()
            return self.ai_helper.settings and self.ai_helper.settings.reasoning_effort or "none"
        end,
        save_func = function(val)
            if val == "none" then
                self.ai_helper.settings.reasoning_effort = nil
                self.ai_helper:saveSettings()
            else
                self.ai_helper:saveSettings({ reasoning_effort = val })
            end
        end,
        about_text = self.loc:t("reasoning_about") or "Controls [B]thinking[/B] depth for reasoning models:\n\n• Unset: No specific instruction sent; model uses its internal defaults.\n• Low: Fast, economical extraction for simple books.\n• Medium: Balanced depth for most narratives.\n• High: Detailed analysis for complex character webs.\n\n[B]Applies to:[/B] GPT-5.x (o1/o3/gpt-5), Claude (sonnet/opus/haiku), and Gemini 2.5+.\n\n[B]Note:[/B] DeepSeek V4 reasons [B]inherently[/B] — this setting has no effect on it.",
    })
end

function M:showUnitConversionDirectionSettings()
    XRaySettingsCard.show(self, {
        title = self.loc:t("unit_conv_direction") or "Conversion Direction",
        description = self.loc:t("unit_conv_direction_desc") or "Select target direction for unit conversions:",
        options = {
            { text = self.loc:t("unit_conv_direction_auto") or "Auto (Follow Device)", value = "auto" },
            { text = self.loc:t("unit_conv_direction_metric") or "To Metric", value = "to_metric" },
            { text = self.loc:t("unit_conv_direction_imperial") or "To Imperial", value = "to_imperial" },
        },
        get_current_func = function()
            return self.ai_helper.settings.unit_conversion_direction or "auto"
        end,
        save_func = function(val)
            self.ai_helper:saveSettings({ unit_conversion_direction = val })
        end,
        on_close = function()
            if self.scanBookForUnits then self:scanBookForUnits() end
        end,
        about_text = self.loc:t("unit_conv_direction_about") or "Unit conversion direction determines how measurements in books (e.g. lengths, weight, temperatures) are translated:\n\n• [B]Auto (Follow Device):[/B] Automatically converts based on the 'Dimension units' system setting of your device.\n• [B]To Metric:[/B] Always converts Imperial units (e.g. miles, Fahrenheit) to Metric equivalents (e.g. kilometers, Celsius).\n• [B]To Imperial:[/B] Always converts Metric units to Imperial equivalents.",
    })
end

function M:showBetaChannelSettings()
    local enabled_text = self.loc:t("beta_enabled") or "Beta Channel Enabled"
    local disabled_text = self.loc:t("beta_disabled") or "Stable Channel (Recommended)"
    XRaySettingsCard.show(self, {
        title = self.loc:t("menu_beta_channel") or "Beta Channel Settings",
        description = self.loc:t("beta_preference_desc") or "Select your update channel preference:",
        options = {
            { text = enabled_text, value = true },
            { text = disabled_text, value = false },
        },
        get_current_func = function()
            return self.ai_helper.settings.beta_channel_enabled == true
        end,
        save_func = function(val)
            self.ai_helper:saveSettings({ beta_channel_enabled = val })
        end,
        about_text = self.loc:t("beta_channel_desc") or "The beta channel allows you to receive pre-release versions of the X-Ray plugin. These versions include the latest features and bug fixes but may be [B]less stable[/B] than the regular release.",
    })
end

-- Series context UI extracted to xray_series_ui.lua

function M:handleUnitConversionLookup(text)
    local settings = self.ai_helper and self.ai_helper.settings or {}
    local direction = settings.unit_conversion_direction or "auto"
    if direction == "auto" then
        direction = xray_units.getDefaultDirection()
    end
    local enabled_cats = {
        length = settings.unit_cat_length ~= false,
        weight = settings.unit_cat_weight ~= false,
        temp = settings.unit_cat_temp ~= false,
        volume = settings.unit_cat_volume ~= false,
        speed = settings.unit_cat_speed ~= false,
        area = settings.unit_cat_area ~= false,
    }
    local lang = self.loc and self.loc:getLanguage() or "en"
    local matches = xray_units.detectMeasurements(text, direction, enabled_cats, lang)
    if matches and #matches > 0 then
        local match = matches[1]
        local entity = {
            name = match.original,
            description = match.original .. " = " .. match.converted,
            category = "Unit Conversion",
            role = match.category:upper(),
            is_conversion = true
        }
        showBottomPopup(self, entity)
        return true
    end
    return false
end

-- Manage Series UI extracted to xray_series_ui.lua

return M
