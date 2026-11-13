-- Bottom-panel popup widget and popup font metric calculations
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
local Screen          = require("device").screen
local UIManager       = require("ui/uimanager")

local plugin_path = ((...) or ""):match("(.-)[^%.]+$") or ""
local utils = require(plugin_path .. "xray_utils")

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

local function _textHasCJK(text)
    return utils:textHasCJK(text)
end

local function _getTruncatedText(text, limit_en, threshold_en)
    return utils:getTruncatedText(text, limit_en, threshold_en)
end

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
    local p = (plugin and plugin.plugin) or plugin
    local size
    if p and p.ui and p.ui.font and p.ui.font.configurable then
        size = p.ui.font.configurable.font_size
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

local M = {}

function M:calculatePopupFontMetrics(entity_or_text, opts)
    local plugin = (self and self.plugin) or self
    local base_fs = _getPopupFontSize(plugin)

    local font_setting = plugin and plugin.ai_helper and plugin.ai_helper.settings and plugin.ai_helper.settings.popup_font_size
    local font_offset = 0
    if font_setting == "small" then
        font_offset = -2
    elseif font_setting == "large" then
        font_offset = 3
    elseif font_setting == "xlarge" then
        font_offset = 6
    end
    local adjusted_base = math.max(12, base_fs + font_offset)

    local doc_family
    if plugin and plugin.ui and plugin.ui.font then
        doc_family = plugin.ui.font.font_face
    end
    if not doc_family and G_reader_settings then
        doc_family = G_reader_settings:readSetting("cre_font_family")
    end

    local is_arabic = false
    local is_cjk = false

    if type(entity_or_text) == "table" then
        is_arabic = (utils.entityHasArabic and utils:entityHasArabic(entity_or_text)) == true
        is_cjk = (utils.entityHasCJK and utils:entityHasCJK(entity_or_text)) == true
    elseif type(entity_or_text) == "string" then
        is_arabic = (utils.textHasArabic and utils:textHasArabic(entity_or_text)) == true
        is_cjk = (utils.textHasCJK and utils:textHasCJK(entity_or_text)) == true
    end

    if not is_arabic then
        local is_rtl = (plugin and plugin.isRTL and plugin:isRTL()) == true
        local is_ar_font = (utils.isArabicFontFamily and utils:isArabicFontFamily(doc_family)) == true
        is_arabic = is_rtl or is_ar_font
    end
    if not is_cjk then
        is_cjk = _isCJKFontFamily(doc_family) == true
    end

    is_arabic = (is_arabic == true)
    is_cjk = (is_cjk == true)

    local fs, fs_small, fs_btn
    if is_cjk then
        -- CJK glyphs fill the full em-box; scale down to match Latin optical size
        fs = math.max(12, math.min(math.floor(adjusted_base * 0.75), 20))
        fs_small = math.max(11, fs - 3)
        fs_btn = math.max(13, fs - 1)
    elseif is_arabic then
        -- Arabic glyphs have low body x-height and require diacritic headroom;
        -- scale up by ~1.25x and increase maximum ceiling from 20 to 30.
        fs = math.max(16, math.min(math.floor(adjusted_base * 1.25), 30))
        fs_small = math.max(14, math.floor(fs * 0.88))
        fs_btn = math.max(15, fs - 2)
    else
        -- Standard Latin / Western scripts
        fs = math.max(14, math.min(adjusted_base, 24))
        fs_small = math.max(12, fs - 4)
        fs_btn = math.max(14, fs - 2)
    end

    return {
        fs = fs,
        fs_small = fs_small,
        fs_btn = fs_btn,
        is_arabic = is_arabic,
        is_cjk = is_cjk,
        doc_family = doc_family,
    }
end

