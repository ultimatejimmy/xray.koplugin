-- X-Ray UI and Menu Functions
local util = require("util")

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

local M = {}

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
    return fl:find("cjk") or fl:find("han") or fl:find("wenquanyi")
        or fl:find("noto.*jp") or fl:find("noto.*sc") or fl:find("noto.*tc")
        or fl:find("noto.*kr") or fl:find("source han") or fl:find("adobe")
        or fl:find("kozuka") or fl:find("hiragino") or fl:find("meiryo")
        or fl:find("yugothic") or fl:find("simhei") or fl:find("simsun")
        or fl:find("mingliu") or fl:find("kaiti") or fl:find("fangzheng")
end

local function _getPopupFontSize(plugin)
    local size
    if plugin and plugin.ui and plugin.ui.font and plugin.ui.font.configurable then
        size = plugin.ui.font.configurable.font_size
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

local XRayBottomPopup = InputContainer:extend{
    entity      = nil,
    plugin      = nil,
    font_size   = DEFAULT_POPUP_FONT_SIZE,
    margin_size = 28,   -- default symmetric horizontal margin (px)
}

function XRayBottomPopup:init()
    local Device = require("device")
    self.focused_btn_index = self.focused_btn_index or 1

    self.key_events = {
        PrevButton = {
            { "Left" },
            { "Up" },
        },
        NextButton = {
            { "Right" },
            { "Down" },
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
    }
    if Device.hasKeys and Device:hasKeys() and Device.input and Device.input.group and Device.input.group.Back then
        table.insert(self.key_events.Close, { Device.input.group.Back })
    end

    self:_rebuild()
end

function XRayBottomPopup:_rebuild()
    if self._font_fallback then
        self:_buildContent()
        return
    end

    local ok, err = pcall(function() self:_buildContent() end)
    if not ok then
        if self.plugin and self.plugin.log then
            self.plugin:log("XRayPlugin: XRayBottomPopup:_rebuild failed (" .. tostring(err) .. "), retrying with cfont fallback")
        end
        self._font_fallback = true
        local ok2, err2 = pcall(function() self:_buildContent() end)
        if not ok2 and self.plugin and self.plugin.log then
            self.plugin:log("XRayPlugin: XRayBottomPopup fallback rebuild also failed: " .. tostring(err2))
        end
        self._font_fallback = nil
    end
end

function XRayBottomPopup:_buildContent()
    local sw = Screen:getWidth()
    local sh = Screen:getHeight()
    local fs  = self.font_size
    local pad = self.margin_size  -- symmetric left/right/top/bottom

    -- Uniform gap between every block
    local gap = math.max(1, math.floor(fs * 0.08))

    local inner_w = sw - pad * 2

    local e = self.entity or {}

    local doc_family
    if not self._font_fallback then
        if self.plugin and self.plugin.ui and self.plugin.ui.font then
            doc_family = self.plugin.ui.font.font_face
        end
        if not doc_family and G_reader_settings then
            doc_family = G_reader_settings:readSetting("cre_font_family")
        end
    end
    local Device = require("device")

    -- Check if entity text contains CJK characters
    local text_has_cjk = false
    if e.name and _textHasCJK(tostring(e.name)) then
        text_has_cjk = true
    elseif e.description and _textHasCJK(tostring(e.description)) then
        text_has_cjk = true
    elseif e.biography and _textHasCJK(tostring(e.biography)) then
        text_has_cjk = true
    elseif e.definition and _textHasCJK(tostring(e.definition)) then
        text_has_cjk = true
    end

    -- If doc_family is CJK or the text contains CJK, apply a smaller scaling factor
    local is_cjk = _isCJKFontFamily(doc_family) or text_has_cjk
    if is_cjk then
        fs = math.max(12, math.min(math.floor(fs * (0.55 / 0.75)), 20))
    else
        fs = math.max(12, math.min(fs, 20))
    end

    local function getFontSafe(preferred_family, size)
        if self._font_fallback or is_cjk or _isCJKFontFamily(preferred_family) then
            return Font:getFace("cfont", size)
        end
        if preferred_family and preferred_family ~= "" then
            local ok, credoc = pcall(require, "document/credocument")
            if ok and credoc and credoc.engineInit then
                local ok2, cre = pcall(credoc.engineInit, credoc)
                if ok2 and cre and cre.getFontFaceFilenameAndFaceIndex then
                    local filename, faceindex = cre.getFontFaceFilenameAndFaceIndex(preferred_family)
                    if not filename then
                        filename, faceindex = cre.getFontFaceFilenameAndFaceIndex(preferred_family, nil, true)
                    end
                    if filename then
                        local face_ok, face = pcall(Font.getFace, Font, filename, size, faceindex)
                        if face_ok and face then return face end
                    end
                end
            end
        end
        return Font:getFace("cfont", size)
    end

    -- Fonts
    local face_normal = getFontSafe(doc_family, fs)
    local face_btn    = Font:getFace("cfont", math.max(12, fs - 2))

    local fs_small    = math.max(12, fs - 4)
    local face_small_normal = getFontSafe(doc_family, fs_small)

    local function make_text(text, face, align, is_bold)
        return TextBoxWidget:new{
            text       = text,
            face       = face,
            width      = inner_w,
            alignment  = align or ((self.plugin and self.plugin:isRTL()) and "right" or "justify"),
            justified  = true,
            bold       = is_bold,
        }
    end

    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan  = require("ui/widget/horizontalspan")
    local btn_padding_h   = (Size.padding and Size.padding.large) or 12
    local btn_padding_v   = (Size.padding and Size.padding.small) or 4

    local function make_btn(label, cb, is_focused)
        return Button:new{
            text            = label,
            text_font_face  = "cfont",
            text_font_size  = math.max(14, fs - 2),
            text_font_bold  = true,
            padding_h       = btn_padding_h,
            padding_v       = btn_padding_v,
            margin          = 0,
            radius          = 4,
            bordersize      = 2,
            background      = nil,
            callback        = cb,
        }
    end

    local function get_loc_t(key, default)
        return (self.plugin and self.plugin.loc and self.plugin.loc:t(key)) or default
    end

    -- ── content ──────────────────────────────────────────────────────────────
    local align = (self.plugin and self.plugin:isRTL()) and "right" or "left"
    local vg_components = { align = align }

    -- 1. Name (bold, justified)
    table.insert(vg_components, make_text(tostring(e.name or "?"), face_normal, "justify", true))

    local has_metadata = false

    -- 2. Aliases
    local aliases_str
    if e.aliases then
        local kept = {}
        local name_lower = (e.name or ""):lower()
        local src = (type(e.aliases) == "table") and e.aliases
                 or (type(e.aliases) == "string") and { e.aliases } or {}
        for _, a in ipairs(src) do
            local al = tostring(a):match("^%s*(.-)%s*$")
            if #al > 1 and not name_lower:find(al:lower(), 1, true) then
                table.insert(kept, al)
            end
        end
        if #kept > 0 then aliases_str = table.concat(kept, ", ") end
    end
    if aliases_str then
        table.insert(vg_components, VerticalSpan:new{ width = gap })
        table.insert(vg_components, make_text(get_loc_t("label_aliases", "ALIASES") .. ": " .. aliases_str, face_small_normal, "justify"))
        has_metadata = true
    end

    -- 3. Combined non-description attributes (Role, Occupation, Gender)
    local attrs = {}
    if e.role and e.role ~= "" and e.role ~= "---" then
        table.insert(attrs, e.role)
    end
    if e.occupation and e.occupation ~= "" and e.occupation ~= "---" then
        table.insert(attrs, e.occupation)
    end
    if e.gender and e.gender ~= "" and e.gender ~= "---" then
        table.insert(attrs, e.gender)
    end

    if #attrs > 0 then
        table.insert(vg_components, VerticalSpan:new{ width = gap })
        table.insert(vg_components, make_text(table.concat(attrs, " | "), face_small_normal, "justify"))
        has_metadata = true
    end

    -- 6. AI Reasoning
    if e.ai_reasoning and e.ai_reasoning ~= "" then
        table.insert(vg_components, VerticalSpan:new{ width = gap })
        table.insert(vg_components, make_text("[" .. get_loc_t("label_reasoning", "AI REASONING") .. "]\n" .. e.ai_reasoning, face_small_normal, "justify"))
        has_metadata = true
    end

    -- 7. Description (with Preview/Read More truncation)
    local desc_str = tostring(e.description or e.biography or e.definition or e.desc or "")
    desc_str = desc_str:match("^%s*(.-)%s*$")
    local display_desc = desc_str
    local is_truncated = false
    if desc_str ~= "" then
        display_desc, is_truncated = _getTruncatedText(desc_str, 350, 400)
        if is_truncated then
            local last_space = display_desc:match("^.*()%s")
            if last_space then
                display_desc = display_desc:sub(1, last_space - 1)
            end
            display_desc = display_desc .. " ..."
        end
        local desc_gap = has_metadata and fs or gap
        table.insert(vg_components, VerticalSpan:new{ width = desc_gap })
        table.insert(vg_components, make_text(display_desc, face_normal, "justify"))
    end

    -- ── buttons ──────────────────────────────────────────────────────────────
    local plugin = self.plugin
    local linked_enabled = plugin and plugin.ai_helper and plugin.ai_helper.settings and plugin.ai_helper.settings.linked_entries_enabled ~= false
    local related = {}
    if linked_enabled and plugin and plugin.findRelatedEntities then
        related = plugin:findRelatedEntities(desc_str or "", e.name) or {}
    end
    local mentions_enabled = plugin and plugin.ai_helper and plugin.ai_helper.settings and plugin.ai_helper.settings.mentions_enabled ~= false

    local raw_button_defs = {}

    -- A. Read More button (if truncated)
    if is_truncated then
        table.insert(raw_button_defs, {
            label = get_loc_t("read_more", "Read More"),
            cb = function()
                UIManager:close(self)
                local TextViewer = require("ui/widget/textviewer")
                local full_text_for_viewer = tostring(e.name or "?") .. "\n"
                if #attrs > 0 then
                    full_text_for_viewer = full_text_for_viewer .. table.concat(attrs, " | ") .. "\n"
                end
                if aliases_str then
                    full_text_for_viewer = full_text_for_viewer .. get_loc_t("label_aliases", "Aliases") .. ": " .. aliases_str .. "\n"
                end
                full_text_for_viewer = full_text_for_viewer .. "\n" .. desc_str
                if e.ai_reasoning and e.ai_reasoning ~= "" then
                    full_text_for_viewer = full_text_for_viewer .. "\n\n[" .. get_loc_t("label_reasoning", "AI Reasoning") .. "]\n" .. e.ai_reasoning
                end
                local viewer = TextViewer:new{
                    title = e.name,
                    text = full_text_for_viewer,
                }
                UIManager:show(viewer)
            end,
        })
    end

    -- B. Linked Entries button
    if #related > 0 and not e.is_conversion then
        table.insert(raw_button_defs, {
            label = get_loc_t("linked_entries", "Linked Entries"),
            cb = function()
                UIManager:close(self)
                if plugin and plugin.showRelatedEntities then
                    plugin:showRelatedEntities(related, nil, e)
                end
            end,
        })
    end

    -- C. Find Mentions button
    if mentions_enabled and not e.is_timeline and not e.is_conversion then
        table.insert(raw_button_defs, {
            label = get_loc_t("find_mentions", "Find Mentions"),
            cb = function()
                UIManager:close(self)
                if plugin then
                    if     plugin.showMentionsForEntity then plugin:showMentionsForEntity(e)
                    elseif plugin.findMentions          then plugin:findMentions(e)
                    elseif plugin.showMentions          then plugin:showMentions(e)
                    end
                end
            end,
        })
    end

    if #raw_button_defs > 0 then
        if self.focused_btn_index > #raw_button_defs then self.focused_btn_index = #raw_button_defs end
        if self.focused_btn_index < 1 then self.focused_btn_index = 1 end
    else
        self.focused_btn_index = 1
    end

    self.active_button_defs = raw_button_defs
    local active_btns = {}
    for idx, bdef in ipairs(raw_button_defs) do
        local is_focused = (idx == self.focused_btn_index)
        local btn = make_btn(bdef.label, bdef.cb, is_focused)
        table.insert(active_btns, btn)
    end

    -- Layout buttons row
    local btn_row
    if #active_btns > 0 then
        local row_h = 0
        for _, btn in ipairs(active_btns) do
            row_h = math.max(row_h, btn:getSize().h)
        end
        if #active_btns == 1 then
            btn_row = LeftContainer:new{
                dimen = Geom:new{ w = inner_w, h = row_h },
                active_btns[1],
            }
        elseif #active_btns == 2 then
            btn_row = HorizontalGroup:new{
                align = "center",
                active_btns[1],
                HorizontalSpan:new{ width = math.max(16, gap * 3) },
                active_btns[2],
            }
        else
            local btn_components = { align = "center" }
            for i, btn in ipairs(active_btns) do
                if i > 1 then
                    table.insert(btn_components, HorizontalSpan:new{ width = math.max(12, gap * 2) })
                end
                table.insert(btn_components, btn)
            end
            btn_row = HorizontalGroup:new(btn_components)
        end
    end

    if btn_row then
        table.insert(vg_components, VerticalSpan:new{ width = math.max(18, gap * 4) })
        table.insert(vg_components, btn_row)
    end

    local vg = VerticalGroup:new(vg_components)

    -- ── frame: line flush on top, then padded content ─────────────────────
    local line_h    = (Size.line and Size.line.thick) or 2
    local separator = LineWidget:new{
        dimen      = Geom:new{ w = sw, h = line_h },
        background = Blitbuffer.COLOR_DARK_GRAY,
    }

    local pad_top_px    = math.floor(fs * 0.55)
    local pad_bottom_px = math.floor(fs * 0.85)
    if Device:isAndroid() then
        local safe_bottom = 20
        if Screen.scaleBySize then
            safe_bottom = Screen:scaleBySize(20)
        end
        pad_bottom_px = pad_bottom_px + safe_bottom
    end

    local outer_vg = VerticalGroup:new{
        align = "left",
        separator,
        FrameContainer:new{
            background     = Blitbuffer.COLOR_WHITE,
            bordersize     = 0,
            radius         = 0,
            padding_top    = pad_top_px,
            padding_bottom = pad_bottom_px,
            padding_left   = pad,
            padding_right  = pad,
            width          = sw,
            vg,
        }
    }

    self.popup_frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        radius     = 0,
        padding    = 0,
        width      = sw,
        outer_vg,
    }

    -- ── positioning ───────────────────────────────────────────────────────
    local popup_h = self.popup_frame:getSize().h
    local popup_y = sh - popup_h

    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }

    self.ges_events = {
        TapOutside = {
            GestureRange:new{
                ges     = "tap",
                range   = Geom:new{ x = 0, y = 0, w = sw, h = popup_y },
            },
        },
    }

    local BottomContainer = require("ui/widget/container/bottomcontainer")
    self[1] = BottomContainer:new{
        dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh },
        self.popup_frame,
    }
