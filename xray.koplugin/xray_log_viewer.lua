-- X-Ray Log Viewer and Log Management
local Screen          = require("device").screen
local UIManager       = require("ui/uimanager")
local InfoMessage     = require("ui/widget/infomessage")
local Geom            = require("ui/geometry")
local InputContainer  = require("ui/widget/container/inputcontainer")
local Size            = require("ui/size")
local CenterContainer = require("ui/widget/container/centercontainer")
local ImageWidget     = require("ui/widget/imagewidget")

local FrameContainer  = require("ui/widget/container/framecontainer")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local TextBoxWidget   = require("ui/widget/textboxwidget")
local LineWidget      = require("ui/widget/linewidget")
local Button          = require("ui/widget/button")
local Font            = require("ui/font")

local plugin_path = ((...) or ""):match("(.-)[^%.]+$") or ""
local utils = require(plugin_path .. "xray_utils")

local function _textHasCJK(text)
    return utils:textHasCJK(text)
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

local M = {}

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
            { "RPgBack" },
            { "LPgBack" },
        },
        NextPage = {
            { "Right" },
            { "Down" },
            { "PageDown" },
            { "Space" },
            { "n" },
            { "N" },
            { "RPgFwd" },
            { "LPgFwd" },
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
    if Device.input and Device.input.group then
        if Device.input.group.PgFwd then
            table.insert(self.key_events.NextPage, { Device.input.group.PgFwd })
        end
        if Device.input.group.PgBack then
            table.insert(self.key_events.PrevPage, { Device.input.group.PgBack })
        end
    end
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
    local is_arabic = (utils.textHasArabic and utils:textHasArabic(text))
        or (utils.isArabicFontFamily and utils:isArabicFontFamily(doc_family))

    local fs
    if is_cjk then
        fs = math.max(12, math.min(math.floor(base_fs * 0.55), 14))
    elseif is_arabic then
        fs = math.max(14, math.min(math.floor(base_fs * 0.90), 20))
    else
        fs = math.max(12, math.min(math.floor(base_fs * 0.75), 16))
    end

    local content_face
    if is_cjk or is_arabic then
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



M.XRayLogViewer = XRayLogViewer

return M