local function _calculatePopupFontMetrics(target, entity_or_text, opts)
    local caller = (target and target.calculatePopupFontMetrics and target) or M
    return caller:calculatePopupFontMetrics(entity_or_text, opts)
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

    local metrics = _calculatePopupFontMetrics(self.plugin, e)
    local fs = metrics.fs
    local fs_small = metrics.fs_small
    local fs_btn = metrics.fs_btn
    local is_cjk = metrics.is_cjk
    local is_arabic = metrics.is_arabic
    local doc_family = self._font_fallback and nil or metrics.doc_family
    local Device = require("device")

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
    local face_btn    = Font:getFace("cfont", fs_btn)

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

    local function make_btn(label, cb, is_focused, custom_fs, custom_pad_h)
        return Button:new{
            text            = label,
            text_font_face  = "cfont",
            text_font_size  = custom_fs or fs_btn,
            text_font_bold  = true,
            padding_h       = custom_pad_h or btn_padding_h,
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
        related = plugin:findRelatedEntities(desc_str or "", e.name, e) or {}
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

    -- Past Evolution button
    local evolution_enabled = plugin and plugin.ai_helper and plugin.ai_helper.settings and plugin.ai_helper.settings.evolution_enabled ~= false
    local has_evo = evolution_enabled and (((plugin and plugin.hasEntityEvolution) and plugin:hasEntityEvolution(e))
                    or (e.states and #e.states > 1) or (e.history and #e.history > 1))
    if has_evo and plugin and plugin.showPastEvolution then
        table.insert(raw_button_defs, {
            label = get_loc_t("past_evolution", "Story Arc"),
            cb = function()
                UIManager:close(self)
                UIManager:nextTick(function()
                    plugin:showPastEvolution(e)
                end)
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

    -- D. Highlight Menu button (when opened via auto-popup)
    if self.restore_menu_cb then
        table.insert(raw_button_defs, {
            label = get_loc_t("highlight_menu_btn", "Highlight Menu"),
            cb = function()
                UIManager:close(self)
                self.restore_menu_cb()
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
    local is_multi_btn = (#raw_button_defs >= 3)
    local cur_fs_btn = is_multi_btn and math.max(12, math.min(14, fs_btn - 2)) or fs_btn
    local cur_pad_h = is_multi_btn and 8 or btn_padding_h
    local span_w = is_multi_btn and math.max(8, gap) or math.max(12, gap * 2)

    local active_btns = {}
    for idx, bdef in ipairs(raw_button_defs) do
        local is_focused = (idx == self.focused_btn_index)
        local btn = make_btn(bdef.label, bdef.cb, is_focused, cur_fs_btn, cur_pad_h)
        table.insert(active_btns, btn)
    end

    -- Layout buttons row
    local btn_row
    if #active_btns > 0 then
        local row_h = 0
        local total_btns_w = 0
        for _, btn in ipairs(active_btns) do
            local sz = btn:getSize()
            row_h = math.max(row_h, sz.h)
            total_btns_w = total_btns_w + sz.w
        end
        total_btns_w = total_btns_w + (#active_btns - 1) * span_w

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
        elseif total_btns_w > inner_w and #active_btns > 2 then
            -- Multi-row wrap with uniform column widths (2 columns per row)
            local col_w = math.floor((inner_w - span_w) / 2)
            for _, btn in ipairs(active_btns) do
                btn.width = col_w
            end

            local rows = {}
            local current_row = nil
            for i, btn in ipairs(active_btns) do
                if (i % 2) == 1 then
                    current_row = { align = "center" }
                    table.insert(rows, current_row)
                    table.insert(current_row, btn)
                else
                    table.insert(current_row, HorizontalSpan:new{ width = span_w })
                    table.insert(current_row, btn)
                end
            end

            local vg_rows = { align = "center" }
            for r_idx, r in ipairs(rows) do
                if r_idx > 1 then
                    table.insert(vg_rows, VerticalSpan:new{ width = math.max(6, gap) })
                end
                table.insert(vg_rows, HorizontalGroup:new(r))
            end
            btn_row = VerticalGroup:new(vg_rows)
        else
            local btn_components = { align = "center" }
            for i, btn in ipairs(active_btns) do
                if i > 1 then
                    table.insert(btn_components, HorizontalSpan:new{ width = span_w })
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

local function showBottomPopup(plugin, entity, opts)
    if not entity then return end
    if plugin.active_details_dialog then
        UIManager:close(plugin.active_details_dialog)
        plugin.active_details_dialog = nil
    end

    local normalized = {}
    for k, v in pairs(entity) do normalized[k] = v end

    if plugin.getUnlockedAliases then
        normalized.aliases = plugin:getUnlockedAliases(entity)
    end

    if plugin.resolveEntityState and (entity.states and #entity.states > 0) then
        local r_role, r_status, r_desc = plugin:resolveEntityState(entity)
        if r_role then normalized.role = r_role end
        if r_status then normalized.status = r_status end
        if r_desc and r_desc ~= "---" then normalized.description = r_desc end
    elseif plugin.resolveDescriptionForPage then
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
        modal           = true,
        entity          = normalized,
        plugin          = plugin,
        font_size       = fs,
        margin_size     = pad,
        restore_menu_cb = opts and opts.restore_menu_cb,
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



-- Multi-calling convention wrappers
local raw_showBottomPopup = showBottomPopup
M.showBottomPopup = function(self_or_plugin, entity_or_opts, maybe_opts)
    if type(entity_or_opts) == "table" and (entity_or_opts.name or entity_or_opts.description or entity_or_opts.category or entity_or_opts.biography or entity_or_opts.definition) then
        return raw_showBottomPopup(self_or_plugin, entity_or_opts, maybe_opts)
    else
        return raw_showBottomPopup(self_or_plugin, entity_or_opts, maybe_opts)
    end
end

local raw_shouldUseBottomPopup = shouldUseBottomPopup
M.shouldUseBottomPopup = function(self_or_plugin, maybe_opts)
    if type(maybe_opts) == "table" or maybe_opts == nil then
        return raw_shouldUseBottomPopup(self_or_plugin, maybe_opts)
    else
        return raw_shouldUseBottomPopup(self_or_plugin)
    end
end

M.XRayBottomPopup = XRayBottomPopup

return M