end

function XRayBottomPopup:onPrevButton()
    local count = self.active_button_defs and #self.active_button_defs or 0
    if count == 0 then return true end
    if self.focused_btn_index > 1 then
        self.focused_btn_index = self.focused_btn_index - 1
    else
        self.focused_btn_index = count
    end
    self:_rebuild()
    UIManager:setDirty(self, "ui")
    return true
end

function XRayBottomPopup:onNextButton()
    local count = self.active_button_defs and #self.active_button_defs or 0
    if count == 0 then return true end
    if self.focused_btn_index < count then
        self.focused_btn_index = self.focused_btn_index + 1
    else
        self.focused_btn_index = 1
    end
    self:_rebuild()
    UIManager:setDirty(self, "ui")
    return true
end

function XRayBottomPopup:onSelect()
    if self.active_button_defs and #self.active_button_defs > 0 then
        local def = self.active_button_defs[self.focused_btn_index or 1]
        if def and def.cb then
            def.cb()
            return true
        end
    end
    return true
end

function XRayBottomPopup:onTapOutside()
    UIManager:close(self)
    return true
end

function XRayBottomPopup:onClose()
    UIManager:close(self)
    return true
end

function XRayBottomPopup:onShow()
    UIManager:setDirty(self, "ui")
    return true
end

function XRayBottomPopup:onCloseWidget()
    if self.plugin then
        self.plugin.active_details_dialog = nil
    end
    UIManager:setDirty(nil, "ui")
end

local function showBottomPopup(plugin, entity)
    if not entity then return end
    if plugin.active_details_dialog then
        UIManager:close(plugin.active_details_dialog)
        plugin.active_details_dialog = nil
    end

    local normalized = {}
    for k, v in pairs(entity) do normalized[k] = v end

    if plugin.resolveDescriptionForPage then
        local resolved = plugin:resolveDescriptionForPage(entity)
        if resolved and resolved ~= "---" then
            normalized.description = resolved
        end
    end
    if not normalized.description and normalized.biography then
        normalized.description = normalized.biography
    end
    if not normalized.description and normalized.definition then
        normalized.description = normalized.definition
    end
    if not normalized.role and normalized.category and normalized.category ~= "" then
        normalized.role = normalized.category
    end

    local fs  = _getPopupFontSize(plugin)
    local pad = 28  -- default
    if G_reader_settings then
        pad = G_reader_settings:readSetting("xray_popup_margin") or pad
    end
    local popup = XRayBottomPopup:new{
        modal       = true,
        entity      = normalized,
        plugin      = plugin,
        font_size   = fs,
        margin_size = pad,
    }
    plugin.active_details_dialog = popup
    UIManager:show(popup)
end

local function shouldUseBottomPopup(plugin, opts)
    local settings = plugin.ai_helper and plugin.ai_helper.settings
    if not settings then return false end

    -- Migrate old settings if they exist and booleans are not set yet
    if settings.entity_ui_mode and settings.ui_popup_intext == nil and settings.ui_popup_menu == nil then
        local mode = settings.entity_ui_mode
        local intext = (mode == "both" or mode == "in_text_only")
        local menu = (mode == "both" or mode == "menu_only")
        settings.ui_popup_intext = intext
        settings.ui_popup_menu = menu
        settings.entity_ui_mode = nil
        pcall(function() plugin.ai_helper:saveSettings({
            ui_popup_intext = intext,
            ui_popup_menu = menu
        }) end)
    end

    local ui_popup_intext = settings.ui_popup_intext
    if ui_popup_intext == nil then ui_popup_intext = true end
    local ui_popup_menu = settings.ui_popup_menu
    if ui_popup_menu == nil then ui_popup_menu = false end

    if opts and opts.source == "in_text" then
        return ui_popup_intext
    elseif opts and opts.source == "menu" then
        return ui_popup_menu
    end
    return ui_popup_intext
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
        supported = { en=1, de=1, fr=1, ru=1, zh_CN=1, ja=1, tr=1, pt_br=1, es=1, uk=1, hu=1, nl=1, pl=1, id=1, ar=1, sr=1 }
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
                if book_lang:lower():find("zh") then lang = "zh_CN"
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

    menu.key_events.PrevPage = menu.key_events.PrevPage or {}
    table.insert(menu.key_events.PrevPage, { "PageUp" })
    table.insert(menu.key_events.PrevPage, { "[" })
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
    
    if self.ai_helper then
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
    if book_lang:find("zh") then lang = "zh_CN"
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
        title = self.loc:t("lang_mismatch_title") or "Language Mismatch",
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

function M:findRelatedEntities(text, exclude_name)
    if not text or text == "" then return {} end
    local related = {}
    local seen = {}
    if exclude_name then seen[exclude_name:lower()] = true end

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
            local name = item.name
            if name and not seen[name:lower()] then
                local found = false

                -- Strategy 1: Full name match
                if termFound(name) then
                    found = true
                end

                -- Strategy 2: Aliases (skip generic and honorific-only aliases)
                if not found and item.aliases then
                    for _, alias in ipairs(item.aliases) do
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
        showBottomPopup(self, character)
        return
    end
    local base_fs = _getPopupFontSize(self)
    local doc_family
    if self.ui and self.ui.font then
        doc_family = self.ui.font.font_face
    end
    if not doc_family and G_reader_settings then
        doc_family = G_reader_settings:readSetting("cre_font_family")
    end

    local text_has_cjk = false
    if character.name and _textHasCJK(tostring(character.name)) then
        text_has_cjk = true
    elseif character.description and _textHasCJK(tostring(character.description)) then
        text_has_cjk = true
    elseif character.biography and _textHasCJK(tostring(character.biography)) then
        text_has_cjk = true
    elseif character.definition and _textHasCJK(tostring(character.definition)) then
        text_has_cjk = true
    end

    local is_cjk = _isCJKFontFamily(doc_family) or text_has_cjk
    local fs
    if is_cjk then
        fs = math.max(12, math.min(math.floor(base_fs * 0.75), 18))
    else
        fs = math.max(12, math.min(base_fs, 20))
    end
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
    if character.aliases and type(character.aliases) == "table" and #character.aliases > 0 then
        local name_lower = (character.name or ""):lower()
        for _, alias in ipairs(character.aliases) do
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
            face = Font:getFace("cfont", math.max(12, fs - 4)),
            width = title_group_width,
            alignment = align,
        })
    end

    -- 3. Combined attributes line (smaller, no label)
    local attrs = {}
    if character.role and character.role ~= "" and character.role ~= "---" then
        table.insert(attrs, character.role)
    end
    if character.occupation and character.occupation ~= "" and character.occupation ~= "---" then
        table.insert(attrs, character.occupation)
    end
    if character.gender and character.gender ~= "" and character.gender ~= "---" then
        table.insert(attrs, character.gender)
    end
    if #attrs > 0 then
        table.insert(vg_components, VerticalSpan:new{ width = math.max(6, math.floor(fs * 0.3)) })
        table.insert(vg_components, TextBoxWidget:new{
            text = table.concat(attrs, " | "),
            face = Font:getFace("cfont", math.max(12, fs - 4)),
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
    local resolved_desc = self:resolveDescriptionForPage(character)
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
    local related = linked_enabled and self:findRelatedEntities(resolved_desc or "", character.name) or {}
    local mentions_enabled = self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.mentions_enabled ~= false
    
    local buttons = {}
    if #related > 0 then
        buttons = {
            {
                {
                    text = self.loc:t("linked_entries") or "Linked Entries",
                    callback = function()
                        if self.active_details_dialog then UIManager:close(self.active_details_dialog); self.active_details_dialog = nil end
                        self:showRelatedEntities(related, opts, character)
                    end,
                }
            },
            {
                {
                    text = self.loc:t("find_mentions") or "Find Mentions",
                    callback = function()
                        if self.active_details_dialog then UIManager:close(self.active_details_dialog); self.active_details_dialog = nil end
                        self:showMentionsForEntity(character)
                    end,
                },
                {
                    text = self.loc:t("close") or "Close",
                    is_enter_default = true,
                    callback = function()
                        if self.active_details_dialog then UIManager:close(self.active_details_dialog) end
                        self.active_details_dialog = nil
                    end,
                }
            }
        }
        if not mentions_enabled then
            table.remove(buttons[2], 1)
        end
    else
        if mentions_enabled then
            buttons = {
                {
                    {
                        text = self.loc:t("find_mentions") or "Find Mentions",
                        callback = function()
                            if self.active_details_dialog then UIManager:close(self.active_details_dialog); self.active_details_dialog = nil end
                            self:showMentionsForEntity(character)
                        end,
                    },
                    {
                        text = self.loc:t("close") or "Close",
                        is_enter_default = true,
                        callback = function()
                            if self.active_details_dialog then UIManager:close(self.active_details_dialog) end
                            self.active_details_dialog = nil
                        end,
                    }
                }
            }
        else
            buttons = {
                {
                    {
                        text = self.loc:t("close") or "Close",
                        is_enter_default = true,
                        callback = function()
                            if self.active_details_dialog then UIManager:close(self.active_details_dialog) end
                            self.active_details_dialog = nil
                        end,
                    }
                }
            }
        end
    end

    if is_truncated then
        table.insert(buttons, 1, {
            {
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
                end
            }
        })
    end

    self.active_details_dialog = ButtonDialog:new{
        modal = true,
        _added_widgets = { vg },
        buttons = buttons,
    }
    UIManager:show(self.active_details_dialog)
end

function M:showLocationDetails(loc_item, opts)
    if shouldUseBottomPopup(self, opts) then
        showBottomPopup(self, loc_item)
        return
    end
    local base_fs = _getPopupFontSize(self)
    local doc_family
    if self.ui and self.ui.font then
        doc_family = self.ui.font.font_face
    end
    if not doc_family and G_reader_settings then
        doc_family = G_reader_settings:readSetting("cre_font_family")
    end

    local text_has_cjk = false
    if loc_item.name and _textHasCJK(tostring(loc_item.name)) then
        text_has_cjk = true
    elseif loc_item.description and _textHasCJK(tostring(loc_item.description)) then
        text_has_cjk = true
    elseif loc_item.biography and _textHasCJK(tostring(loc_item.biography)) then
        text_has_cjk = true
    elseif loc_item.definition and _textHasCJK(tostring(loc_item.definition)) then
        text_has_cjk = true
    end

    local is_cjk = _isCJKFontFamily(doc_family) or text_has_cjk
    local fs
    if is_cjk then
        fs = math.max(12, math.min(math.floor(base_fs * 0.75), 18))
    else
        fs = math.max(12, math.min(base_fs, 20))
    end
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
    if desc == "---" then desc = "" end
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
    local related = linked_enabled and self:findRelatedEntities(desc, loc_item.name) or {}
    local mentions_enabled = self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.mentions_enabled ~= false
    
    local buttons = {}
    if #related > 0 then
        buttons = {
            {
                {
                    text = self.loc:t("linked_entries") or "Linked Entries",
                    callback = function()
                        if self.active_details_dialog then UIManager:close(self.active_details_dialog); self.active_details_dialog = nil end
                        self:showRelatedEntities(related, opts, loc_item)
                    end,
                }
            },
            {
                {
                    text = self.loc:t("find_mentions") or "Find Mentions",
                    callback = function()
                        if self.active_details_dialog then UIManager:close(self.active_details_dialog); self.active_details_dialog = nil end
                        self:showMentionsForEntity(loc_item)
                    end,
                },
                {
                    text = self.loc:t("close") or "Close",
                    is_enter_default = true,
                    callback = function()
                        if self.active_details_dialog then UIManager:close(self.active_details_dialog) end
                        self.active_details_dialog = nil
                    end,
                }
            }
        }
        if not mentions_enabled then
            table.remove(buttons[2], 1)
        end
    else
        if mentions_enabled then
            buttons = {
                {
                    {
                        text = self.loc:t("find_mentions") or "Find Mentions",
                        callback = function()
                            if self.active_details_dialog then UIManager:close(self.active_details_dialog); self.active_details_dialog = nil end
                            self:showMentionsForEntity(loc_item)
                        end,
                    },
                    {
                        text = self.loc:t("close") or "Close",
                        is_enter_default = true,
                        callback = function()
                            if self.active_details_dialog then UIManager:close(self.active_details_dialog) end
                            self.active_details_dialog = nil
                        end,
                    }
                }
            }
        else
            buttons = {
                {
                    {
                        text = self.loc:t("close") or "Close",
                        is_enter_default = true,
                        callback = function()
                            if self.active_details_dialog then UIManager:close(self.active_details_dialog) end
                            self.active_details_dialog = nil
                        end,
                    }
                }
            }
        end
    end

    if is_truncated then
        table.insert(buttons, 1, {
            {
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
                end
            }
        })
    end

    self.active_details_dialog = ButtonDialog:new{
        modal = true,
        _added_widgets = { vg },
        buttons = buttons,
    }
    UIManager:show(self.active_details_dialog)
end

function M:showTermDetails(term, opts)
    if shouldUseBottomPopup(self, opts) then
        showBottomPopup(self, term)
        return
    end
    local base_fs = _getPopupFontSize(self)
    local doc_family
    if self.ui and self.ui.font then
        doc_family = self.ui.font.font_face
    end
    if not doc_family and G_reader_settings then
        doc_family = G_reader_settings:readSetting("cre_font_family")
    end

    local text_has_cjk = false
    if term.name and _textHasCJK(tostring(term.name)) then
        text_has_cjk = true
    elseif term.description and _textHasCJK(tostring(term.description)) then
        text_has_cjk = true
    elseif term.biography and _textHasCJK(tostring(term.biography)) then
        text_has_cjk = true
    elseif term.definition and _textHasCJK(tostring(term.definition)) then
        text_has_cjk = true
    end

    local is_cjk = _isCJKFontFamily(doc_family) or text_has_cjk
    local fs
    if is_cjk then
        fs = math.max(12, math.min(math.floor(base_fs * 0.75), 18))
    else
        fs = math.max(12, math.min(base_fs, 20))
    end
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
    if term.aliases and type(term.aliases) == "table" and #term.aliases > 0 then
        local name_lower = (term.name or ""):lower()
        for _, alias in ipairs(term.aliases) do
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
            face = Font:getFace("cfont", math.max(12, fs - 4)),
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
            face = Font:getFace("cfont", math.max(12, fs - 4)),
            width = title_group_width,
            alignment = align,
        })
    end

    -- 4. Definition (no label)
    local resolved_definition = term.definition
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
    local related = linked_enabled and self:findRelatedEntities(term.definition or "", term.name) or {}
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

    local buttons = {}
    if #related > 0 then
        buttons = {
            {
                {
                    text = self.loc:t("linked_entries") or "Linked Entries",
                    callback = function()
                        if self.active_details_dialog then UIManager:close(self.active_details_dialog); self.active_details_dialog = nil end
                        self:showRelatedEntities(related, opts, term)
                    end,
                }
            },
            {
                {
                    text = self.loc:t("find_mentions") or "Find Mentions",
                    callback = function()
                        if self.active_details_dialog then UIManager:close(self.active_details_dialog); self.active_details_dialog = nil end
                        self:showMentionsForEntity(term)
                    end,
                },
                {
                    text = self.loc:t("close") or "Close",
                    is_enter_default = true,
                    callback = function()
                        if self.active_details_dialog then UIManager:close(self.active_details_dialog) end
                        self.active_details_dialog = nil
                    end,
                }
            }
        }
        if not mentions_enabled then table.remove(buttons[2], 1) end
        if opts and opts.low_confidence then
            table.insert(buttons, 1, get_relookup_row())
        end
    else
        if opts and opts.low_confidence then
            buttons = { get_relookup_row() }
            if mentions_enabled then
                table.insert(buttons, {
                    {
                        text = self.loc:t("find_mentions") or "Find Mentions",
                        callback = function()
                            if self.active_details_dialog then UIManager:close(self.active_details_dialog); self.active_details_dialog = nil end
                            self:showMentionsForEntity(term)
                        end,
                    }
                })
            end
            table.insert(buttons, {
                {
                    text = self.loc:t("close") or "Close",
                    is_enter_default = true,
                    callback = function()
                        if self.active_details_dialog then UIManager:close(self.active_details_dialog) end
                        self.active_details_dialog = nil
                    end,
                }
            })
        else
            if mentions_enabled then
                buttons = {
                    {
                        {
                            text = self.loc:t("find_mentions") or "Find Mentions",
                            callback = function()
                                if self.active_details_dialog then UIManager:close(self.active_details_dialog); self.active_details_dialog = nil end
                                self:showMentionsForEntity(term)
                            end,
                        },
                        {
                            text = self.loc:t("close") or "Close",
                            is_enter_default = true,
                            callback = function()
                                if self.active_details_dialog then UIManager:close(self.active_details_dialog) end
                                self.active_details_dialog = nil
                            end,
                        }
                    }
                }
            else
                buttons = {
                    {
                        {
                            text = self.loc:t("close") or "Close",
                            is_enter_default = true,
                            callback = function()
                                if self.active_details_dialog then UIManager:close(self.active_details_dialog) end
                                self.active_details_dialog = nil
                            end,
                        }
                    }
                }
            end
        end
    end

    if is_truncated then
        table.insert(buttons, 1, {
            {
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
        })
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
    XRaySettingsCard.show(self, {
        title = self.loc:t("menu_book_mode") or "Book Type",
        description = self.loc:t("book_mode_desc") or "Select the type for this book:",
        options = {
            { text = self.loc:t("book_type_auto") or "Auto-Detect", value = "auto" },
            { text = self.loc:t("book_type_fiction") or "Fiction", value = "fiction" },
            { text = self.loc:t("book_type_nonfiction") or "Non-Fiction", value = "non_fiction" },
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
            cache.book_mode_override = mode
            if doc_file and self.cache_manager then
                self.cache_manager:asyncSaveCache(doc_file, cache)
            end
            self.book_type = (mode == "auto") and nil or mode
            UIManager:setDirty(nil, "ui")
        end,
        about_text = self.loc:t("book_type_about") or "The Book Type determines which AI extraction strategy is used.\n\n[B]• Fiction:[/B] Focuses on characters, timeline, and world-building terms (factions, spells, lore, etc.).\n[B]• Non-Fiction:[/B] Focuses on technical terms, concepts, and historical figures.\n\n[B]Auto-Detect[/B] will let the AI decide after the [B]first[/B] fetch.\n\n[B]Note:[/B] This setting is saved [B]per book[/B]. A custom choice overrides default auto-detection or global settings.",
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

function M:filterValidDuplicatePairs(list, pairs)
    if not pairs or not list then return {} end
    if not self.book_data then
        if not self.cache_manager then
            self.cache_manager = require(plugin_path .. "xray_cachemanager"):new()
        end
        self.book_data = self.cache_manager:loadCache(self.ui.document.file) or {}
    end
    local rejected_pairs = self.book_data.rejected_merge_pairs or {}
    local filtered = {}
    for _, pair in ipairs(pairs) do
        if pair.primary and pair.secondary then
            local p_name = pair.primary:lower()
            local s_name = pair.secondary:lower()
            local key = p_name < s_name and (p_name .. "|" .. s_name) or (s_name .. "|" .. p_name)
            if not rejected_pairs[key] then
                local primary_item, secondary_item
                for _, it in ipairs(list) do
                    if it.name then
                        if it.name:lower() == p_name then primary_item = it end
                        if it.name:lower() == s_name then secondary_item = it end
                    end
                end
                if primary_item and secondary_item then
                    table.insert(filtered, pair)
                end
            end
        end
    end
    return filtered
end

function M:walkDuplicatePairs(list, list_name, pairs_found)
    local InfoMessage = require("ui/widget/infomessage")
    local ButtonDialog = require("ui/widget/buttondialog")

    self:log("XRayPlugin: Walking " .. tostring(pairs_found and #pairs_found or 0) .. " duplicate pair(s) for " .. tostring(list_name))

    if not pairs_found or #pairs_found == 0 then
        UIManager:show(InfoMessage:new{
            text = self.loc:t("no_duplicates_found") or "No duplicates found.",
            timeout = 3
        })
        return
    end

    if not self.book_data then
        if not self.cache_manager then
            self.cache_manager = require(plugin_path .. "xray_cachemanager"):new()
        end
        self.book_data = self.cache_manager:loadCache(self.ui.document.file) or {}
    end

    pairs_found = self:filterValidDuplicatePairs(list, pairs_found)

    self:log("XRayPlugin: " .. tostring(#pairs_found) .. " pair(s) remain after filtering rejected/non-existent for " .. tostring(list_name))

    if #pairs_found == 0 then
        UIManager:show(InfoMessage:new{
            text = self.loc:t("no_duplicates_found") or "No duplicates found.",
            timeout = 3
        })
        return
    end

    -- Walk through pairs one at a time
    local pair_idx = 1
    local merge_count = 0

    local function saveAndRefresh()
        if merge_count == 0 then return end
        local doc_file = self.ui and self.ui.document and self.ui.document.file
        if not self.cache_manager then
            self.cache_manager = require(plugin_path .. "xray_cachemanager"):new()
        end
        if not self.book_data then
            self.book_data = (doc_file and self.cache_manager:loadCache(doc_file)) or {}
        end
        local cache = self.book_data
        if list_name == "characters" then
            cache.characters = list
        elseif list_name == "locations" then
            cache.locations = list
        end
        if doc_file and self.cache_manager then
            self.cache_manager:asyncSaveCache(doc_file, cache)
        end
        -- Clear normalized lookup caches
        for _, it in ipairs(list) do
            it._norm_name = nil
            it._norm_aliases = nil
        end
    end

    local function processNextPair()
        if pair_idx > #pairs_found then
            saveAndRefresh()
            local msg = merge_count > 0
                and self.loc:t("ai_merged_n", merge_count)
                or  (self.loc:t("no_merges_performed") or "No merges performed.")
            UIManager:show(InfoMessage:new{ text = msg, timeout = 3 })
            self:log("XRayPlugin: Duplicate walk complete. " .. tostring(merge_count) .. " merge(s) performed.")
            if list_name == "characters" then self:showCharacters()
            elseif list_name == "locations" then self:showLocations() end
            return
        end

        local pair = pairs_found[pair_idx]
        pair_idx = pair_idx + 1

        -- Validate both entries still exist (earlier merge may have removed one)
        local primary_item, secondary_item
        for _, it in ipairs(list) do
            if it.name and it.name:lower() == (pair.primary or ""):lower() then
                primary_item = it
            end
            if it.name and it.name:lower() == (pair.secondary or ""):lower() then
                secondary_item = it
            end
        end

        if not primary_item or not secondary_item then
            processNextPair()  -- skip silently
            return
        end

        local confirm_text = string.format(
            "%s\n\nKEEP:   %s\nREMOVE: %s\n\n%s: %s",
            self.loc:t("ai_merge_confirm_title") or "AI Duplicate Detected",
            pair.primary, pair.secondary,
            self.loc:t("reason") or "Reason",
            pair.reason or "Similar entries"
        )

        local confirm_dialog
        confirm_dialog = ButtonDialog:new{
            modal = true,
            title = confirm_text,
            buttons = {{
                {
                    text = self.loc:t("merge_button") or "Merge",
                    callback = function()
                        self:log("XRayPlugin: Merging duplicate pair: keep '" .. tostring(pair.primary) .. "', remove '" .. tostring(pair.secondary) .. "'")
                        UIManager:close(confirm_dialog)
                        local p_desc = primary_item.description or primary_item.biography
                        local s_desc = secondary_item.description or secondary_item.biography
                        if p_desc and s_desc then
                            local wait_msg = InfoMessage:new{ text = self.loc:t("merging_smartly") or "Merging...", timeout = 120 }
                            UIManager:show(wait_msg)
                            UIManager:scheduleIn(0.1, function()
                                coroutine.wrap(function()
                                    if self.destroyed or not self.ui or not self.ui.document then return end
                                    if self.ai_helper then self.ai_helper:setTrapWidget(wait_msg) end
                                    local ai_desc = self.ai_helper:mergeDescriptionsWithAI(p_desc, s_desc)
                                    if self.ai_helper then self.ai_helper:resetTrapWidget() end
                                    UIManager:close(wait_msg)
                                    self:mergeEntries(list, pair.primary, pair.secondary, ai_desc)
                                    merge_count = merge_count + 1
                                    processNextPair()
                                end)()
                            end)
                        else
                            self:mergeEntries(list, pair.primary, pair.secondary, nil)
                            merge_count = merge_count + 1
                            processNextPair()
                        end
                    end
                },
                {
                    text = self.loc:t("skip") or "Skip",
                    callback = function()
                        self:log("XRayPlugin: Skipping pair '" .. tostring(pair.primary) .. "' / '" .. tostring(pair.secondary) .. "'")
                        UIManager:close(confirm_dialog)
                        processNextPair()
                    end
                },
                {
                    text = self.loc:t("reject_pair") or "Reject",
                    callback = function()
                        self:log("XRayPlugin: Rejecting pair '" .. tostring(pair.primary) .. "' / '" .. tostring(pair.secondary) .. "'")
                        UIManager:close(confirm_dialog)
                        local doc_file = self.ui and self.ui.document and self.ui.document.file
                        if not self.book_data then
                            if not self.cache_manager then
                                self.cache_manager = require(plugin_path .. "xray_cachemanager"):new()
                            end
                            self.book_data = (doc_file and self.cache_manager:loadCache(doc_file)) or {}
                        end
                        self.book_data.rejected_merge_pairs = self.book_data.rejected_merge_pairs or {}
                        local p_name = pair.primary:lower()
                        local s_name = pair.secondary:lower()
                        local key = p_name < s_name and (p_name .. "|" .. s_name) or (s_name .. "|" .. p_name)
                        self.book_data.rejected_merge_pairs[key] = true
                        
                        -- Save cache to persist rejection
                        if not self.cache_manager then
                            self.cache_manager = require(plugin_path .. "xray_cachemanager"):new()
                        end
                        if doc_file and self.cache_manager then
                            self.cache_manager:asyncSaveCache(doc_file, self.book_data)
                        end
                        
                        UIManager:show(InfoMessage:new{ text = self.loc:t("pair_rejected") or "Pair marked as not a duplicate.", timeout = 2 })
                        processNextPair()
                    end
                },
                {
                    text = self.loc:t("stop") or "Stop",
                    callback = function()
                        self:log("XRayPlugin: User stopped duplicate walk after " .. tostring(merge_count) .. " merge(s)")
                        UIManager:close(confirm_dialog)
                        pair_idx = #pairs_found + 1
                        processNextPair()
                    end
                }
            }}
        }
        UIManager:show(confirm_dialog)
    end

    processNextPair()
end

function M:showAIFindDuplicatesFlow(list, list_name, entity_label)
    local InfoMessage = require("ui/widget/infomessage")
    local ButtonDialog = require("ui/widget/buttondialog")

    self:log("XRayPlugin: AI duplicate scan started for " .. tostring(list_name))

    if not self.ai_helper or not self.ai_helper:hasApiKey() then
        UIManager:show(InfoMessage:new{
            text = self.loc:t("ai_key_required") or "An AI API key is required.",
            timeout = 4
        })
        return
    end

    local props = self.ui.document:getProps() or {}
    local title  = props.title  or (self.book_data and self.book_data.book_title) or "Unknown"
    local author = props.authors or (self.book_data and self.book_data.author)     or "Unknown"
    local current_page = self.ui:getCurrentPage()
    local reading_percent = math.floor((current_page / self.ui.document:getPageCount()) * 100)
    local spoiler_setting = self.ai_helper.settings and self.ai_helper.settings.spoiler_setting or "spoiler_free"
    if spoiler_setting == "full_book" then reading_percent = 100 end

    if not self.chapter_analyzer then
        self.chapter_analyzer = require(plugin_path .. "xray_chapteranalyzer"):new()
    end
    local dup_book_text = self.chapter_analyzer:getTextForAnalysis(
        self.ui, 15000, nil, current_page)

    local wait_msg = InfoMessage:new{
        text = self.loc:t("ai_scanning_duplicates") or "AI is scanning for duplicates...",
        timeout = 120
    }
    UIManager:show(wait_msg)

    UIManager:scheduleIn(0.1, function()
        if self.destroyed or not self.ui or not self.ui.document then return end
        local pairs_found, err_code, err_msg = self.ai_helper:findDuplicates(
            title, author, list, entity_label, reading_percent, dup_book_text
        )
        UIManager:close(wait_msg)

        if not pairs_found then
            self:log("XRayPlugin: AI duplicate scan failed for " .. tostring(list_name) .. ": " .. tostring(err_msg))
            UIManager:show(InfoMessage:new{
                text = (self.loc:t("ai_error") or "AI Error: ") .. tostring(err_msg),
                timeout = 4
            })
            return
        end

        self:log("XRayPlugin: AI duplicate scan found " .. tostring(#pairs_found) .. " pair(s) for " .. tostring(list_name))
        self:walkDuplicatePairs(list, list_name, pairs_found)
    end)
end

function M:showMergeFlow(list, list_name)
    local ButtonDialog = require("ui/widget/buttondialog")
    local InfoMessage = require("ui/widget/infomessage")
    
    local primary_dialog, secondary_dialog
    local showPrimaryPicker, pickSecondary
    
    pickSecondary = function(primary_item)
        local buttons = {}
        for _, item in ipairs(list) do
            if item.name ~= primary_item.name then
                local secondary_name = item.name
                table.insert(buttons, {{
                    text = secondary_name,
                    align = "left",
                    callback = function()
                        if secondary_dialog then
                            UIManager:close(secondary_dialog)
                            secondary_dialog = nil
                        end
                        local confirm
                        confirm = ButtonDialog:new{
                            modal = true,
                            title = string.format(
                                self.loc:t("merge_confirm") or "Merge %s into %s? The secondary entry will be deleted and its aliases absorbed.",
                                secondary_name, primary_item.name
                            ),
                            buttons = {{
                                {
                                    text = self.loc:t("close") or "Close",
                                    callback = function()
                                        UIManager:close(confirm)
                                    end,
                                },
                                {
                                    text = self.loc:t("yes") or "Yes",
                                    is_enter_default = true,
                                    callback = function()
                                        UIManager:close(confirm)
                                        local wait_msg = InfoMessage:new{ text = self.loc:t("merging_smartly") or "Merging...", timeout = 120 }
                                        UIManager:show(wait_msg)
                                        
                                        UIManager:scheduleIn(0.1, function()
                                            if self.destroyed or not self.ui or not self.ui.document then return end
                                            local ai_merged_desc = nil
                                            if self.ai_helper and self.ai_helper:hasApiKey() then
                                                local sec_item = nil
                                                for _, it in ipairs(list) do
                                                    if it.name == secondary_name then sec_item = it; break end
                                                end
                                                
                                                if sec_item and primary_item.description and sec_item.description then
                                                    if self.ai_helper then self.ai_helper:setTrapWidget(wait_msg) end
                                                    ai_merged_desc = self.ai_helper:mergeDescriptionsWithAI(primary_item.description, sec_item.description)
                                                    if self.ai_helper then self.ai_helper:resetTrapWidget() end
                                                end
                                            end
                                            
                                            UIManager:close(wait_msg)
                                            
                                            if self:mergeEntries(list, primary_item.name, secondary_name, ai_merged_desc) then
                                                -- Save cache: load existing, patch only the changed list
                                                local doc_file = self.ui and self.ui.document and self.ui.document.file
                                                if not self.cache_manager then
                                                    self.cache_manager = require(plugin_path .. "xray_cachemanager"):new()
                                                end
                                                if not self.book_data then
                                                    self.book_data = (doc_file and self.cache_manager:loadCache(doc_file)) or {}
                                                end
                                                local cache = self.book_data
                                                if list_name == "characters" then
                                                    cache.characters = list
                                                elseif list_name == "locations" then
                                                    cache.locations = list
                                                end
                                                if doc_file and self.cache_manager then
                                                    self.cache_manager:asyncSaveCache(doc_file, cache)
                                                end
                                                
                                                -- Clear normalized lookup caches so the LookupManager rebuilds them
                                                for _, it in ipairs(list) do
                                                    it._norm_name = nil
                                                    it._norm_aliases = nil
                                                end
                                                
                                                UIManager:show(InfoMessage:new{
                                                    text = self.loc:t("merge_success") or "Entries merged successfully.",
                                                    timeout = 3
                                                })
                                                
                                                -- Refresh the list menu
                                                if list_name == "characters" then
                                                    self:showCharacters()
                                                elseif list_name == "locations" then
                                                    self:showLocations()
                                                end
                                            else
                                                UIManager:show(InfoMessage:new{
                                                    text = self.loc:t("merge_failed") or "Merge failed.",
                                                    timeout = 3
                                                })
                                            end
                                        end)
                                    end,
                                },
                            }},
                        }
                        UIManager:show(confirm)
                    end
                }})
            end
        end
        
        table.insert(buttons, {{
            text = self.loc:t("merge_back") or "← Back",
            callback = function()
                if secondary_dialog then
                    UIManager:close(secondary_dialog)
                    secondary_dialog = nil
                end
                showPrimaryPicker()
            end
        }})
        
        secondary_dialog = ButtonDialog:new{
            modal = true,
            title = self.loc:t("merge_pick_secondary") or "Choose the entry to REMOVE",
            buttons = buttons
        }
        UIManager:show(secondary_dialog)
    end
    
    showPrimaryPicker = function()
        local buttons = {}
        for _, item in ipairs(list) do
            local primary_item = item
            table.insert(buttons, {{
                text = item.name,
                align = "left",
                callback = function()
                    if primary_dialog then
                        UIManager:close(primary_dialog)
                        primary_dialog = nil
                    end
                    pickSecondary(primary_item)
                end
            }})
        end
        
        table.insert(buttons, {{
            text = self.loc:t("close") or "Close",
            callback = function()
                if primary_dialog then
                    UIManager:close(primary_dialog)
                    primary_dialog = nil
                end
            end
        }})
        
        primary_dialog = ButtonDialog:new{
            modal = true,
            title = self.loc:t("merge_pick_primary") or "Choose the entry to KEEP",
            buttons = buttons
        }
        UIManager:show(primary_dialog)
    end

    showPrimaryPicker()
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

    local base_fs = _getPopupFontSize(self)
    local doc_family
    if self.ui and self.ui.font then
        doc_family = self.ui.font.font_face
    end
    if not doc_family and G_reader_settings then
        doc_family = G_reader_settings:readSetting("cre_font_family")
    end

    local text_has_cjk = false
    if self.author_info.name and _textHasCJK(tostring(self.author_info.name)) then
        text_has_cjk = true
    elseif self.author_info.description and _textHasCJK(tostring(self.author_info.description)) then
        text_has_cjk = true
    end

    local is_cjk = _isCJKFontFamily(doc_family) or text_has_cjk
    local fs
    if is_cjk then
        fs = math.max(12, math.min(math.floor(base_fs * 0.75), 18))
    else
        fs = math.max(12, math.min(base_fs, 20))
    end
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
            face = Font:getFace("cfont", fs - 4),
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

function M:clearCache()
    if not self.cache_manager then self.cache_manager = require(plugin_path .. "xray_cachemanager"):new() end
    if self.ui and self.ui.document and self.ui.document.file then
        self.cache_manager:clearCache(self.ui.document.file)
    end
    self.characters = {}
    self.locations = {}
    self.timeline = {}
    self.historical_figures = {}
    self.terms = {}
    self.terms_fetched = false
    self.author_info = nil
    self.book_data = {}
    self.series_context_loaded = false
    self.xray_mode_enabled = false
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

function M:clearLogs()
    local XRayLogger = require(plugin_path .. "xray_logger")
    XRayLogger:clear()
    UIManager:show(InfoMessage:new{ text = self.loc:t("logs_cleared") or "Logs cleared!", timeout = 3 })
end

local XRayLogViewer = InputContainer:extend{
    pages = nil,
    log_path = nil,
    current_page = nil,
    close_label = nil,
    ui_instance = nil,
}

function XRayLogViewer:init()
    local sw = Screen:getWidth()
    local sh = Screen:getHeight()
    local Device = require("device")

    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }

    self.key_events = {
        PrevPage = {
            { "Left" },
            { "Up" },
            { "PageUp" },
            { "p" },
            { "P" },
        },
        NextPage = {
            { "Right" },
            { "Down" },
            { "PageDown" },
            { "Space" },
            { "n" },
            { "N" },
        },
        Reload = {
            { "r" },
            { "R" },
            { "F5" },
        },
        Close = {
            { "Escape" },
            { "Back" },
            { "q" },
            { "Q" },
        },
    }
    if Device.hasKeys and Device:hasKeys() and Device.input and Device.input.group and Device.input.group.Back then
        table.insert(self.key_events.Close, { Device.input.group.Back })
    end

    self:_rebuild()
end

function XRayLogViewer:onPrevPage()
    if self.current_page and self.current_page > 1 then
        self.current_page = self.current_page - 1
        self:_rebuild()
    end
    return true
end

function XRayLogViewer:onNextPage()
    local total = (self.pages and #self.pages) or 1
    if self.current_page and self.current_page < total then
        self.current_page = self.current_page + 1
        self:_rebuild()
    end
    return true
end

function XRayLogViewer:onReload()
    self:_reloadFromDisk()
    return true
end

function XRayLogViewer:onClose()
    UIManager:close(self)
    return true
end

function XRayLogViewer:_rebuild()
    local sw = Screen:getWidth()
    local sh = Screen:getHeight()
    local Device = require("device")
    local pad = (Size.padding and Size.padding.large) or 12
    local gap = math.max(4, math.floor(sh * 0.01))

    local total_pages = (self.pages and #self.pages) or 1
    local current_page = self.current_page or total_pages
    if current_page < 1 then current_page = 1 end
    if current_page > total_pages then current_page = total_pages end
    self.current_page = current_page

    local text = (self.pages and self.pages[current_page]) or ""

    -- Title
    local title_face = Font:getFace("cfont", 22)
    local title_text = string.format("%s (%d/%d)", (self.ui_instance and self.ui_instance.loc:t("menu_view_log")) or "X-Ray Log", current_page, total_pages)
    local title_widget = TextBoxWidget:new{
        text = title_text,
        face = title_face,
        width = sw - pad * 2,
        alignment = "center",
        bold = true,
    }

    -- Separator
    local line_h = (Size.line and Size.line.thick) or 2
    local separator = LineWidget:new{
        dimen = Geom:new{ w = sw - pad * 2, h = line_h },
        background = Blitbuffer.COLOR_DARK_GRAY,
    }

    local function _getPopupFontSize(plugin)
        local size
        if plugin and plugin.ui and plugin.ui.font and plugin.ui.font.configurable then
            size = plugin.ui.font.configurable.font_size
        elseif G_reader_settings then
            size = G_reader_settings:readSetting("cre_font_size")
                  or G_reader_settings:readSetting("kopt_font_size")
        end
        if size then
            return size
        end
        if Screen.scaleBySize then
            return Screen:scaleBySize(22)
        end
        return 22
    end

    local base_fs = _getPopupFontSize(self.ui_instance and self.ui_instance.plugin)

    local doc_family
    if self.ui_instance and self.ui_instance.plugin and self.ui_instance.plugin.ui and self.ui_instance.plugin.ui.font then
        doc_family = self.ui_instance.plugin.ui.font.font_face
    end
    if not doc_family and G_reader_settings then
        doc_family = G_reader_settings:readSetting("cre_font_family")
    end

    local text_has_cjk = _textHasCJK(text)
    local is_cjk = _isCJKFontFamily(doc_family) or text_has_cjk

    local fs
    if is_cjk then
        fs = math.max(12, math.min(math.floor(base_fs * 0.55), 14))
    else
        fs = math.max(12, math.min(math.floor(base_fs * 0.75), 16))
    end

    local content_face
    if is_cjk then
        content_face = Font:getFace("cfont", fs)
    else
        content_face = Font:getFace("infont", fs)
            or Font:getFace("smallinfont", fs)
            or Font:getFace("cfont", fs)
    end

    if not content_face then
        content_face = Font:getFace("cfont", fs)
    end

    -- Buttons
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local LeftContainer = require("ui/widget/container/leftcontainer")
    local btn_face = Font:getFace("cfont", 18)
    local btn_padding_h = (Size.padding and Size.padding.large) or 12
    local btn_padding_v = (Size.padding and Size.padding.small) or 4

    local active_btns = {}

    -- Prev Button
    local prev_btn = Button:new{
        text = "◀ Prev",
        face = btn_face,
        padding_h = btn_padding_h,
        padding_v = btn_padding_v,
        margin = 10,
        radius = 4,
        bordersize = 2,
        callback = current_page > 1 and function()
            self.current_page = current_page - 1
            UIManager:nextTick(function()
                self:_rebuild()
            end)
        end or nil,
    }
    table.insert(active_btns, prev_btn)

    -- Refresh Button
    local refresh_btn = Button:new{
        text = "⟳ Refresh",
        face = btn_face,
        padding_h = btn_padding_h,
        padding_v = btn_padding_v,
        margin = 10,
        radius = 4,
        bordersize = 2,
        callback = function()
            UIManager:nextTick(function()
                self:_reloadFromDisk()
            end)
        end,
    }
    table.insert(active_btns, refresh_btn)

    -- Next Button
    local next_btn = Button:new{
        text = "Next ▶",
        face = btn_face,
        padding_h = btn_padding_h,
        padding_v = btn_padding_v,
        margin = 10,
        radius = 4,
        bordersize = 2,
        callback = current_page < total_pages and function()
            self.current_page = current_page + 1
            UIManager:nextTick(function()
                self:_rebuild()
            end)
        end or nil,
    }
    table.insert(active_btns, next_btn)

    -- Close Button
    local close_btn = Button:new{
        text = self.close_label or "Close",
        face = btn_face,
        padding_h = btn_padding_h,
        padding_v = btn_padding_v,
        margin = 10,
        radius = 4,
        bordersize = 2,
        callback = function()
            UIManager:close(self)
        end,
    }
    table.insert(active_btns, close_btn)

    local row_h = math.max(prev_btn:getSize().h, refresh_btn:getSize().h, next_btn:getSize().h, close_btn:getSize().h)
    local btn_components = { align = "center" }
    local btn_w = math.floor((sw - pad * 2) / #active_btns)
    for _, btn in ipairs(active_btns) do
        table.insert(btn_components, LeftContainer:new{
            dimen = Geom:new{ w = btn_w, h = row_h },
            btn,
        })
    end
    local btn_row = HorizontalGroup:new(btn_components)

    local title_h = title_widget:getSize().h
    local btn_h = btn_row:getSize().h

    local pad_top = math.max(20, pad)
    local pad_bottom = math.max(20, pad)
    if Device:isAndroid() then
        local safe_bottom = 20
        if Screen.scaleBySize then
            safe_bottom = Screen:scaleBySize(20)
        end
        pad_bottom = pad_bottom + safe_bottom
    end

    local content_h = sh - title_h - separator:getSize().h - btn_h - pad_top - pad_bottom - gap * 3 - (fs + 4)

    local content_widget = TextBoxWidget:new{
        text = text,
        face = content_face,
        width = sw - pad * 2,
        height = content_h,
        alignment = "left",
        justified = false,
        auto_para_direction = false,
    }

    local vg = VerticalGroup:new{
        align = "center",
        title_widget,
        VerticalSpan:new{ width = gap },
        separator,
        VerticalSpan:new{ width = gap },
        content_widget,
        VerticalSpan:new{ width = gap },
        btn_row,
    }

    self.frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        radius = 0,
        padding_top = pad_top,
        padding_bottom = pad_bottom,
        padding_left = pad,
        padding_right = pad,
        width = sw,
        height = sh,
        vg,
    }

    local CenterContainer = require("ui/widget/container/centercontainer")
    self[1] = CenterContainer:new{
        dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh },
        self.frame,
    }

    UIManager:setDirty(self, "full")
end

function XRayLogViewer:_reloadFromDisk()
    if not self.log_path then return end
    local snapshot = nil
    pcall(function()
        local f = io.open(self.log_path, "r")
        if f then
            snapshot = f:read("*a")
            f:close()
        end
    end)

    if not snapshot or snapshot == "" then
        UIManager:show(InfoMessage:new{
            text = (self.ui_instance and self.ui_instance.loc:t("log_empty")) or "Log is empty or currently unavailable.",
            timeout = 3,
        })
        return
    end

    local all_lines = {}
    for line in snapshot:gmatch("[^\r\n]+") do
        table.insert(all_lines, line)
    end

    -- Keep only the last 50 lines for display
    local max_lines = 50
    local display_lines = all_lines
    local skipped = 0
    if #all_lines > max_lines then
        skipped = #all_lines - max_lines
        display_lines = {}
        for i = #all_lines - max_lines + 1, #all_lines do
            table.insert(display_lines, all_lines[i])
        end
    end

    -- Split into pages of 25 lines backward so the last page (most recent logs) is full
    local lines_per_page = 25
    local pages = {}
    local i = #display_lines
    while i > 0 do
        local page_lines = {}
        local start_idx = math.max(1, i - lines_per_page + 1)
        for j = start_idx, i do
            table.insert(page_lines, display_lines[j])
        end
        table.insert(pages, 1, table.concat(page_lines, "\n"))
        i = start_idx - 1
    end

    -- Prepend skipped notice to the first page (earliest logs) if applicable
    if skipped > 0 and #pages > 0 then
        pages[1] = string.format("[... %d earlier line(s) omitted ...]\n%s", skipped, pages[1])
    end

    if #pages > 0 then
        self.pages = pages
        -- If current page is now invalid because pages count changed, clamp it
        if self.current_page > #pages then
            self.current_page = #pages
        end
        self:_rebuild()
    end
end

function XRayLogViewer:onClose()
    UIManager:close(self)
    return true
end

function XRayLogViewer:onShow()
    UIManager:setDirty(self, "ui")
    return true
end

function XRayLogViewer:onCloseWidget()
    if self.ui_instance then
        self.ui_instance.log_viewer = nil
    end
    UIManager:setDirty(nil, "ui")
end

function M:viewLog(page_num)
    local XRayLogger = require(plugin_path .. "xray_logger")
    local log_path = XRayLogger.path .. "/xray.log"

    local snapshot = nil
    pcall(function()
        local f = io.open(log_path, "r")
        if f then
            snapshot = f:read("*a")
            f:close()
        end
    end)

    if not snapshot or snapshot == "" then
        UIManager:show(InfoMessage:new{
            text = self.loc:t("log_empty") or "Log is empty or currently unavailable.",
            timeout = 3,
        })
        return
    end

    local all_lines = {}
    for line in snapshot:gmatch("[^\r\n]+") do
        table.insert(all_lines, line)
    end

    -- Keep only the last 100 lines for display
    local max_lines = 100
    local display_lines = all_lines
    local skipped = 0
    if #all_lines > max_lines then
        skipped = #all_lines - max_lines
        display_lines = {}
        for i = #all_lines - max_lines + 1, #all_lines do
            table.insert(display_lines, all_lines[i])
        end
    end



    -- Fallback to XRayLogViewer
    -- Split into pages of 25 lines backward so the last page (most recent logs) is full
    local lines_per_page = 25
    local pages = {}
    local i = #display_lines
    while i > 0 do
        local page_lines = {}
        local start_idx = math.max(1, i - lines_per_page + 1)
        for j = start_idx, i do
            table.insert(page_lines, display_lines[j])
        end
        table.insert(pages, 1, table.concat(page_lines, "\n"))
        i = start_idx - 1
    end

    -- Prepend skipped notice to the first page (earliest logs) if applicable
    if skipped > 0 and #pages > 0 then
        pages[1] = string.format("[... %d earlier line(s) omitted ...]\n%s", skipped, pages[1])
    end

    local total_pages = #pages
    if total_pages == 0 then
        UIManager:show(InfoMessage:new{
            text = self.loc:t("log_empty") or "Log is empty.",
            timeout = 3,
        })
        return
    end

    -- Default to the last page (most recent logs)
    local target_page = page_num or total_pages
    if target_page < 1 then target_page = 1 end
    if target_page > total_pages then target_page = total_pages end

    if self.log_viewer then
        UIManager:close(self.log_viewer)
        self.log_viewer = nil
    end

    self.log_viewer = XRayLogViewer:new{
        pages = pages,
        log_path = log_path,
        current_page = target_page,
        close_label = self.loc:t("close") or "Close",
        ui_instance = self,
    }
    local viewer = self.log_viewer
    UIManager:nextTick(function()
        UIManager:show(viewer)
    end)
end

function M:toggleXRayMode()
    local enabled_text = self.loc:t("xray_enabled_label") or "Enabled"
    local disabled_text = self.loc:t("xray_disabled_label") or "Disabled"
    XRaySettingsCard.show(self, {
        title = self.loc:t("menu_xray_mode") or "X-Ray Mode Settings",
        description = self.loc:t("xray_mode_desc"),
        options = {
            { text = enabled_text, value = true },
            { text = disabled_text, value = false },
        },
        get_current_func = function()
            return self.xray_mode_enabled == true
        end,
        save_func = function(val)
            self.xray_mode_enabled = val
            if self.ai_helper then self.ai_helper:saveSettings({ xray_mode_enabled = val }) end
            UIManager:setDirty(nil, "ui")
        end,
    })
end

function M:showTimeline()
    if not self.timeline or #self.timeline == 0 then
        local InfoMessage = require("ui/widget/infomessage")
        UIManager:show(InfoMessage:new{ text = self.loc:t("no_timeline_data"), timeout = 3 })
        return
    end
    local utils = require(plugin_path .. "xray_utils")
    local toc = utils:flattenTOC(self.ui.document:getToc())
    self:assignTimelinePages(self.timeline, toc, true)
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
    local base_fs = _getPopupFontSize(self)
    local doc_family
    if self.ui and self.ui.font then
        doc_family = self.ui.font.font_face
    end
    if not doc_family and G_reader_settings then
        doc_family = G_reader_settings:readSetting("cre_font_family")
    end

    local text_has_cjk = false
    if ev.chapter and _textHasCJK(tostring(ev.chapter)) then
        text_has_cjk = true
    elseif ev.event and _textHasCJK(tostring(ev.event)) then
        text_has_cjk = true
    end

    local is_cjk = _isCJKFontFamily(doc_family) or text_has_cjk
    local fs
    if is_cjk then
        fs = math.max(12, math.min(math.floor(base_fs * 0.75), 18))
    else
        fs = math.max(12, math.min(base_fs, 20))
    end
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
    local related = linked_enabled and self:findRelatedEntities(event_text, ev.chapter) or {}

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
        showBottomPopup(self, fig)
        return
    end
    local base_fs = _getPopupFontSize(self)
    local doc_family
    if self.ui and self.ui.font then
        doc_family = self.ui.font.font_face
    end
    if not doc_family and G_reader_settings then
        doc_family = G_reader_settings:readSetting("cre_font_family")
    end

    local text_has_cjk = false
    if fig.name and _textHasCJK(tostring(fig.name)) then
        text_has_cjk = true
    elseif fig.biography and _textHasCJK(tostring(fig.biography)) then
        text_has_cjk = true
    elseif fig.description and _textHasCJK(tostring(fig.description)) then
        text_has_cjk = true
    end

    local is_cjk = _isCJKFontFamily(doc_family) or text_has_cjk
    local fs
    if is_cjk then
        fs = math.max(12, math.min(math.floor(base_fs * 0.75), 18))
    else
        fs = math.max(12, math.min(base_fs, 20))
    end
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
    if bio == "---" then bio = self.loc:t("msg_no_bio") or "No biography available." end
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
    local related = linked_enabled and self:findRelatedEntities(bio, fig.name) or {}
    local mentions_enabled = self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.mentions_enabled ~= false
    
    local buttons = {}
    if #related > 0 then
        buttons = {
            {
                {
                    text = self.loc:t("linked_entries") or "Linked Entries",
                    callback = function()
                        if self.active_details_dialog then UIManager:close(self.active_details_dialog); self.active_details_dialog = nil end
                        self:showRelatedEntities(related, opts, fig)
                    end,
                }
            },
            {
                {
                    text = self.loc:t("find_mentions") or "Find Mentions",
                    callback = function()
                        if self.active_details_dialog then UIManager:close(self.active_details_dialog); self.active_details_dialog = nil end
                        self:showMentionsForEntity(fig)
                    end,
                },
                {
                    text = self.loc:t("close") or "Close",
                    is_enter_default = true,
                    callback = function()
                        if self.active_details_dialog then UIManager:close(self.active_details_dialog) end
                        self.active_details_dialog = nil
                    end,
                }
            }
        }
        if not mentions_enabled then
            table.remove(buttons[2], 1)
        end
    else
        if mentions_enabled then
            buttons = {
                {
                    {
                        text = self.loc:t("find_mentions") or "Find Mentions",
                        callback = function()
                            if self.active_details_dialog then UIManager:close(self.active_details_dialog); self.active_details_dialog = nil end
                            self:showMentionsForEntity(fig)
                        end,
                    },
                    {
                        text = self.loc:t("close") or "Close",
                        is_enter_default = true,
                        callback = function()
                            if self.active_details_dialog then UIManager:close(self.active_details_dialog) end
                            self.active_details_dialog = nil
                        end,
                    }
                }
            }
        else
            buttons = {
                {
                    {
                        text = self.loc:t("close") or "Close",
                        is_enter_default = true,
                        callback = function()
                            if self.active_details_dialog then UIManager:close(self.active_details_dialog) end
                            self.active_details_dialog = nil
                        end,
                    }
                }
            }
        end
    end

    if is_truncated then
        table.insert(buttons, 1, {
            {
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
        })
    end

    self.active_details_dialog = ButtonDialog:new{
        modal = true,
        _added_widgets = { vg },
        buttons = buttons,
    }
    UIManager:show(self.active_details_dialog)
end

function M:showHistoricalFigures()
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
                { id = "gemini-3.7-flash", cost = "free" },
                { id = "gemini-3.6-flash", cost = "free" },
                { id = "gemini-3.5-flash-lite", cost = "free" },
                { id = "gemini-3.5-flash", cost = "free" },
                { id = "gemini-3.1-pro-preview", cost = "paid" },
                { id = "gemini-2.5-pro", cost = "paid" },
            }
        },
        {
            id = "chatgpt",
            display_name = "ChatGPT",
            models = {
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
                { id = "deepseek-v4-flash", cost = "paid" },
                { id = "deepseek-v4-pro", cost = "paid" },
            }
        },
        {
            id = "claude",
            display_name = "Claude",
            models = {
                { id = "claude-sonnet-5", cost = "paid" },
                { id = "claude-sonnet-4-6", cost = "paid" },
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

function M:toggleSeriesContextEnabled()
    if not self.ai_helper or not self.ai_helper.settings then return end
    local current = not not self.ai_helper.settings.series_context_enabled
    self.ai_helper.settings.series_context_enabled = not current
    self.ai_helper:saveSettings({ series_context_enabled = not current })
    UIManager:setDirty(nil, "ui")
end

function M:manualFetchSeriesContext()
    local ButtonDialog = require("ui/widget/buttondialog")
    local cancel_ref = { cancelled = false }
    local wait_dialog
    wait_dialog = ButtonDialog:new{
        title = self.loc:t("fetching_series_info") or "Identifying series books…",
        buttons = {{{
            text = self.loc:t("cancel") or "Cancel",
            callback = function()
                cancel_ref.cancelled = true
                self:log("XRayPlugin: Series: User cancelled series fetch before launch.")
                UIManager:close(wait_dialog)
            end
        }}}
    }
    UIManager:show(wait_dialog)
    UIManager:nextTick(function()
        if cancel_ref.cancelled then
            self:log("XRayPlugin: Series: nextTick fired after user already cancelled fetch.")
            return
        end
        self:fetchSeriesContext(false, wait_dialog, cancel_ref)
    end)
end

function M:showSeriesContextPrompt(series_info)
    if self.destroyed then return end
    self:log("XRayPlugin: Series: showSeriesContextPrompt: Series detected: " .. series_info.name .. ", index=" .. tostring(series_info.index) .. ". Showing prompt dialog.")

    local body_text = self.loc:t(
        "series_context_prompt_text",
        series_info.index,
        series_info.name,
        series_info.index - 1
    )

    local confirm
    confirm = ButtonDialog:new{
        title = (self.loc:t("series_context_prompt_title") or "Series Detected") .. "\n\n" .. body_text,
        buttons = {
            {
                {
                    text = self.loc:t("yes") or "Yes",
                    is_enter_default = true,
                    callback = function()
                        self:log("XRayPlugin: Series: User chose YES on series context prompt.")
                        UIManager:close(confirm)
                        
                        local cancel_ref = { cancelled = false }
                        local wait_dialog
                        wait_dialog = ButtonDialog:new{
                            title = self.loc:t("fetching_series_info") or "Identifying series books…",
                            buttons = {{{
                                text = self.loc:t("cancel") or "Cancel",
                                callback = function()
                                    cancel_ref.cancelled = true
                                    self:log("XRayPlugin: Series: User cancelled series fetch before launch.")
                                    UIManager:close(wait_dialog)
                                end
                            }}}
                        }
                        UIManager:show(wait_dialog)
                        
                        UIManager:nextTick(function()
                            if cancel_ref.cancelled then
                                self:log("XRayPlugin: Series: nextTick fired after user already cancelled fetch.")
                                return
                            end
                            self:fetchSeriesContext(false, wait_dialog, cancel_ref)
                        end)
                    end,
                },
                {
                    text = self.loc:t("later") or "Later",
                    callback = function()
                        self:log("XRayPlugin: Series: User chose LATER on series context prompt.")
                        UIManager:close(confirm)
                        local ask_later_msg = self.loc:t("series_ask_later_msg") or "Series recap postponed. We will ask again when you open/resume this book."
                        UIManager:show(InfoMessage:new{
                            text = ask_later_msg,
                            timeout = 5
                        })
                    end,
                },
                {
                    text = self.loc:t("dont_ask_again") or "Don't ask again",
                    callback = function()
                        self:log("XRayPlugin: Series: User chose DONT_ASK_AGAIN on series context prompt.")
                        UIManager:close(confirm)
                        local doc_file = self.ui and self.ui.document and self.ui.document.file
                        if not self.cache_manager then
                            self.cache_manager = require(plugin_path .. "xray_cachemanager"):new()
                        end
                        if not self.book_data then
                            self.book_data = (doc_file and self.cache_manager:loadCache(doc_file)) or {}
                        end
                        local cache = self.book_data
                        cache.series_context_dismissed = true
                        if doc_file and self.cache_manager then
                            self.cache_manager:asyncSaveCache(doc_file, cache)
                        end
                        local disabled_msg = self.loc:t("series_disabled_msg") or "Auto-prompt disabled for this book. You can manually fetch recap from X-Ray menu."
                        UIManager:show(InfoMessage:new{
                            text = disabled_msg,
                            timeout = 5
                        })
                    end,
                }
            }
        }
    }
    UIManager:show(confirm)
end

function M:checkSeriesContext()
    self:log("XRayPlugin: Series: checkSeriesContext starting")
    if self.destroyed then
        self:log("XRayPlugin: Series: checkSeriesContext: plugin destroyed, skipping")
        return
    end
    if self._unit_scan_in_progress then
        self:log("XRayPlugin: Series: checkSeriesContext: unit scan in progress, deferring series check")
        UIManager:scheduleIn(5, function()
            if self.destroyed or not self.ui or not self.ui.document then return end
            self:checkSeriesContext()
        end)
        return
    end
    if not self.ui or not self.ui.document then
        self:log("XRayPlugin: Series: checkSeriesContext: document/ui not available, skipping")
        return
    end

    if not self.ai_helper or not self.ai_helper.settings or not self.ai_helper.settings.series_context_enabled then
        self:log("XRayPlugin: Series: checkSeriesContext: series_context_enabled setting is false/nil, skipping")
        return
    end

    if self.book_data and (self.book_data.series_context_loaded or self.book_data.series_context_dismissed) then
        self:log("XRayPlugin: Series: checkSeriesContext: series context is already loaded or dismissed, skipping")
        return
    end

    local props = self.ui.document:getProps() or {}
    local function sanitizeMetadata(val)
        if type(val) == "string" then return val
        elseif type(val) == "table" then return table.concat(val, ", ")
        else return "Unknown" end
    end
    local title = sanitizeMetadata(props.title)
    local author = sanitizeMetadata(props.authors)

    self:log("XRayPlugin: Series: checkSeriesContext: checking book title=" .. tostring(title) .. ", author=" .. tostring(author))

    local function saveSeriesChecked()
        self:log("XRayPlugin: Series: Saving series check outcome (dismissed=true) to cache")
        local doc_file = self.ui and self.ui.document and self.ui.document.file
        if not self.cache_manager then
            self.cache_manager = require(plugin_path .. "xray_cachemanager"):new()
        end
        if not self.book_data then
            self.book_data = (doc_file and self.cache_manager:loadCache(doc_file)) or {}
        end
        self.book_data.series_context_dismissed = true
        if doc_file and self.cache_manager then
            self.cache_manager:asyncSaveCache(doc_file, self.book_data)
        end
    end

    -- 1. Try metadata check first (without AI, passes nil for ai_helper)
    local series_info = self.series_manager and self.series_manager.detectSeries and self.series_manager:detectSeries(props, title, author, nil)
    local has_explicit_metadata_index = props and (props.series_index or props.seriesindex or props.SeriesIndex)
    local has_title_index = series_info and self.series_manager and self.series_manager.extractIndexFromTitle and self.series_manager:extractIndexFromTitle(title, series_info.name)

    if series_info and series_info.name and series_info.index then
        if series_info.index > 1 then
            self:log("XRayPlugin: Series: Metadata/title check found series: " .. series_info.name .. ", index=" .. tostring(series_info.index))
            
            -- Check if all prior books are already in local SeriesCache or on local disk
            local slug = series_info.slug or (self.series_manager and self.series_manager.makeSlug and self.series_manager:makeSlug(series_info.name))
            local cache_data = slug and self.series_manager and self.series_manager.loadSeriesCache and self.series_manager:loadSeriesCache(slug) or { series_slug = slug, books = {} }
            cache_data.books = cache_data.books or {}

            -- Try to discover any missing prior books on local disk first
            local doc_file = self.ui and self.ui.document and self.ui.document.file
            for p_idx = 1, series_info.index - 1 do
                if not cache_data.books[p_idx] or cache_data.books[p_idx].source ~= "local_xray" then
                    local local_book = self.series_manager and self.series_manager.findLocalBookXRay and self.series_manager:findLocalBookXRay(series_info, p_idx, doc_file, nil, self.cache_manager)
                    if local_book then
                        cache_data.books[p_idx] = local_book
                    end
                end
            end

            local all_priors_cached = true
            for p_idx = 1, series_info.index - 1 do
                if not cache_data.books[p_idx] then
                    all_priors_cached = false
                    break
                end
            end

            if all_priors_cached then
                self:log("XRayPlugin: Series: All prior books resolved locally. Merging series context automatically.")
                self:mergeSeriesContext(cache_data, series_info)
                return
            end

            local NetworkMgr = require("ui/network/manager")
            if not NetworkMgr:isConnected() or not NetworkMgr:isOnline() then
                self:log("XRayPlugin: Series: Prior books missing from cache and device is offline, skipping silently.")
                return
            end

            self:showSeriesContextPrompt(series_info)
            return
        elseif series_info.has_explicit_index or has_explicit_metadata_index or has_title_index or not (props and (props.series or props.Series)) then
            self:log("XRayPlugin: Series: Metadata/title check confirmed first book in series: " .. series_info.name .. ", index=" .. tostring(series_info.index) .. ". Caching check outcome.")
            saveSeriesChecked()
            return
        else
            self:log("XRayPlugin: Series: Series name found in metadata (" .. series_info.name .. "), but index unknown. Falling through to async AI check.")
        end
    end

    -- 2. Fallback to AI (performed asynchronously to prevent UI freeze, requires network)
    local NetworkMgr = require("ui/network/manager")
    if not NetworkMgr:isConnected() or not NetworkMgr:isOnline() then
        self:log("XRayPlugin: Series: Device is offline, skipping async AI series check silently.")
        return
    end

    self:log("XRayPlugin: Series: Metadata check didn't conclusively resolve series/index. Initiating asynchronous AI check.")
    local prompt = self.ai_helper:createPrompt(title, author, nil, "series_detect")
    local req_params = self.ai_helper:buildComprehensiveRequest(nil, nil, nil, prompt)
    if not req_params then
        self:log("XRayPlugin: Series: Failed to build AI request for series check")
        return
    end

    local DataStorage = require("datastorage")
    local result_file = DataStorage:getSettingsDir() .. "/xray/bg_series_detect_" .. tostring(os.time()) .. ".json"
    
    local request_pid = self.ai_helper:makeRequestAsync(req_params, result_file)
    if not request_pid then
        self:log("XRayPlugin: Series: Async check not supported/failed (e.g. on Windows). Skipping automatic AI fallback.")
        return
    end

    local poll_count = 0
    local max_polls = 150 -- 5 minutes at 2s intervals
    local function pollDetect()
        if self.destroyed or not self.ui or not self.ui.document then
            pcall(function() os.remove(result_file) end)
            return
        end
        poll_count = poll_count + 1
        local result, p_err_code, p_err_msg = self.ai_helper:checkAsyncResult(result_file, request_pid)
        if result == nil then
            if poll_count < max_polls then
                UIManager:scheduleIn(2, pollDetect)
            else
                self:log("XRayPlugin: Series: Async series check timed out")
            end
        elseif result == false then
            self:log("XRayPlugin: Series: Async series check failed: " .. tostring(p_err_msg))
        else
            -- AI returned a valid result!
            self:log("XRayPlugin: Series: Async series check result received")
            if result.is_series then
                local name = result.series_name or (series_info and series_info.name) or (props and (props.series or props.Series))
                local title_idx = self.series_manager and self.series_manager.extractIndexFromTitle and self.series_manager:extractIndexFromTitle(title, name)
                local index = tonumber(result.book_index) or title_idx or 1
                if name and name ~= "" then
                    local make_slug_fn = self.series_manager and self.series_manager.makeSlug
                    local slug = make_slug_fn and self.series_manager:makeSlug(name) or name:lower():gsub("[%s%p]+", "_"):gsub("^_+", ""):gsub("_+$", "")
                    local ai_series_info = {
                        name = name,
                        index = index,
                        slug = slug
                    }
                    self:log("XRayPlugin: Series: Async check detected series=" .. tostring(name) .. ", index=" .. tostring(index))
                    if index > 1 then
                        local cache_data = slug and self.series_manager and self.series_manager.loadSeriesCache and self.series_manager:loadSeriesCache(slug) or { series_slug = slug, books = {} }
                        cache_data.books = cache_data.books or {}

                        local doc_file = self.ui and self.ui.document and self.ui.document.file
                        for p_idx = 1, index - 1 do
                            if not cache_data.books[p_idx] or cache_data.books[p_idx].source ~= "local_xray" then
                                local local_book = self.series_manager and self.series_manager.findLocalBookXRay and self.series_manager:findLocalBookXRay(ai_series_info, p_idx, doc_file, nil, self.cache_manager)
                                if local_book then
                                    cache_data.books[p_idx] = local_book
                                end
                            end
                        end

                        local all_priors_cached = true
                        for p_idx = 1, index - 1 do
                            if not cache_data.books[p_idx] then
                                all_priors_cached = false
                                break
                            end
                        end

                        if all_priors_cached then
                            self:log("XRayPlugin: Series: All prior books resolved locally. Merging series context automatically.")
                            self:mergeSeriesContext(cache_data, ai_series_info)
                        else
                            self:showSeriesContextPrompt(ai_series_info)
                        end
                    else
                        self:log("XRayPlugin: Series: Book is first in series (index=" .. tostring(index) .. "), skipping prompt. Caching check outcome.")
                        saveSeriesChecked()
                    end
                else
                    self:log("XRayPlugin: Series: Async check detected series, but name is invalid. Caching check outcome.")
                    saveSeriesChecked()
                end
            else
                self:log("XRayPlugin: Series: Async check determined book is not part of a series. Caching check outcome.")
                saveSeriesChecked()
            end
        end
    end
    UIManager:scheduleIn(2, pollDetect)
end

function M:resolveDescriptionForPage(entity, current_page)
    if not entity then return "---" end
    local desc_key = entity.biography and "biography" or "description"
    
    -- If there's no history table, return the default description/biography
    if not entity.history or #entity.history == 0 then
        return entity[desc_key] or "---"
    end
    
    -- Default current_page fallback
    local doc_page = nil
    if self.ui then
        if type(self.ui.getCurrentPage) == "function" then
            local ok, p = pcall(function() return self.ui:getCurrentPage() end)
            if ok and p then doc_page = p end
        elseif self.ui.document and type(self.ui.document.getCurrentPage) == "function" then
            local ok, p = pcall(function() return self.ui.document:getCurrentPage() end)
            if ok and p then doc_page = p end
        end
    end
    current_page = current_page or self.last_pageno or doc_page or 999999
    
    -- Traverse history and find the latest entry where entry.page <= current_page
    local best_entry = nil
    for _, entry in ipairs(entity.history) do
        if entry.page and entry.page <= current_page then
            if not best_entry or entry.page > best_entry.page then
                best_entry = entry
            end
        end
    end
    
    if best_entry then
        return best_entry[desc_key] or "---"
    end
    
    -- Fallback to the first history entry if we're somehow before any recorded history page
    if #entity.history > 0 then
        return entity.history[1][desc_key] or "---"
    end
    
    return entity[desc_key] or "---"
end

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

function M:getCurrentSeriesInfo()
    if not self.series_manager then
        local SeriesManager = require(plugin_path .. "xray_seriesmanager")
        self.series_manager = SeriesManager:new()
    end

    local props = self.ui and self.ui.document and self.ui.document.getProps and self.ui.document:getProps() or {}
    local function sanitizeMetadata(val)
        if type(val) == "string" then return val
        elseif type(val) == "table" then return table.concat(val, ", ")
        else return nil end
    end
    local title = sanitizeMetadata(props.title)
    local author = sanitizeMetadata(props.authors)

    local info = self.series_manager:getSeriesInfo(self.book_data, props, title, author)
    if info and self.book_data then
        self.book_data.series_slug = info.slug
        self.book_data.series = info.name
        self.book_data.series_index = info.index
        if not self.book_data.title and title then
            self.book_data.title = title
        end
    end
    return info
end

function M:showImages(opts)
    opts = opts or {}
    self.image_tab = opts.tab or self.image_tab or "all"
    self.image_view_mode = opts.view_mode or self.image_view_mode or "mosaic"
    self.image_filter_mode = opts.filter_mode or self.image_filter_mode or "standard"

    -- Load images: prefer book_data.images from cache (preserves user customizations & rotations),
    -- fall back to scan only if no cached images exist.
    if (not self.book_data or not self.book_data.images) and self.cache_manager and self.ui and self.ui.document and self.ui.document.file then
        local loaded = self.cache_manager:loadCache(self.ui.document.file)
        if loaded and type(loaded) == "table" then
            self.book_data = loaded
        end
    end

    -- If the user minimized an image and is reopening via normal menu, seamlessly resume that image!
    if not opts.force_gallery then
        local min_state = self.last_minimized_state or (self.book_data and self.book_data.last_minimized_state)
        if min_state and min_state.image_entry then
            return self:resumeMinimizedImage()
        end
    end

    if not self.image_manager then
        local ImageManager = require(plugin_path .. "xray_imagemanager")
        self.image_manager = ImageManager:new(self)
    end

    if not self.images or #self.images == 0 then
        if self.book_data and self.book_data.images and #self.book_data.images > 0 then
            self.images = self.book_data.images
        elseif self.ui and self.ui.document then
            -- No cached images — scan fresh
            local scanned = self.image_manager:scanDocumentImages(self.ui)
            self.book_data = self.book_data or {}
            -- Merge all custom user fields from existing book_data.images
            if self.book_data.images and #self.book_data.images > 0 then
                local user_data = {}
                for _, img in ipairs(self.book_data.images) do
                    local entry = {
                        title = img.title,
                        custom_title = img.custom_title,
                        rotation = img.rotation,
                        zoom_level = img.zoom_level,
                        pan_x = img.pan_x,
                        pan_y = img.pan_y,
                        is_favorite = img.is_favorite,
                        is_hidden = img.is_hidden,
                        is_series = img.is_series,
                        cached_file = img.cached_file,
                    }
                    if img.id then user_data[img.id] = entry end
                    if img.href then user_data[img.href] = entry end
                    if img.src then user_data[img.src] = entry end
                end
                for _, img in ipairs(scanned) do
                    local saved = (img.id and user_data[img.id]) or (img.href and user_data[img.href]) or (img.src and user_data[img.src])
                    if saved then
                        if saved.custom_title and saved.title then
                            img.title = saved.title
                            img.custom_title = true
                        end
                        if saved.rotation then img.rotation = saved.rotation end
                        if saved.zoom_level then img.zoom_level = saved.zoom_level end
                        if saved.pan_x then img.pan_x = saved.pan_x end
                        if saved.pan_y then img.pan_y = saved.pan_y end
                        if saved.is_favorite ~= nil then img.is_favorite = saved.is_favorite end
                        if saved.is_hidden ~= nil then img.is_hidden = saved.is_hidden end
                        if saved.is_series ~= nil then img.is_series = saved.is_series end
                        if saved.cached_file then img.cached_file = saved.cached_file end
                    end
                end
            end
            self.images = scanned
            self.book_data.images = self.images
            if self.cache_manager and self.ui.document.file then
                self.cache_manager:asyncSaveCache(self.ui.document.file, self.book_data)
            end
        end
    end

    if self.xray_menu then
        UIManager:close(self.xray_menu)
        self.xray_menu = nil
    end
    if self.image_gallery_overlay then
        local ov = self.image_gallery_overlay
        self.image_gallery_overlay = nil
        UIManager:close(ov, "ui")
    end

    local ImageGallery = require(plugin_path .. "xray_image_gallery")
    local ok_gallery, gallery = pcall(function()
        return ImageGallery:new{
            plugin = self,
            current_page = opts.current_page or 1,
            view_mode = self.image_view_mode,
            tab = self.image_tab,
            filter_mode = self.image_filter_mode,
        }
    end)
    if ok_gallery and gallery then
        self.image_gallery_overlay = gallery
        UIManager:show(gallery, "ui")
    else
        logger.warn("XRayPlugin: Failed to open image gallery:", tostring(gallery))
        if self.notify then
            self:notify(self.loc and self.loc:t("error_opening_gallery") or "Failed to open image gallery", 3)
        end
    end
end

function M:renameImageDialog(image_entry, on_success)
    if not image_entry then return end
    local InputDialog = require("ui/widget/inputdialog")
    local rename_dialog
    rename_dialog = InputDialog:new{
        modal = true,
        title = self.loc:t("img_rename_title") or "Rename Image Label",
        input = image_entry.title or "",
        buttons = {
            {
                {
                    text = self.loc:t("cancel") or "Cancel",
                    callback = function()
                        UIManager:close(rename_dialog)
                    end,
                },
                {
                    text = self.loc:t("save") or "Save",
                    is_enter_default = true,
                    callback = function()
                        local new_val = rename_dialog:getInputText()
                        UIManager:close(rename_dialog)
                        if new_val and #new_val > 0 and self.image_manager and self.book_data then
                            image_entry.title = new_val
                            image_entry.custom_title = true
                            local cur_id = image_entry.id or image_entry.href or image_entry.src
                            self.image_manager:renameImage(self.book_data, cur_id, new_val)
                            if self.images then
                                for _, img in ipairs(self.images) do
                                    if (img.id and img.id == cur_id) or (img.href and img.href == cur_id) or (img.src and img.src == cur_id) then
                                        img.title = new_val
                                        img.custom_title = true
                                    end
                                end
                            end
                            if self.cache_manager and self.ui and self.ui.document and self.ui.document.file then
                                self.cache_manager:asyncSaveCache(self.ui.document.file, self.book_data)
                            end
                            if on_success then on_success() end
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(rename_dialog)
    rename_dialog:onShowKeyboard()
end

function M:showImageActions(image_entry)
    if not image_entry then return end
    local InputContainer = require("ui/widget/container/inputcontainer")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local LeftContainer = require("ui/widget/container/leftcontainer")
    local RightContainer = require("ui/widget/container/rightcontainer")
    local OverlapGroup = require("ui/widget/overlapgroup")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local LineWidget = require("ui/widget/linewidget")
    local TextWidget = require("ui/widget/textwidget")
    local TextBoxWidget = require("ui/widget/textboxwidget")
    local Button = require("ui/widget/button")
    local ImageWidget = require("ui/widget/imagewidget")
    local Font = require("ui/font")
    local Geom = require("ui/geometry")
    local GestureRange = require("ui/gesturerange")
    local Blitbuffer = require("ffi/blitbuffer")
    local Device = require("device")
    local Screen = Device.screen
    local xray_theme = require(plugin_path .. "xray_theme")

    local function sc(val)
        return (Screen and Screen.scaleBySize and Screen:scaleBySize(val)) or val
    end

    local sw = Screen:getWidth()
    local sh = Screen:getHeight()
    local dialog_w = math.min(sw - sc(24), sc(400))
    local card_padding = sc(14)
    local card_border = sc(2)
    local inner_w = dialog_w - (card_padding * 2) - (card_border * 2)

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

    local overlay
    local is_touch_dev = false
    local ok_dev_touch, DevTouch = pcall(require, "device")
    if ok_dev_touch and DevTouch then
        if type(DevTouch.isTouchDevice) == "function" then
            local ok2, res = pcall(DevTouch.isTouchDevice, DevTouch)
            if ok2 and res ~= nil then is_touch_dev = (res == true) end
        elseif DevTouch.isTouchDevice ~= nil then
            is_touch_dev = (DevTouch.isTouchDevice == true)
        end
    end
    local focus_visible = not is_touch_dev
    local focused_action_idx = focus_visible and 1 or nil
    local action_items_list = {}
    local total_nav_items = 1

    local closeDialog
    local refreshActiveContext
    local buildActionItemsList
    local buildDialogWidget
    local rebuildOverlay
    local runAction

    closeDialog = function(callback)
        if overlay then
            local ov = overlay
            overlay = nil
            ov.onClose = nil
            UIManager:close(ov, "ui")
        end
        if callback then callback() end
    end

    refreshActiveContext = function()
        if self.active_image_viewer and self.active_image_viewer.buildUI then
            self.active_image_viewer.image_entry = image_entry
            self.active_image_viewer:buildUI()
            UIManager:setDirty(self.active_image_viewer, "ui")
        end
        if self.image_gallery_overlay then
            self.image_gallery_overlay.cached_pages = nil
            if self.image_gallery_overlay.buildUI then
                self.image_gallery_overlay:buildUI()
                UIManager:setDirty(self.image_gallery_overlay, "ui")
            end
        end
    end

    buildActionItemsList = function()
        action_items_list = {}

        -- 1. Favorite Toggle
        local is_fav = (image_entry.is_favorite == true)
        local fav_title = is_fav and "Remove from Favorites" or "Add to Favorites"
        local fav_desc = is_fav and "Unpin from the favorites tab" or "Pin this image to the favorites tab"
        table.insert(action_items_list, {
            icon = is_fav and "star-off.svg" or "star.svg",
            title = fav_title,
            desc = fav_desc,
            cb = function()
                if self.image_manager and self.book_data then
                    local cur_id = image_entry.id or image_entry.href or image_entry.src
                    local new_fav = self.image_manager:toggleFavorite(self.book_data, cur_id)
                    image_entry.is_favorite = new_fav
                    if self.images then
                        for _, img in ipairs(self.images) do
                            if (img.id and img.id == cur_id) or (img.href and img.href == cur_id) or (img.src and img.src == cur_id) then
                                img.is_favorite = new_fav
                            end
                        end
                    end
                    if self.cache_manager and self.ui.document and self.ui.document.file then
                        self.cache_manager:asyncSaveCache(self.ui.document.file, self.book_data)
                    end
                    refreshActiveContext()
                end
            end,
        })

        -- 2. Series References
        local series_info = self:getCurrentSeriesInfo()
        local is_in_series = false
        local series_slug = series_info and series_info.slug
        if series_slug and series_slug ~= "" and series_slug ~= "series" then
            if type(image_entry.is_series) == "boolean" then
                is_in_series = image_entry.is_series
            elseif self.series_manager then
                local s_imgs = self.series_manager:getSeriesImages(series_slug, 999) or {}
                local cur_id = image_entry.id or image_entry.href or image_entry.src
                for _, s_item in ipairs(s_imgs) do
                    if (s_item.id and cur_id and s_item.id == cur_id) or (s_item.href and image_entry.href and s_item.href == image_entry.href) or (s_item.src and image_entry.src and s_item.src == image_entry.src) then
                        is_in_series = true
                        break
                    end
                end
            end
        end

        local series_title = is_in_series and "Remove from Series References" or "Add to Series References"
        local series_desc
        if not series_info then
            series_desc = self.loc:t("no_series_detected") or "No series detected for this book"
        elseif is_in_series then
            series_desc = "Remove this map from the series-wide collection"
        else
            series_desc = string.format("Keep map accessible across all %s volumes", series_info.name or "series")
        end

        table.insert(action_items_list, {
            icon = "book-open.svg",
            title = series_title,
            desc = series_desc,
            cb = function()
                if not series_info or not series_slug or series_slug == "" or series_slug == "series" then
                    local InfoMessage = require("ui/widget/infomessage")
                    UIManager:show(InfoMessage:new{
                        text = self.loc:t("no_series_to_clear") or "No series detected for this book.",
                        timeout = 3
                    })
                    return
                end

                if self.series_manager then
                    local cur_id = image_entry.id or image_entry.href or image_entry.src
                    if is_in_series then
                        self.series_manager:removeSeriesImage(series_slug, cur_id)
                        image_entry.is_series = false
                    else
                        local copy = {}
                        for k, v in pairs(image_entry) do copy[k] = v end
                        copy.is_series = true
                        if not copy.cached_file and self.image_manager and self.ui and self.ui.document and self.ui.document.file then
                            copy.cached_file = self.image_manager:extractImageToFile(self.ui.document.file, image_entry)
                        end
                        local doc_props = self.ui and self.ui.document and self.ui.document.getProps and self.ui.document:getProps()
                        copy.source_book_title = (self.book_data and self.book_data.title) or (doc_props and doc_props.title) or "Book"
                        copy.source_book_index = (self.book_data and self.book_data.series_index) or series_info.index or 1
                        self.series_manager:saveSeriesImage(series_slug, copy)
                        image_entry.is_series = true
                    end
                    if self.book_data then
                        self.book_data.series_slug = series_slug
                        self.book_data.series = series_info.name
                        self.book_data.series_index = series_info.index
                    end
                    if self.images then
                        for _, img in ipairs(self.images) do
                            if (img.id and img.id == cur_id) or (img.href and img.href == cur_id) or (img.src and img.src == cur_id) then
                                img.is_series = image_entry.is_series
                            end
                        end
                    end
                    if self.cache_manager and self.ui and self.ui.document and self.ui.document.file then
                        self.cache_manager:asyncSaveCache(self.ui.document.file, self.book_data)
                    end
                    refreshActiveContext()
                end
            end,
        })

        -- 3. Rename Label
        table.insert(action_items_list, {
            icon = "edit.svg",
            title = self.loc:t("img_rename_title") or "Rename Label",
            desc = "Edit custom image title and description",
            cb = function()
                self:renameImageDialog(image_entry, function()
                    refreshActiveContext()
                    rebuildOverlay()
                end)
            end,
        })

        -- 4. Jump to Page
        local target_page = tonumber(image_entry.page) or 1
        table.insert(action_items_list, {
            icon = "external-link.svg",
            title = string.format("Jump to Page %d", target_page),
            desc = "Navigate directly to this illustration in reader",
            should_close = true,
            cb = function()
                self:jumpToImagePage(target_page, image_entry)
            end,
        })

        -- 5. Hide / Unhide Image
        local is_hid = (image_entry.is_hidden == true)
        local hide_title = is_hid and "Unhide Image" or "Hide Image"
        local hide_desc = is_hid and "Restore image to main gallery" or "Remove decorative image from gallery"
        table.insert(action_items_list, {
            icon = is_hid and "eye.svg" or "eye-off.svg",
            title = hide_title,
            desc = hide_desc,
            cb = function()
                if self.image_manager and self.book_data then
                    local cur_id = image_entry.id or image_entry.href or image_entry.src
                    local new_hid = self.image_manager:toggleHideImage(self.book_data, cur_id)
                    image_entry.is_hidden = new_hid
                    if self.images then
                        for _, img in ipairs(self.images) do
                            if (img.id and img.id == cur_id) or (img.href and img.href == cur_id) or (img.src and img.src == cur_id) then
                                img.is_hidden = new_hid
                            end
                        end
                    end
                    if self.cache_manager and self.ui.document and self.ui.document.file then
                        self.cache_manager:asyncSaveCache(self.ui.document.file, self.book_data)
                    end
                    refreshActiveContext()
                end
            end,
        })

        -- 6. Open Image Gallery
        if self.active_image_viewer then
            table.insert(action_items_list, {
                icon = "grid.svg",
                title = "Open Image Gallery",
                desc = "Browse all illustrations and maps in book",
                should_close = true,
                cb = function()
                    self:showImages{ force_gallery = true }
                end,
            })
        end

        total_nav_items = #action_items_list + 1
    end

    buildDialogWidget = function()
        local content_items = {}

        -- 1. Card Header
        local display_title = image_entry.title or (self.loc:t("img_untitled") or "Image")
        local title_label = TextBoxWidget:new{
            text = (image_entry.is_favorite and "★ " or "") .. display_title,
            face = Font:getFace("cfont", 20),
            bold = true,
            fgcolor = Blitbuffer.COLOR_BLACK,
            width = inner_w,
            alignment = "left",
        }
        table.insert(content_items, title_label)

        local sub_info = (image_entry.page and ("Page " .. tostring(image_entry.page)) or "Reference Image")
        if image_entry.category then
            sub_info = sub_info .. "  ·  [" .. image_entry.category:upper() .. "]"
        end
        if image_entry.is_series then
            sub_info = sub_info .. "  ·  Series Reference"
        end

        local sub_label = TextWidget:new{
            text = sub_info,
            face = Font:getFace("cfont", 13),
            fgcolor = Blitbuffer.Color8(70),
        }
        table.insert(content_items, sub_label)
        table.insert(content_items, VerticalSpan:new{ width = sc(6) })
        table.insert(content_items, LineWidget:new{
            dimen = Geom:new{ w = inner_w, h = sc(1) },
            background = Blitbuffer.COLOR_DARK_GRAY,
        })
        table.insert(content_items, VerticalSpan:new{ width = sc(6) })

        -- 2. Render Action Rows
        for idx, item_def in ipairs(action_items_list) do
            if idx > 1 then
                table.insert(content_items, VerticalSpan:new{ width = sc(5) })
                table.insert(content_items, LineWidget:new{
                    dimen = Geom:new{ w = inner_w, h = sc(1) },
                    background = Blitbuffer.Color8(175),
                })
                table.insert(content_items, VerticalSpan:new{ width = sc(5) })
            end

            local is_focused = (focus_visible and idx == focused_action_idx)
            local icon_sz = sc(26)
            local icon_widget = ImageWidget:new{
                file = getAssetPath(item_def.icon),
                width = icon_sz,
                height = icon_sz,
                scale_factor = 0,
                is_icon = true,
                alpha = true,
            }

            local max_text_w = inner_w - icon_sz - sc(40)
            local t_label = TextWidget:new{
                text = item_def.title,
                face = Font:getFace("cfont", 16),
                bold = true,
                fgcolor = Blitbuffer.COLOR_BLACK,
                max_width = max_text_w,
            }

            local text_vg = VerticalGroup:new{ align = "left", t_label }
            if item_def.desc and item_def.desc ~= "" then
                table.insert(text_vg, VerticalSpan:new{ width = sc(2) })
                local d_label = TextWidget:new{
                    text = item_def.desc,
                    face = Font:getFace("cfont", 12),
                    fgcolor = Blitbuffer.Color8(75),
                    max_width = max_text_w,
                }
                table.insert(text_vg, d_label)
            end

            local chevron = TextWidget:new{
                text = "›",
                face = Font:getFace("cfont", 19),
                bold = true,
                fgcolor = Blitbuffer.Color8(110),
            }

            local left_content = HorizontalGroup:new{
                align = "center",
                icon_widget,
                HorizontalSpan:new{ width = sc(14) },
                text_vg,
            }

            local row_w = inner_w - sc(16)
            local row_elements = OverlapGroup:new{
                dimen = Geom:new{ w = row_w, h = sc(38) },
                LeftContainer:new{
                    dimen = Geom:new{ w = row_w - sc(24), h = sc(38) },
                    left_content,
                },
                RightContainer:new{
                    dimen = Geom:new{ w = row_w, h = sc(38) },
                    chevron,
                },
            }

            local row_frame = FrameContainer:new{
                padding = sc(8),
                padding_h = sc(8),
                bordersize = is_focused and (xray_theme.border_focus or sc(2)) or 0,
                color = is_focused and (xray_theme.color_focus_border or Blitbuffer.COLOR_BLACK) or Blitbuffer.COLOR_WHITE,
                background = is_focused and (xray_theme.color_focus_bg or Blitbuffer.Color8(230)) or Blitbuffer.COLOR_WHITE,
                radius = sc(4),
                width = inner_w,
                row_elements,
            }

            local item = InputContainer:new{ row_frame }
            item.ges_events = {
                Tap = {
                    GestureRange:new{
                        ges = "tap",
                        range = function()
                            local dim = item.dimen
                            if not dim then return Geom:new{ x = -1, y = -1, w = 1, h = 1 } end
                            return Geom:new{
                                x = dim.x or 0,
                                y = dim.y or 0,
                                w = (dim.w and dim.w > 0 and dim.w) or inner_w,
                                h = (dim.h and dim.h > 0 and dim.h) or sc(48),
                            }
                        end
                    }
                }
            }
            item.onTap = function()
                runAction(item_def)
                return true
            end
            table.insert(content_items, item)
        end

        -- 3. Close Button
        table.insert(content_items, VerticalSpan:new{ width = sc(8) })
        local is_close_focused = (focus_visible and focused_action_idx == total_nav_items)
        local close_btn = Button:new{
            text = self.loc:t("close") or "Close",
            text_font_size = 15,
            text_font_bold = true,
            bordersize = is_close_focused and (xray_theme.border_focus or sc(3)) or sc(1),
            color = is_close_focused and (xray_theme.color_focus_border or Blitbuffer.COLOR_BLACK) or Blitbuffer.COLOR_BLACK,
            background = is_close_focused and (xray_theme.color_focus_bg or Blitbuffer.Color8(200)) or Blitbuffer.Color8(240),
            radius = sc(4),
            width = inner_w,
            height = sc(38),
            callback = function() closeDialog() end,
        }
        table.insert(content_items, close_btn)

        local content_vg = VerticalGroup:new(content_items)
        content_vg.align = "left"

        return FrameContainer:new{
            padding = card_padding,
            radius = sc(4),
            bordersize = card_border,
            color = Blitbuffer.COLOR_BLACK,
            background = Blitbuffer.COLOR_WHITE,
            width = dialog_w,
            content_vg,
        }
    end

    rebuildOverlay = function()
        buildActionItemsList()
        if overlay then
            overlay[1] = CenterContainer:new{
                dimen = Geom:new{ w = sw, h = sh },
                buildDialogWidget(),
            }
            UIManager:setDirty(overlay, "ui")
        end
    end

    runAction = function(item_def)
        if not item_def then return end
        if item_def.should_close then
            closeDialog(item_def.cb)
        else
            if item_def.cb then
                local ok, err = pcall(item_def.cb)
                if not ok then
                    logger.warn("xray: action failed: " .. tostring(err))
                end
            end
            rebuildOverlay()
        end
    end

    -- Initial build: resolve page if missing, non-positive, or if spine cache is already warm
    if self.image_manager and self.image_manager.resolveImagePage then
        local is_warm = self.image_manager._epub_spine_cache and self.ui and self.ui.document and self.ui.document.file and self.image_manager._epub_spine_cache[self.ui.document.file] ~= nil
        if not image_entry.page or tonumber(image_entry.page) <= 0 or (is_warm and not image_entry.page_resolved) then
            self.image_manager:resolveImagePage(self.ui, image_entry)
        end
    end
    buildActionItemsList()
    local card = buildDialogWidget()

    -- Build key name lookup sets for fast matching
    local ok_dev, Device = pcall(require, "device")
    local extra_enter_keys = {}
    local extra_back_keys = {}
    if ok_dev and Device and Device.input and Device.input.group then
        if Device.input.group.Enter then extra_enter_keys[Device.input.group.Enter] = true end
        if Device.input.group.Select then extra_enter_keys[Device.input.group.Select] = true end
        if Device.input.group.Back then extra_back_keys[Device.input.group.Back] = true end
    end

    local UP_KEYS    = { Up=true, Left=true, PrevPage=true, PageUp=true, k=true, K=true }
    local DOWN_KEYS  = { Down=true, Right=true, NextPage=true, PageDown=true, j=true, J=true }
    local ENTER_KEYS = { Return=true, Enter=true, KP_Enter=true, Select=true, Space=true, Press=true }
    local CLOSE_KEYS = { Escape=true, Back=true, q=true, Q=true }
    for k in pairs(extra_enter_keys) do ENTER_KEYS[k] = true end
    for k in pairs(extra_back_keys)  do CLOSE_KEYS[k] = true end

    overlay = InputContainer:new{
        modal = true,
        dimen = Geom:new{ w = sw, h = sh },
        stop_events_propagation = true,
        CenterContainer:new{
            dimen = Geom:new{ w = sw, h = sh },
            card,
        }
    }

    -- Use raw onKeyPress so we intercept keys before any other widget
    overlay.onKeyPress = function(self_ov, key)
        local key_name = key and key.key or key
        if UP_KEYS[key_name] then
            focus_visible = true
            if not focused_action_idx then
                focused_action_idx = total_nav_items
            else
                focused_action_idx = (focused_action_idx > 1) and (focused_action_idx - 1) or total_nav_items
            end
            overlay[1] = CenterContainer:new{
                dimen = Geom:new{ w = sw, h = sh },
                buildDialogWidget(),
            }
            UIManager:setDirty(overlay, "ui")
            return true
        elseif DOWN_KEYS[key_name] then
            focus_visible = true
            if not focused_action_idx then
                focused_action_idx = 1
            else
                focused_action_idx = (focused_action_idx < total_nav_items) and (focused_action_idx + 1) or 1
            end
            overlay[1] = CenterContainer:new{
                dimen = Geom:new{ w = sw, h = sh },
                buildDialogWidget(),
            }
            UIManager:setDirty(overlay, "ui")
            return true
        elseif ENTER_KEYS[key_name] then
            if not focus_visible or not focused_action_idx then
                focused_action_idx = 1
            end
            if focused_action_idx <= #action_items_list then
                local def = action_items_list[focused_action_idx]
                if def then runAction(def) end
            else
                closeDialog()
            end
            return true
        elseif CLOSE_KEYS[key_name] then
            closeDialog()
            return true
        end
    end

    UIManager:show(overlay, "ui")
    return overlay
end

function M:openImageViewer(image_entry)
    if not image_entry then return end
    
    -- Check spoiler protection
    local is_spoiler = image_entry.is_spoiler
    if is_spoiler and self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.no_spoilers ~= false then
        local ConfirmBox = require("ui/widget/confirmbox")
        local msg = string.format(self.loc:t("img_spoiler_confirm") or "This image appears on page %d (past your current reading progress). Reveal image?", tonumber(image_entry.page) or 0)
        local confirm
        confirm = ConfirmBox:new{
            modal = true,
            text = msg,
            ok_text = self.loc:t("img_reveal") or "Reveal",
            cancel_text = self.loc:t("cancel"),
            ok_callback = function()
                image_entry.is_spoiler = false
                if self.image_gallery_overlay then
                    self.image_gallery_overlay:buildUI()
                    UIManager:setDirty(self.image_gallery_overlay, "ui")
                end
                self:_launchImageViewer(image_entry)
            end,
        }
        UIManager:show(confirm)
        return
    end

    self:_launchImageViewer(image_entry)
end

function M:_launchImageViewer(image_entry, custom_state)
    if not image_entry then return end

    local file_path = image_entry.cached_file or image_entry.local_file or image_entry.file_path
    if file_path then
        local f = io.open(file_path, "rb")
        if f then
            f:close()
        else
            file_path = nil
        end
    end

    if not file_path then
        local book_path = self.ui and self.ui.document and self.ui.document.file
        if not self.image_manager then
            local ImageManager = require(plugin_path .. "xray_imagemanager")
            self.image_manager = ImageManager:new(self)
        end
        if book_path and self.image_manager then
            file_path = self.image_manager:extractImageToFile(book_path, image_entry)
        end
    end

    if not file_path then
        UIManager:show(InfoMessage:new{
            text = self.loc:t("img_extract_failed") or "Could not extract image file.",
            timeout = 3,
        })
        return
    end

    if not self.book_data and self.cache_manager and self.ui and self.ui.document and self.ui.document.file then
        self.book_data = self.cache_manager:loadCache(self.ui.document.file) or {}
    end
    if self.book_data and self.book_data.images then
        for _, b_img in ipairs(self.book_data.images) do
            if (image_entry.id and b_img.id == image_entry.id)
                or (image_entry.href and b_img.href == image_entry.href)
                or (image_entry.src and b_img.src == image_entry.src)
                or (image_entry.title and b_img.title == image_entry.title)
                or (image_entry.cached_file and b_img.cached_file == image_entry.cached_file) then
                if b_img.rotation ~= nil then image_entry.rotation = b_img.rotation end
                if b_img.zoom_level ~= nil then image_entry.zoom_level = b_img.zoom_level end
                if b_img.pan_x ~= nil then image_entry.pan_x = b_img.pan_x end
                if b_img.pan_y ~= nil then image_entry.pan_y = b_img.pan_y end
                break
            end
        end
    end

    local ImageViewer = require(plugin_path .. "xray_image_viewer")
    local viewer = ImageViewer:new{
        plugin = self,
        image_entry = image_entry,
        file_path = file_path,
        rotation_angle = (custom_state and custom_state.rotation_angle) or image_entry.rotation,
        zoom_level = (custom_state and custom_state.zoom_level) or image_entry.zoom_level,
        pan_x = (custom_state and custom_state.pan_x) or image_entry.pan_x,
        pan_y = (custom_state and custom_state.pan_y) or image_entry.pan_y,
        inverted = (custom_state and custom_state.inverted ~= nil and custom_state.inverted) or image_entry.inverted,
        is_resumed = (custom_state and custom_state.is_resumed) or false,
    }
    self.active_image_viewer = viewer
    UIManager:show(viewer, "ui")
end

function M:resumeMinimizedImage()
    local state = self.last_minimized_state or (self.book_data and self.book_data.last_minimized_state)
    if not state or not state.image_entry then
        return self:showImages()
    end
    state.is_resumed = true
    self:_launchImageViewer(state.image_entry, state)
end

function M:resumeImagesFeature()
    if self.return_banner then
        local banner = self.return_banner
        self.return_banner = nil
        self.return_page_origin = nil
        pcall(function() UIManager:close(banner) end)
    end

    if self.was_in_image_viewer and (self.last_minimized_state or (self.book_data and self.book_data.last_minimized_state)) then
        self:resumeMinimizedImage()
    else
        self:showImages{
            force_gallery = true,
            tab = self.saved_gallery_tab,
            current_page = self.saved_gallery_page,
            view_mode = self.saved_gallery_view_mode,
        }
    end
end

function M:jumpToImagePage(page, image_entry)
    local pg = tonumber(page)
    if image_entry and self.image_manager and self.image_manager.resolveImagePage and (not image_entry.page_resolved or not pg or pg <= 0) then
        local resolved = self.image_manager:resolveImagePage(self.ui, image_entry, true)
        if resolved and resolved > 0 then pg = resolved end
        if self.cache_manager and self.ui and self.ui.document and self.ui.document.file and self.book_data then
            self.cache_manager:asyncSaveCache(self.ui.document.file, self.book_data)
        end
    end
    if not pg then return end

    local current_pg = self.return_page_origin or self.last_pageno
    if not current_pg and self.ui then
        if self.ui.getCurrentPage then
            local ok, p = pcall(function() return self.ui:getCurrentPage() end)
            if ok and p then current_pg = p end
        elseif self.ui.paging and self.ui.paging.getCurrentPage then
            local ok, p = pcall(function() return self.ui.paging:getCurrentPage() end)
            if ok and p then current_pg = p end
        elseif self.ui.document and self.ui.document.getCurrentPage then
            local ok, p = pcall(function() return self.ui.document:getCurrentPage() end)
            if ok and p then current_pg = p end
        end
    end
    local return_pg = current_pg or 1
    self.return_page_origin = return_pg

    self.pending_return_banner = {
        return_page = return_pg,
        image_entry = image_entry,
        is_image = true,
    }

    if self.image_gallery_overlay then
        self.saved_gallery_page = self.image_gallery_overlay.current_page
        self.saved_gallery_tab = self.image_gallery_overlay.tab
        self.saved_gallery_view_mode = self.image_gallery_overlay.view_mode
        local ov = self.image_gallery_overlay
        self.image_gallery_overlay = nil
        UIManager:close(ov, "ui")
    end

    if self.active_image_viewer then
        self.was_in_image_viewer = true
        self.last_minimized_state = {
            image_entry = self.active_image_viewer.image_entry or image_entry,
            rotation_angle = self.active_image_viewer.rotation_angle,
            zoom_level = self.active_image_viewer.zoom_level,
            pan_x = self.active_image_viewer.pan_x,
            pan_y = self.active_image_viewer.pan_y,
            inverted = self.active_image_viewer.inverted,
        }
        if self.book_data then
            self.book_data.last_minimized_state = self.last_minimized_state
        end
        self.active_image_viewer:close(true)
    else
        self.was_in_image_viewer = false
        if not self.last_minimized_state or not self.last_minimized_state.image_entry then
            self.last_minimized_state = {
                image_entry = image_entry,
            }
        end
    end
    self:closeAllMenus()

    -- If already on this page, show the return banner immediately
    if pg == return_pg then
        self.pending_return_banner = nil
        UIManager:nextTick(function()
            if self.showImageReturnBanner then
                self:showImageReturnBanner(return_pg, image_entry, pg)
            end
        end)
        return
    end

    UIManager:nextTick(function()
        if self.ui and self.ui.handleEvent then
            local ok_ev, Event = pcall(require, "ui/event")
            if ok_ev and Event then
                self.ui:handleEvent(Event:new("GotoPage", pg))
                return
            end
        end
        if self.ui and self.ui.document and self.ui.document.gotoPage then
            self.ui.document:gotoPage(pg)
        end
    end)
end

return M
