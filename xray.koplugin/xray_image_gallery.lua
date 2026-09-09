-- xray_image_gallery.lua — Visual Image, Map & Diagram Gallery UI for KOReader X-Ray
-- Implements custom visual Mosaic (Masonry), Grid (Storefront Screensaver Style), and List views.

local UIManager = require("ui/uimanager")
local InputContainer = require("ui/widget/container/inputcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local RightContainer = require("ui/widget/container/rightcontainer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
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
local RenderImage = require("ui/renderimage")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Screen = Device.screen
local ok_ffiu, ffiutil = pcall(require, "ffi/util")
local ok_ds, DataStorage = pcall(require, "datastorage")

local plugin_path = ((...) or ""):match("(.-)[^%.]+$") or ""
local theme = require(plugin_path .. "xray_theme")

local function sc(val)
    return (Screen and Screen.scaleBySize and Screen:scaleBySize(val)) or val
end

-- Fast binary header parser for PNG, JPEG, and GIF dimensions
local function getImageDimensions(file_path)
    if not file_path then return nil, nil end
    local f = io.open(file_path, "rb")
    if not f then return nil, nil end
    local header = f:read(32)
    if not header or #header < 8 then
        f:close()
        return nil, nil
    end

    -- PNG: bytes 17-24 (width, height in big-endian)
    if header:sub(1, 8) == "\137PNG\r\n\26\n" then
        local w1, w2, w3, w4, h1, h2, h3, h4 = header:byte(17, 24)
        f:close()
        if w1 and h4 then
            local w = (w1 * 16777216) + (w2 * 65536) + (w3 * 256) + w4
            local h = (h1 * 16777216) + (h2 * 65536) + (h3 * 256) + h4
            return w, h
        end
        return nil, nil
    end

    -- GIF: bytes 7-10 (width, height in little-endian)
    if header:sub(1, 3) == "GIF" then
        local w1, w2, h1, h2 = header:byte(7, 10)
        f:close()
        if w1 and h2 then
            local w = w1 + (w2 * 256)
            local h = h1 + (h2 * 256)
            return w, h
        end
        return nil, nil
    end

    -- JPEG: scan for SOF0/SOF2 marker
    if header:byte(1) == 0xFF and header:byte(2) == 0xD8 then
        f:seek("set", 2)
        while true do
            local marker_data = f:read(4)
            if not marker_data or #marker_data < 4 then break end
            local m1, m2 = marker_data:byte(1, 2)
            if m1 ~= 0xFF then break end
            local len = marker_data:byte(3) * 256 + marker_data:byte(4)
            if (m2 >= 0xC0 and m2 <= 0xC3) or (m2 >= 0xC5 and m2 <= 0xC7) or (m2 >= 0xC9 and m2 <= 0xCB) or (m2 >= 0xCD and m2 <= 0xCF) then
                local sof = f:read(5)
                f:close()
                if sof and #sof >= 5 then
                    local h = sof:byte(2) * 256 + sof:byte(3)
                    local w = sof:byte(4) * 256 + sof:byte(5)
                    return w, h
                end
                break
            else
                f:seek("cur", len - 2)
            end
        end
    end

    f:close()
    return nil, nil
end

local _asset_path_cache = {}
local function getAssetPath(filename)
    if _asset_path_cache[filename] then
        return _asset_path_cache[filename]
    end
    local info = debug.getinfo(1, "S")
    local file_dir = (info and info.source and info.source:match("^@?(.*[/\\])")) or ""
    local data_dir = (ok_ds and DataStorage and DataStorage.getDataDir and DataStorage:getDataDir()) or ""
    local settings_dir = (ok_ds and DataStorage and DataStorage.getSettingsDir and DataStorage:getSettingsDir()) or ""

    local candidates = {
        file_dir .. "assets/" .. filename,
        file_dir .. "../assets/" .. filename,
        "plugins/xray.koplugin/assets/" .. filename,
        "./plugins/xray.koplugin/assets/" .. filename,
        data_dir .. "/plugins/xray.koplugin/assets/" .. filename,
        settings_dir .. "/plugins/xray.koplugin/assets/" .. filename,
    }
    for _, path in ipairs(candidates) do
        local f = io.open(path, "r")
        if f then
            f:close()
            if ok_ffiu and ffiutil and ffiutil.realpath then
                local rp = ffiutil.realpath(path)
                if rp then path = rp end
            end
            _asset_path_cache[filename] = path
            return path
        end
    end
    return "plugins/xray.koplugin/assets/" .. filename
end

local function makeTapItem(frame, callback)
    local item = InputContainer:new{ frame }
    item.frame = frame
    function item:getSize()
        return (frame and frame.getSize and frame:getSize()) or { w = frame.width or 0, h = frame.height or 0 }
    end
    function item:paintTo(bb, x, y)
        local fsize = (frame and frame.getSize and frame:getSize()) or { w = frame.width or 0, h = frame.height or 0 }
        self.dimen = Geom:new{ x = x, y = y, w = fsize.w or 0, h = fsize.h or 0 }
        if self.onBeforePaint then
            self:onBeforePaint()
        end
        frame:paintTo(bb, x, y)
    end
    item.ges_events = {
        Tap = {
            GestureRange:new{
                ges = "tap",
                range = function()
                    return item.dimen or Geom:new{ x = -1, y = -1, w = 1, h = 1 }
                end
            }
        }
    }
    item.onTap = function()
        if callback then
            pcall(callback)
        end
        return true
    end
    return item
end

local function createIconButton(opts)
    opts = opts or {}
    local icon_size = opts.size or sc(20)
    local icon_widget
    if opts.text_icon then
        icon_widget = TextWidget:new{
            text = opts.text_icon,
            face = Font:getFace("cfont", opts.text_size or 18),
            bold = true,
            fgcolor = Blitbuffer.COLOR_BLACK,
        }
    else
        icon_widget = ImageWidget:new{
            file = getAssetPath(opts.icon),
            width = icon_size,
            height = icon_size,
            scale_factor = 0,
            is_icon = true,
            alpha = true,
        }
    end
    local frame = FrameContainer:new{
        width = opts.width,
        height = opts.height,
        padding = opts.padding or sc(4),
        padding_h = opts.padding_h or sc(6),
        bordersize = opts.bordersize or sc(1),
        color = opts.color or Blitbuffer.COLOR_DARK_GRAY,
        background = opts.background or theme.color_bg or Blitbuffer.COLOR_WHITE,
        radius = opts.radius or sc(4),
        icon_widget,
    }
    return makeTapItem(frame, opts.callback)
end

-- Action menu badge (supports plain black dots or inverted white-on-black badge)
local function createDotMenuBadge(size, is_plain)
    local badge_sz = size or sc(34)
    local icon_sz = sc(22)
    if is_plain then
        return FrameContainer:new{
            width = badge_sz,
            height = badge_sz,
            padding = 0,
            bordersize = 0,
            CenterContainer:new{
                dimen = Geom:new{ w = badge_sz, h = badge_sz },
                ImageWidget:new{
                    file = getAssetPath("more-vertical.svg"),
                    width = icon_sz,
                    height = icon_sz,
                    scale_factor = 0,
                    is_icon = true,
                    alpha = true,
                }
            }
        }
    end
    return FrameContainer:new{
        width = badge_sz,
        height = badge_sz,
        padding = 0,
        bordersize = sc(1),
        color = Blitbuffer.COLOR_BLACK,
        background = Blitbuffer.COLOR_BLACK,
        radius = sc(4),
        CenterContainer:new{
            dimen = Geom:new{ w = badge_sz, h = badge_sz },
            ImageWidget:new{
                file = getAssetPath("more-vertical-white.svg"),
                width = icon_sz,
                height = icon_sz,
                scale_factor = 0,
                is_icon = true,
                alpha = true,
            }
        }
    }
end

-- Robust thumbnail widget for gallery cards and list rows.
-- Uses KOReader's native ImageWidget with scale_factor = 0 to decode and scale
-- images at their natural aspect ratio without stretching, cropping, or static noise.
-- file_do_cache = false avoids exhausting the 8 MB LRU ImageCache on large book illustrations.
local function createGalleryThumbnailWidget(file_path, target_w, target_h)
    if not file_path or not target_w or not target_h then return nil end
    local ok, widget = pcall(function()
        return ImageWidget:new{
            file = file_path,
            width = target_w,
            height = target_h,
            scale_factor = 0,
            alpha = true,
            file_do_cache = false,
        }
    end)
    return ok and widget or nil
end

local createCoverImageWidget = createGalleryThumbnailWidget
local createMosaicImageWidget = createGalleryThumbnailWidget


local function createButton(opts)
    opts = opts or {}
    local is_primary = (opts.is_primary == true) or (opts.primary == true)
    local is_enabled = (opts.enabled ~= false)
    local border_sz = opts.bordersize or sc(1)
    local radius = opts.radius or (theme.radius_btn or sc(4))

    local btn_opts = {
        text = opts.text or "",
        text_font_size = opts.text_font_size or 15,
        text_font_bold = (opts.bold ~= false),
        bordersize = border_sz,
        radius = radius,
        width = opts.width,
        height = opts.height or sc(36),
        padding = opts.padding or 0,
        padding_h = opts.padding_h or sc(12),
        callback = opts.callback,
        enabled = is_enabled,
    }

    if not is_enabled then
        btn_opts.background = nil
        btn_opts.text_font_color = Blitbuffer.Color8(160)
    elseif is_primary then
        btn_opts.background = Blitbuffer.COLOR_BLACK
        btn_opts.text_font_color = Blitbuffer.COLOR_WHITE
    else
        btn_opts.background = opts.background
        btn_opts.text_font_color = opts.text_font_color or Blitbuffer.COLOR_BLACK
    end

    local btn = Button:new(btn_opts)
    btn.enabled = is_enabled
    if not is_enabled then
        if btn.label_widget then
            btn.label_widget.fgcolor = Blitbuffer.Color8(160)
        end
        if btn.frame then
            btn.frame.color = Blitbuffer.Color8(200)
            btn.frame.bordersize = border_sz
            btn.frame.invert = false
        end
    elseif is_primary and btn.label_widget then
        btn.label_widget.fgcolor = Blitbuffer.COLOR_WHITE
    end
    if is_enabled and btn.frame then
        btn.frame.color = opts.color or Blitbuffer.COLOR_BLACK
        btn.frame.bordersize = border_sz
    end
    return btn
end

local ImageGallery = InputContainer:extend{
    covers_fullscreen = true,
    modal = true,
    plugin = nil,
    current_page = 1,
    focused_index = nil,
    view_mode = "mosaic", -- "mosaic", "grid", "list"
    tab = "all",          -- "all", "favorites", "series", "hidden"
    filter_mode = "standard", -- "standard", "large_only", "all"
    focus_zone = nil,     -- "header", "tabs", "cards", "footer"
    header_focus_idx = 1, -- 1=view_mode, 2=filter, 3=close
    tab_focus_idx = 1,    -- 1=all, 2=favorites, 3=series, 4=hidden
    footer_focus_idx = 1, -- 1=prev, 2=next
}

function ImageGallery:init()
    self.modal = true
    self.covers_fullscreen = true
    self.sw = Screen:getWidth()
    self.sh = Screen:getHeight()
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
    self.is_touch_device = is_touch

    if not is_touch then
        self.focus_zone = self.focus_zone or "cards"
        self.focused_index = self.focused_index or 1
    else
        self.focus_zone = nil
        self.focused_index = nil
    end
    self.header_focus_idx = self.header_focus_idx or 1
    self.tab_focus_idx = self.tab_focus_idx or 1
    self.footer_focus_idx = self.footer_focus_idx or 1

    self.ges_events = {
        Swipe = {
            GestureRange:new{
                ges = "swipe",
                range = function() return Geom:new{ x = 0, y = 0, w = self.sw, h = self.sh } end
            }
        }
    }

    self.key_events = {
        NextCard = {
            { "Right" },
        },
        PrevCard = {
            { "Left" },
        },
        FocusUp = {
            { "Up" },
        },
        FocusDown = {
            { "Down" },
        },
        NextPage = {
            { "NextPage" },
            { "PageDown" },
            { "n" },
            { "N" },
            { "]" },
        },
        PrevPage = {
            { "PrevPage" },
            { "PageUp" },
            { "p" },
            { "P" },
            { "[" },
        },
        OpenFocused = {
            { "Return" },
            { "KP_Enter" },
            { "Enter" },
            { "Press" },
            { "Select" },
            { "Space" },
        },
        ImageActions = {
            { "Menu" },
            { "a" },
            { "A" },
            { "." },
            { "3" },
        },
        CycleTab = {
            { "t" },
            { "T" },
            { "Tab" },
        },
        CycleView = {
            { "v" },
            { "V" },
        },
        ToggleFilter = {
            { "f" },
            { "F" },
        },
        Select1 = { { "1" } },
        Select2 = { { "2" } },
        Select3 = { { "3" } },
        Select4 = { { "4" } },
        Select5 = { { "5" } },
        Select6 = { { "6" } },
        Select7 = { { "7" } },
        Select8 = { { "8" } },
        Select9 = { { "9" } },
        Close = {
            { "Escape" },
            { "Back" },
            { "q" },
            { "Q" },
        },
    }

    if Device and Device.input and Device.input.group then
        if Device.input.group.Enter then table.insert(self.key_events.OpenFocused, { Device.input.group.Enter }) end
        if Device.input.group.Select then table.insert(self.key_events.OpenFocused, { Device.input.group.Select }) end
        if Device.input.group.Back then table.insert(self.key_events.Close, { Device.input.group.Back }) end
    end

    self:buildUI()
end

function ImageGallery:onFocusUp()
    local old_page = self.current_page
    if not self.focus_zone then
        self.focus_zone = "cards"
        self.focused_index = 1
    elseif self.focus_zone == "footer" then
        self.focus_zone = "cards"
        local count = self.current_page_items and #self.current_page_items or 0
        self.focused_index = math.max(1, count)
    elseif self.focus_zone == "cards" then
        local cols = (self.view_mode == "list") and 1 or 2
        local f_idx = self.focused_index or 1
        if f_idx > cols then
            self.focused_index = f_idx - cols
        else
            self.focus_zone = "tabs"
            self.tab_focus_idx = math.min(4, math.max(1, f_idx))
        end
    elseif self.focus_zone == "tabs" then
        self.focus_zone = "header"
        self.header_focus_idx = math.min(3, math.max(1, self.tab_focus_idx or 1))
    elseif self.focus_zone == "header" then
        self.focus_zone = "footer"
        self.footer_focus_idx = 1
    end
    if not self[1] or self.current_page ~= old_page then
        self:buildUI()
    end
    UIManager:setDirty(self, "ui")
    return true
end

function ImageGallery:onFocusDown()
    local old_page = self.current_page
    if not self.focus_zone then
        self.focus_zone = "cards"
        self.focused_index = 1
    elseif self.focus_zone == "header" then
        self.focus_zone = "tabs"
        self.tab_focus_idx = math.min(4, self.header_focus_idx or 1)
    elseif self.focus_zone == "tabs" then
        self.focus_zone = "cards"
        self.focused_index = 1
    elseif self.focus_zone == "cards" then
        local count = self.current_page_items and #self.current_page_items or 0
        local cols = (self.view_mode == "list") and 1 or 2
        local f_idx = self.focused_index or 1
        if f_idx + cols <= count then
            self.focused_index = f_idx + cols
        elseif f_idx < count then
            self.focused_index = count
        else
            self.focus_zone = "footer"
            self.footer_focus_idx = 2
        end
    elseif self.focus_zone == "footer" then
        self.focus_zone = "header"
        self.header_focus_idx = 1
    end
    if not self[1] or self.current_page ~= old_page then
        self:buildUI()
    end
    UIManager:setDirty(self, "ui")
    return true
end

function ImageGallery:onFocusLeft()
    local old_page = self.current_page
    if not self.focus_zone then
        self.focus_zone = "cards"
        self.focused_index = 1
    elseif self.focus_zone == "header" then
        self.header_focus_idx = (self.header_focus_idx > 1) and (self.header_focus_idx - 1) or 3
    elseif self.focus_zone == "tabs" then
        self.tab_focus_idx = (self.tab_focus_idx > 1) and (self.tab_focus_idx - 1) or 4
    elseif self.focus_zone == "cards" then
        local count = self.current_page_items and #self.current_page_items or 0
        if count > 0 then
            local f_idx = self.focused_index or 1
            if f_idx > 1 then
                self.focused_index = f_idx - 1
            elseif self.current_page > 1 then
                self.current_page = self.current_page - 1
                self.focused_index = 1
            else
                self.focused_index = count
            end
        end
    elseif self.focus_zone == "footer" then
        self.footer_focus_idx = (self.footer_focus_idx > 1) and (self.footer_focus_idx - 1) or 2
    end
    if not self[1] or self.current_page ~= old_page then
        self:buildUI()
    end
    UIManager:setDirty(self, "ui")
    return true
end

function ImageGallery:onFocusRight()
    local old_page = self.current_page
    if not self.focus_zone then
        self.focus_zone = "cards"
        self.focused_index = 1
    elseif self.focus_zone == "header" then
        self.header_focus_idx = (self.header_focus_idx < 3) and (self.header_focus_idx + 1) or 1
    elseif self.focus_zone == "tabs" then
        self.tab_focus_idx = (self.tab_focus_idx < 4) and (self.tab_focus_idx + 1) or 1
    elseif self.focus_zone == "cards" then
        local count = self.current_page_items and #self.current_page_items or 0
        if count > 0 then
            local f_idx = self.focused_index or 1
            if f_idx < count then
                self.focused_index = f_idx + 1
            elseif self.current_page < (self.total_pages or 1) then
                self.current_page = self.current_page + 1
                self.focused_index = 1
            else
                self.focused_index = 1
            end
        end
    elseif self.focus_zone == "footer" then
        self.footer_focus_idx = (self.footer_focus_idx < 2) and (self.footer_focus_idx + 1) or 1
    end
    if not self[1] or self.current_page ~= old_page then
        self:buildUI()
    end
    UIManager:setDirty(self, "ui")
    return true
end

function ImageGallery:onNextCard()
    return self:onFocusRight()
end

function ImageGallery:onPrevCard()
    return self:onFocusLeft()
end

function ImageGallery:onOpenFocused()
    if not self.focus_zone then
        local img = self.current_page_items and self.current_page_items[1]
        if img then
            if self.openViewer then
                self:openViewer(img)
            elseif self.plugin and self.plugin.openImageViewer then
                self.plugin:openImageViewer(img)
            elseif self.plugin and self.plugin._launchImageViewer then
                self.plugin:_launchImageViewer(img)
            end
        end
        return true
    elseif self.focus_zone == "header" then
        if self.header_focus_idx == 1 then
            return self:onCycleView()
        elseif self.header_focus_idx == 2 then
            return self:onToggleFilter()
        elseif self.header_focus_idx == 3 then
            return self:onClose()
        end
    elseif self.focus_zone == "tabs" then
        local tabs = { "all", "favorites", "series", "hidden" }
        local target_tab = tabs[self.tab_focus_idx] or "all"
        self.tab = target_tab
        if self.plugin then self.plugin.image_tab = target_tab end
        self.current_page = 1
        self.focused_index = 1
        self.focus_zone = "cards"
        self:buildUI()
        UIManager:setDirty(self, "ui")
        return true
    elseif self.focus_zone == "cards" then
        local f_idx = self.focused_index or 1
        local img = self.current_page_items and self.current_page_items[f_idx]
        if img then
            if self.openViewer then
                self:openViewer(img)
            elseif self.plugin and self.plugin.openImageViewer then
                self.plugin:openImageViewer(img)
            elseif self.plugin and self.plugin._launchImageViewer then
                self.plugin:_launchImageViewer(img)
            end
        end
        return true
    elseif self.focus_zone == "footer" then
        if self.footer_focus_idx == 1 then
            return self:onPrevPage()
        else
            return self:onNextPage()
        end
    end
    return true
end

function ImageGallery:onImageActions()
    local f_idx = self.focused_index or 1
    local img = self.current_page_items and self.current_page_items[f_idx]
    if img and self.plugin then
        self.plugin:showImageActions(img)
    end
    return true
end

function ImageGallery:onCycleTab()
    local tabs = { "all", "favorites", "series", "hidden" }
    local cur_idx = 1
    for i, t in ipairs(tabs) do
        if t == self.tab then cur_idx = i; break end
    end
    local next_tab = tabs[(cur_idx % #tabs) + 1]
    self.tab = next_tab
    self.tab_focus_idx = (cur_idx % #tabs) + 1
    if self.plugin then self.plugin.image_tab = next_tab end
    self.current_page = 1
    self.focused_index = 1
    self:buildUI()
    UIManager:setDirty(self, "ui")
    return true
end

function ImageGallery:onCycleView()
    if self.view_mode == "mosaic" then
        self.view_mode = "grid"
    elseif self.view_mode == "grid" then
        self.view_mode = "list"
    else
        self.view_mode = "mosaic"
    end
    if self.plugin then self.plugin.image_view_mode = self.view_mode end
    self.current_page = 1
    self.focused_index = 1
    self:buildUI()
    UIManager:setDirty(self, "ui")
    return true
end

function ImageGallery:onToggleFilter()
    if self.filter_mode == "maps_only" or self.filter_mode == "large_only" then
        self.filter_mode = "all"
    else
        self.filter_mode = "maps_only"
    end
    if self.plugin then self.plugin.image_filter_mode = self.filter_mode end
    self.current_page = 1
    self.focused_index = 1
    self:buildUI()
    UIManager:setDirty(self, "ui")
    return true
end

local function _openDirect(self, idx)
    local img = self.current_page_items and self.current_page_items[idx]
    if img then
        self.focus_zone = "cards"
        self.focused_index = idx
        if self.openViewer then
            self:openViewer(img)
        elseif self.plugin and self.plugin.openImageViewer then
            self.plugin:openImageViewer(img)
        elseif self.plugin and self.plugin._launchImageViewer then
            self.plugin:_launchImageViewer(img)
        end
    end
    return true
end

function ImageGallery:onSelect1() return _openDirect(self, 1) end
function ImageGallery:onSelect2() return _openDirect(self, 2) end
function ImageGallery:onSelect3() return _openDirect(self, 3) end
function ImageGallery:onSelect4() return _openDirect(self, 4) end
function ImageGallery:onSelect5() return _openDirect(self, 5) end
function ImageGallery:onSelect6() return _openDirect(self, 6) end
function ImageGallery:onSelect7() return _openDirect(self, 7) end
function ImageGallery:onSelect8() return _openDirect(self, 8) end
function ImageGallery:onSelect9() return _openDirect(self, 9) end

function ImageGallery:onNextPage()
    if self.current_page < self.total_pages then
        self.current_page = self.current_page + 1
        self.focused_index = 1
        self:buildUI()
        UIManager:setDirty(self, "ui")
    end
    return true
end

function ImageGallery:onPrevPage()
    if self.current_page > 1 then
        self.current_page = self.current_page - 1
        self.focused_index = 1
        self:buildUI()
        UIManager:setDirty(self, "ui")
    end
    return true
end

function ImageGallery:onClose()
    self:close()
    return true
end

function ImageGallery:onSwipe(arg, ges)
    if self.is_touch_device and self.focus_zone then
        self.focus_zone = nil
        self.focused_index = nil
    end
    if ges.direction == "west" or ges.direction == "left" then
        return self:onNextPage()
    elseif ges.direction == "east" or ges.direction == "right" then
        return self:onPrevPage()
    end
end

function ImageGallery:handleEvent(ev)
    if ev.type == "Key" or ev.type == "KeyPress" or ev.type == "KeyDown" then
        local key = ev.key or ev.name or ev.sym
        if key == "Return" or key == "KP_Enter" or key == "Enter" or key == "Select" or key == "Space" or key == "Press" then
            return self:onOpenFocused()
        elseif key == "Up" then
            return self:onFocusUp()
        elseif key == "Down" then
            return self:onFocusDown()
        elseif key == "Left" then
            return self:onFocusLeft()
        elseif key == "Right" then
            return self:onFocusRight()
        elseif key == "a" or key == "A" or key == "Menu" or key == "." or key == "3" then
            return self:onImageActions()
        elseif key == "v" or key == "V" then
            return self:onCycleView()
        elseif key == "t" or key == "T" or key == "Tab" then
            return self:onCycleTab()
        elseif key == "f" or key == "F" then
            return self:onToggleFilter()
        elseif key == "p" or key == "P" or key == "PageUp" or key == "PrevPage" or key == "[" then
            return self:onPrevPage()
        elseif key == "n" or key == "N" or key == "PageDown" or key == "NextPage" or key == "]" then
            return self:onNextPage()
        elseif key == "Escape" or key == "Back" or key == "q" or key == "Q" then
            return self:onClose()
        elseif key == "1" then return self:onSelect1()
        elseif key == "2" then return self:onSelect2()
        elseif key == "3" then return self:onSelect3()
        elseif key == "4" then return self:onSelect4()
        elseif key == "5" then return self:onSelect5()
        elseif key == "6" then return self:onSelect6()
        elseif key == "7" then return self:onSelect7()
        elseif key == "8" then return self:onSelect8()
        elseif key == "9" then return self:onSelect9()
        end
    end
    return InputContainer.handleEvent(self, ev)
end

function ImageGallery:buildUI()
    local sw = self.sw
    local sh = self.sh
    local p = self.plugin

    local series_images = {}
    local series_info = p.getCurrentSeriesInfo and p:getCurrentSeriesInfo()
    local series_slug = series_info and series_info.slug
    if p.series_manager and series_slug and series_slug ~= "" and series_slug ~= "series" then
        local max_idx = (series_info and series_info.index) or (p.book_data and p.book_data.series_index) or 1
        series_images = p.series_manager:getSeriesImages(series_slug, max_idx) or {}
    end

    local current_book_page = nil
    if p.ui and p.ui.document and p.ui.document.getCurrentPage then
        current_book_page = p.ui.document:getCurrentPage()
    end

    local filtered = p.image_manager:getFilteredImages(p.images or {}, self.tab, current_book_page, self.filter_mode, series_images)

    -- ── 1. Top Header Bar ────────────────────────────────────────────────────────
    local btn_size = sc(32)
    local btn_w = sc(38)
    local btn_gap = sc(18)
    local num_header_btns = 3
    local actions_total_w = (btn_w * num_header_btns) + (btn_gap * (num_header_btns - 1))

    local is_view_focused = (self.focus_zone == "header" and self.header_focus_idx == 1)
    local is_filter_focused = (self.focus_zone == "header" and self.header_focus_idx == 2)
    local is_close_focused = (self.focus_zone == "header" and self.header_focus_idx == 3)

    local mode_icon = (self.view_mode == "mosaic" and "trello.svg") or (self.view_mode == "grid" and "grid.svg" or "list.svg")
    local view_mode_btn = createIconButton{
        icon = mode_icon,
        size = btn_size,
        width = btn_w,
        height = btn_w,
        bordersize = is_view_focused and (theme.border_focus or sc(3)) or 0,
        color = is_view_focused and (theme.color_focus_border or Blitbuffer.COLOR_BLACK) or nil,
        background = is_view_focused and (theme.color_focus_bg or Blitbuffer.Color8(215)) or nil,
        padding = 0,
        padding_h = 0,
        callback = function()
            if self.is_touch_device then
                self.focus_zone = nil
                self.focused_index = nil
            end
            if self.view_mode == "mosaic" then
                self.view_mode = "grid"
            elseif self.view_mode == "grid" then
                self.view_mode = "list"
            else
                self.view_mode = "mosaic"
            end
            p.image_view_mode = self.view_mode
            self.cached_pages = nil
            self.current_page = 1
            self:buildUI()
            UIManager:setDirty(self, "ui")
        end,
    }
    view_mode_btn.onBeforePaint = function()
        local focused = (self.focus_zone == "header" and self.header_focus_idx == 1)
        if view_mode_btn.frame then
            view_mode_btn.frame.bordersize = focused and (theme.border_focus or sc(3)) or 0
            view_mode_btn.frame.color = focused and (theme.color_focus_border or Blitbuffer.COLOR_BLACK) or nil
            view_mode_btn.frame.background = focused and (theme.color_focus_bg or Blitbuffer.Color8(215)) or nil
        end
    end

    local filter_btn = createIconButton{
        icon = "filter.svg",
        size = btn_size,
        width = btn_w,
        height = btn_w,
        bordersize = is_filter_focused and (theme.border_focus or sc(3)) or 0,
        color = is_filter_focused and (theme.color_focus_border or Blitbuffer.COLOR_BLACK) or nil,
        background = is_filter_focused and (theme.color_focus_bg or Blitbuffer.Color8(215)) or nil,
        padding = 0,
        padding_h = 0,
        callback = function()
            if self.is_touch_device then
                self.focus_zone = nil
                self.focused_index = nil
            end
            if self.filter_mode == "maps_only" or self.filter_mode == "large_only" then
                self.filter_mode = "all"
            else
                self.filter_mode = "maps_only"
            end
            p.image_filter_mode = self.filter_mode
            self.cached_pages = nil
            self.current_page = 1
            self:buildUI()
            UIManager:setDirty(self, "ui")
        end,
    }
    filter_btn.onBeforePaint = function()
        local focused = (self.focus_zone == "header" and self.header_focus_idx == 2)
        if filter_btn.frame then
            filter_btn.frame.bordersize = focused and (theme.border_focus or sc(3)) or 0
            filter_btn.frame.color = focused and (theme.color_focus_border or Blitbuffer.COLOR_BLACK) or nil
            filter_btn.frame.background = focused and (theme.color_focus_bg or Blitbuffer.Color8(215)) or nil
        end
    end

    local close_btn = createIconButton{
        icon = "x.svg",
        size = btn_size,
        width = btn_w,
        height = btn_w,
        bordersize = is_close_focused and (theme.border_focus or sc(3)) or 0,
        color = is_close_focused and (theme.color_focus_border or Blitbuffer.COLOR_BLACK) or nil,
        background = is_close_focused and (theme.color_focus_bg or Blitbuffer.Color8(215)) or nil,
        padding = 0,
        padding_h = 0,
        callback = function()
            self:close()
        end,
    }
    close_btn.onBeforePaint = function()
        local focused = (self.focus_zone == "header" and self.header_focus_idx == 3)
        if close_btn.frame then
            close_btn.frame.bordersize = focused and (theme.border_focus or sc(3)) or 0
            close_btn.frame.color = focused and (theme.color_focus_border or Blitbuffer.COLOR_BLACK) or nil
            close_btn.frame.background = focused and (theme.color_focus_bg or Blitbuffer.Color8(215)) or nil
        end
    end

    local header_actions = HorizontalGroup:new{
        align = "center",
        view_mode_btn,
        HorizontalSpan:new{ width = btn_gap },
        filter_btn,
        HorizontalSpan:new{ width = btn_gap },
        close_btn,
    }

    local map_icon = ImageWidget:new{
        file = getAssetPath("map.svg"),
        width = sc(24),
        height = sc(24),
        scale_factor = 0,
        is_icon = true,
        alpha = true,
    }

    local filter_label_str = (self.filter_mode == "maps_only" or self.filter_mode == "large_only") and "Maps & Diagrams Only" or "All Images"
    local title_max_w = sw - sc(32) - actions_total_w - sc(36)
    
    local title_text = TextWidget:new{
        text = "X-Ray · " .. (p.loc:t("menu_images") or "Images & Maps"),
        face = Font:getFace("cfont", 21),
        bold = true,
        fgcolor = Blitbuffer.COLOR_BLACK,
        max_width = title_max_w,
    }

    local sub_str
    if self.tab == "favorites" then
        sub_str = string.format("%d %s", #filtered, (#filtered == 1 and "favorite image" or "favorite images"))
    elseif self.tab == "series" then
        if series_info and series_info.name then
            sub_str = string.format("%d %s across %s", #filtered, (#filtered == 1 and "map / reference" or "maps / references"), series_info.name)
        else
            sub_str = string.format("%d %s across series", #filtered, (#filtered == 1 and "map / reference" or "maps / references"))
        end
    elseif self.tab == "hidden" then
        sub_str = string.format("%d %s", #filtered, (#filtered == 1 and "hidden image" or "hidden images"))
    else
        sub_str = string.format("%d %s  ·  Filter: %s", #filtered, (#filtered == 1 and "item" or "items"), filter_label_str)
    end

    local filter_sub_text = TextWidget:new{
        text = sub_str,
        face = Font:getFace("cfont", 14),
        bold = true,
        fgcolor = Blitbuffer.COLOR_BLACK,
        max_width = title_max_w,
    }

    local header_title_vg = VerticalGroup:new{
        align = "left",
        title_text,
        filter_sub_text,
    }

    local header_title_left = HorizontalGroup:new{
        align = "center",
        map_icon,
        HorizontalSpan:new{ width = sc(6) },
        header_title_vg,
    }

    local row_w = sw - sc(24)
    local header_top_row = OverlapGroup:new{
        dimen = Geom:new{ w = row_w, h = sc(40) },
        LeftContainer:new{
            dimen = Geom:new{ w = row_w - actions_total_w - sc(12), h = sc(40) },
            header_title_left,
        },
        RightContainer:new{
            dimen = Geom:new{ w = row_w, h = sc(40) },
            header_actions,
        },
    }

    -- ── 2. Segmented Tab Bar ───────────────────────────────────────────────────
    local fav_count = 0
    local hidden_count = 0
    for _, img in ipairs(p.images or {}) do
        if img.is_favorite then fav_count = fav_count + 1 end
        if img.is_hidden then hidden_count = hidden_count + 1 end
    end

    local all_tab_items = p.image_manager:getFilteredImages(p.images or {}, "all", current_book_page, self.filter_mode, series_images)
    local all_filtered_count = #all_tab_items

    local tab_h = sc(32)
    local tab_gap = sc(6)
    local hidden_tab_w = (hidden_count > 0) and sc(46) or sc(36)
    local total_gaps = tab_gap * 3
    local main_tab_w = math.floor((sw - sc(32) - total_gaps - hidden_tab_w) / 3)

    local function createTabBtn(label, tab_key, count, icon_file, custom_w, tab_idx)
        local is_active = (self.tab == tab_key)
        local is_focused_tab = (self.focus_zone == "tabs" and self.tab_focus_idx == tab_idx)
        local btn_w = custom_w or main_tab_w
        local content_widget

        local effective_icon_file = icon_file
        if is_active and icon_file then
            effective_icon_file = icon_file:gsub("%.svg$", "-white.svg")
        end

        if tab_key == "hidden" then
            local hidden_icon = is_active and "eye-off-white.svg" or (icon_file or "eye-off.svg")
            local icon_w = ImageWidget:new{
                file = getAssetPath(hidden_icon),
                width = sc(16),
                height = sc(16),
                scale_factor = 0,
                is_icon = true,
                alpha = true,
            }
            if count and count > 0 then
                local count_txt = TextWidget:new{
                    text = tostring(count),
                    face = Font:getFace("cfont", 13),
                    bold = is_active or is_focused_tab,
                    fgcolor = is_active and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK,
                }
                content_widget = HorizontalGroup:new{
                    align = "center",
                    icon_w,
                    HorizontalSpan:new{ width = sc(3) },
                    count_txt,
                }
            else
                content_widget = icon_w
            end
        else
            local display_label = (label or "") .. " (" .. tostring(count) .. ")"
            local txt = TextWidget:new{
                text = display_label,
                face = Font:getFace("cfont", 14),
                bold = is_active or is_focused_tab,
                fgcolor = is_active and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK,
            }
            content_widget = txt
            if icon_file then
                local icon_w = ImageWidget:new{
                    file = getAssetPath(effective_icon_file),
                    width = sc(15),
                    height = sc(15),
                    scale_factor = 0,
                    is_icon = true,
                    alpha = true,
                }
                content_widget = HorizontalGroup:new{
                    align = "center",
                    icon_w,
                    HorizontalSpan:new{ width = sc(4) },
                    txt,
                }
            end
        end

        local frame = FrameContainer:new{
            padding = sc(3),
            bordersize = is_focused_tab and (theme.border_focus or sc(3)) or sc(1),
            color = is_focused_tab and (theme.color_focus_border or Blitbuffer.COLOR_BLACK) or (is_active and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY),
            background = is_active and Blitbuffer.COLOR_BLACK or (is_focused_tab and (theme.color_focus_bg or Blitbuffer.Color8(215)) or Blitbuffer.COLOR_WHITE),
            radius = sc(4),
            CenterContainer:new{
                dimen = Geom:new{ w = btn_w - sc(8), h = tab_h - sc(8) },
                content_widget,
            }
        }
        local tab_item = makeTapItem(frame, function()
            if self.is_touch_device then
                self.focus_zone = nil
                self.focused_index = nil
            end
            self.tab = tab_key
            self.tab_focus_idx = tab_idx or 1
            p.image_tab = tab_key
            self.cached_pages = nil
            self.current_page = 1
            self:buildUI()
            UIManager:setDirty(self, "ui")
        end)
        tab_item.onBeforePaint = function()
            local focused = (self.focus_zone == "tabs" and self.tab_focus_idx == tab_idx)
            local active = (self.tab == tab_key)
            frame.bordersize = focused and (theme.border_focus or sc(3)) or sc(1)
            frame.color = focused and (theme.color_focus_border or Blitbuffer.COLOR_BLACK) or (active and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY)
            frame.background = active and Blitbuffer.COLOR_BLACK or (focused and (theme.color_focus_bg or Blitbuffer.Color8(215)) or Blitbuffer.COLOR_WHITE)
        end
        return tab_item
    end

    local tab_bar = HorizontalGroup:new{
        align = "center",
        createTabBtn(p.loc:t("img_tab_all") or "All", "all", all_filtered_count, nil, nil, 1),
        HorizontalSpan:new{ width = tab_gap },
        createTabBtn(p.loc:t("img_tab_favorites") or "Favorites", "favorites", fav_count, "star.svg", nil, 2),
        HorizontalSpan:new{ width = tab_gap },
        createTabBtn(p.loc:t("img_tab_series") or "Series", "series", #series_images, "book-open.svg", nil, 3),
        HorizontalSpan:new{ width = tab_gap },
        createTabBtn(nil, "hidden", hidden_count, "eye-off.svg", hidden_tab_w, 4),
    }

    local header_vg = VerticalGroup:new{
        align = "left",
        header_top_row,
        VerticalSpan:new{ width = sc(8) },
        tab_bar,
        VerticalSpan:new{ width = sc(8) },
        LineWidget:new{
            background = Blitbuffer.COLOR_DARK_GRAY,
            dimen = Geom:new{ w = sw - sc(32), h = sc(1) },
        },
    }

    local header_frame = FrameContainer:new{
        padding = sc(12),
        padding_top = sc(14),
        padding_bottom = sc(4),
        bordersize = 0,
        width = sw,
        header_vg,
    }

    local header_h = header_frame:getSize().h
    local footer_h = sc(48)
    local avail_content_h = sh - header_h - footer_h - sc(8)
    self.avail_content_h = avail_content_h
    self.footer_h = footer_h
    self.max_mosaic_thumb_h = math.floor(avail_content_h * 0.46)

    -- ── 3. Page Layout Budgeting ───────────────────────────────────────────────
    local margin_h = sc(12)
    local content_w = sw - (margin_h * 2)
    local grid_gap = sc(10)
    local grid_gap_v = sc(8)

    local COLS = (sw >= 700 and self.view_mode == "grid") and 3 or 2
    local cell_w = math.floor((content_w - (grid_gap * (COLS - 1))) / COLS)

    local pages = {}
    local cur_page_items = {}

    if self.cached_tab == self.tab and self.cached_filter_mode == self.filter_mode and self.cached_view_mode == self.view_mode and self.cached_pages then
        pages = self.cached_pages
    else
        if self.view_mode == "list" then
            local row_h = sc(82)
            local row_gap = sc(6)
            local items_per_page = math.max(1, math.floor((avail_content_h + row_gap) / (row_h + row_gap)))
            for idx, img in ipairs(filtered) do
                table.insert(cur_page_items, img)
                if #cur_page_items == items_per_page or idx == #filtered then
                    table.insert(pages, cur_page_items)
                    cur_page_items = {}
                end
            end
        elseif self.view_mode == "mosaic" then
            -- ── Dynamic Height-Budget Mosaic Pagination ───────────────────────────
            local col1_h = 0
            local col2_h = 0
            for idx, img in ipairs(filtered) do
                local aspect_ratio = 0.75
                if img.aspect_ratio and img.aspect_ratio > 0 then
                    aspect_ratio = img.aspect_ratio
                elseif img.width and img.height and tonumber(img.width) and tonumber(img.height) and tonumber(img.width) > 0 then
                    aspect_ratio = tonumber(img.height) / tonumber(img.width)
                    img.aspect_ratio = aspect_ratio
                else
                    local local_file = img.cached_file
                    if not local_file and book_path and not img.is_spoiler then
                        local_file = p.image_manager:extractImageToFile(book_path, img)
                    end
                    if local_file then
                        local nat_w, nat_h = getImageDimensions(local_file)
                        if nat_w and nat_h and nat_w > 0 and nat_h > 0 then
                            aspect_ratio = nat_h / nat_w
                            img.aspect_ratio = aspect_ratio
                            img.width = nat_w
                            img.height = nat_h
                        end
                    end
                end
                aspect_ratio = math.max(0.15, math.min(1.85, aspect_ratio))
                local thumb_h = math.min(math.floor(cell_w * aspect_ratio), avail_content_h)
                local est_h = thumb_h + grid_gap_v

                if col1_h <= col2_h then
                    if (col1_h + est_h > avail_content_h) and (#cur_page_items > 0) then
                        table.insert(pages, cur_page_items)
                        cur_page_items = { img }
                        col1_h = est_h
                        col2_h = 0
                    else
                        table.insert(cur_page_items, img)
                        col1_h = col1_h + est_h
                    end
                else
                    if (col2_h + est_h > avail_content_h) and (#cur_page_items > 0) then
                        table.insert(pages, cur_page_items)
                        cur_page_items = { img }
                        col1_h = est_h
                        col2_h = 0
                    else
                        table.insert(cur_page_items, img)
                        col2_h = col2_h + est_h
                    end
                end

                if idx == #filtered and #cur_page_items > 0 then
                    table.insert(pages, cur_page_items)
                    cur_page_items = {}
                end
            end
        else
            -- Uniform Grid with 1:1 Square Thumbnails
            local inner_w = cell_w
            local card_h = inner_w + sc(36)
            local rows_can_fit = math.max(1, math.floor((avail_content_h + grid_gap_v) / (card_h + grid_gap_v)))
            local items_per_page = rows_can_fit * COLS
            for idx, img in ipairs(filtered) do
                table.insert(cur_page_items, img)
                if #cur_page_items == items_per_page or idx == #filtered then
                    table.insert(pages, cur_page_items)
                    cur_page_items = {}
                end
            end
        end

        self.cached_tab = self.tab
        self.cached_filter_mode = self.filter_mode
        self.cached_view_mode = self.view_mode
        self.cached_pages = pages
    end

    self.total_pages = math.max(1, #pages)
    if self.current_page > self.total_pages then self.current_page = self.total_pages end
    if self.current_page < 1 then self.current_page = 1 end

    local page_items = pages[self.current_page] or {}
    self.current_page_items = page_items
    if self.focused_index and #page_items > 0 then
        if self.focused_index > #page_items then self.focused_index = #page_items end
        if self.focused_index < 1 then self.focused_index = 1 end
    elseif not self.is_touch_device then
        self.focused_index = 1
    end

    local page_content_vg = VerticalGroup:new{ align = "left" }

    if #filtered == 0 then
        local empty_msg = p.loc:t("img_no_images") or "No images found for this tab/filter.\n\nExtracting or scanning images from book..."
        if self.tab == "hidden" then
            empty_msg = p.loc:t("img_no_hidden") or "No hidden images.\n\nUse the ⋮ menu on any image in the gallery to hide decorative illustrations or drop caps."
        elseif self.tab == "favorites" then
            empty_msg = p.loc:t("img_no_favorites") or "No favorites yet.\n\nUse the ⋮ menu on any image to add it to your favorites."
        elseif self.tab == "series" then
            if not series_info then
                empty_msg = p.loc:t("img_no_series_detected") or "This book is not part of a recognized series.\n\nSeries references are only available for books in a series."
            else
                empty_msg = p.loc:t("img_no_series") or "No series references saved.\n\nUse the ⋮ menu on any map to save it to your series references."
            end
        end
        local empty_text = TextBoxWidget:new{
            text = empty_msg,
            face = Font:getFace("cfont", 16),
            fgcolor = Blitbuffer.COLOR_BLACK,
            width = sw - sc(40),
            alignment = "center",
        }
        table.insert(page_content_vg, FrameContainer:new{
            padding = sc(20),
            bordersize = 0,
            width = sw,
            CenterContainer:new{
                dimen = Geom:new{ w = sw - sc(40), h = avail_content_h - sc(20) },
                empty_text,
            }
        })
    elseif self.view_mode == "list" then
        for idx, img in ipairs(page_items) do
            local is_focused = (self.focus_zone == "cards" and idx == self.focused_index)
            local item_widget = self:renderListRow(img, content_w, is_focused, idx)
            item_widget.gallery = self
            table.insert(page_content_vg, item_widget)
            table.insert(page_content_vg, VerticalSpan:new{ width = sc(6) })
        end
    elseif self.view_mode == "mosaic" then
        -- ── TRUE MOSAIC / MASONRY LAYOUT ──────────────────────────────────────
        local col1_items = {}
        local col2_items = {}
        local col1_h = 0
        local col2_h = 0

        for idx, img in ipairs(page_items) do
            local card_w = cell_w
            local is_focused = (self.focus_zone == "cards" and idx == self.focused_index)
            local card_widget, estimated_h = self:renderMosaicCard(img, card_w, is_focused, idx)
            card_widget.gallery = self
            
            if col1_h <= col2_h then
                table.insert(col1_items, card_widget)
                table.insert(col1_items, VerticalSpan:new{ width = grid_gap_v })
                col1_h = col1_h + estimated_h + grid_gap_v
            else
                table.insert(col2_items, card_widget)
                table.insert(col2_items, VerticalSpan:new{ width = grid_gap_v })
                col2_h = col2_h + estimated_h + grid_gap_v
            end
        end

        local col1_vg = VerticalGroup:new(col1_items)
        col1_vg.align = "left"
        local col2_vg = VerticalGroup:new(col2_items)
        col2_vg.align = "left"

        local masonry_row = HorizontalGroup:new{
            align = "top",
            HorizontalSpan:new{ width = margin_h },
            col1_vg,
            HorizontalSpan:new{ width = grid_gap },
            col2_vg,
            HorizontalSpan:new{ width = margin_h },
        }
        table.insert(page_content_vg, masonry_row)
    else
        -- ── STOREFRONT SCREENSAVER STYLE GRID VIEW ───────────────────────────
        local current_row_widgets = {}
        for i, img in ipairs(page_items) do
            local is_focused = (self.focus_zone == "cards" and i == self.focused_index)
            local card_widget = self:renderGridCard(img, cell_w, is_focused, i)
            card_widget.gallery = self
            table.insert(current_row_widgets, card_widget)

            if #current_row_widgets == COLS or i == #page_items then
                local row_items = { HorizontalSpan:new{ width = margin_h } }
                for col_i, cell in ipairs(current_row_widgets) do
                    if col_i > 1 then
                        table.insert(row_items, HorizontalSpan:new{ width = grid_gap })
                    end
                    table.insert(row_items, cell)
                end
                table.insert(row_items, HorizontalSpan:new{ width = margin_h })
                local row_group = HorizontalGroup:new(row_items)
                row_group.align = "top"
                table.insert(page_content_vg, row_group)
                table.insert(page_content_vg, VerticalSpan:new{ width = grid_gap_v })
                current_row_widgets = {}
            end
        end
    end

    -- ── 4. Fixed Bottom Pagination Bar (Always Anchored at Bottom) ─────────────
    local is_prev_focused = (self.focus_zone == "footer" and self.footer_focus_idx == 1)
    local is_next_focused = (self.focus_zone == "footer" and self.footer_focus_idx == 2)
    local can_prev = self.current_page > 1
    local can_next = self.current_page < self.total_pages

    local prev_btn = createButton{
        text = "‹ " .. (p.loc:t("prev") or "Prev"),
        width = sc(85),
        height = sc(34),
        enabled = can_prev,
        bold = is_prev_focused,
        bordersize = is_prev_focused and (theme.border_focus or sc(3)) or sc(1),
        color = not can_prev and Blitbuffer.Color8(200) or (is_prev_focused and (theme.color_focus_border or Blitbuffer.COLOR_BLACK) or Blitbuffer.COLOR_BLACK),
        background = is_prev_focused and (theme.color_focus_bg or Blitbuffer.Color8(215)) or nil,
        callback = function()
            if self.is_touch_device then
                self.focus_zone = nil
                self.focused_index = nil
            end
            if self.current_page > 1 then
                self.current_page = self.current_page - 1
                self:buildUI()
                UIManager:setDirty(self, "ui")
            end
        end,
    }

    local next_btn = createButton{
        text = (p.loc:t("next") or "Next") .. " ›",
        width = sc(85),
        height = sc(34),
        enabled = can_next,
        bold = is_next_focused,
        bordersize = is_next_focused and (theme.border_focus or sc(3)) or sc(1),
        color = not can_next and Blitbuffer.Color8(200) or (is_next_focused and (theme.color_focus_border or Blitbuffer.COLOR_BLACK) or Blitbuffer.COLOR_BLACK),
        background = is_next_focused and (theme.color_focus_bg or Blitbuffer.Color8(215)) or nil,
        callback = function()
            if self.is_touch_device then
                self.focus_zone = nil
                self.focused_index = nil
            end
            if self.current_page < self.total_pages then
                self.current_page = self.current_page + 1
                self:buildUI()
                UIManager:setDirty(self, "ui")
            end
        end,
    }

    local orig_prev_paint = prev_btn.paintTo
    prev_btn.paintTo = function(this, bb, x, y)
        if not this.enabled then
            this.bordersize = sc(1)
            this.color = Blitbuffer.Color8(200)
            this.background = nil
            if this.frame then
                this.frame.bordersize = sc(1)
                this.frame.color = Blitbuffer.Color8(200)
                this.frame.background = nil
                this.frame.invert = false
            end
            if this.label_widget then
                this.label_widget.fgcolor = Blitbuffer.Color8(160)
            end
        else
            local focused = (self.focus_zone == "footer" and self.footer_focus_idx == 1)
            this.bordersize = focused and (theme.border_focus or sc(3)) or sc(1)
            this.color = focused and (theme.color_focus_border or Blitbuffer.COLOR_BLACK) or Blitbuffer.COLOR_BLACK
            this.background = focused and (theme.color_focus_bg or Blitbuffer.Color8(215)) or nil
            if this.frame then
                this.frame.bordersize = this.bordersize
                this.frame.color = this.color
                this.frame.background = this.background
            end
            if this.label_widget then
                this.label_widget.fgcolor = Blitbuffer.COLOR_BLACK
            end
        end
        if orig_prev_paint then
            orig_prev_paint(this, bb, x, y)
        end
    end

    local orig_next_paint = next_btn.paintTo
    next_btn.paintTo = function(this, bb, x, y)
        if not this.enabled then
            this.bordersize = sc(1)
            this.color = Blitbuffer.Color8(200)
            this.background = nil
            if this.frame then
                this.frame.bordersize = sc(1)
                this.frame.color = Blitbuffer.Color8(200)
                this.frame.background = nil
                this.frame.invert = false
            end
            if this.label_widget then
                this.label_widget.fgcolor = Blitbuffer.Color8(160)
            end
        else
            local focused = (self.focus_zone == "footer" and self.footer_focus_idx == 2)
            this.bordersize = focused and (theme.border_focus or sc(3)) or sc(1)
            this.color = focused and (theme.color_focus_border or Blitbuffer.COLOR_BLACK) or Blitbuffer.COLOR_BLACK
            this.background = focused and (theme.color_focus_bg or Blitbuffer.Color8(215)) or nil
            if this.frame then
                this.frame.bordersize = this.bordersize
                this.frame.color = this.color
                this.frame.background = this.background
            end
            if this.label_widget then
                this.label_widget.fgcolor = Blitbuffer.COLOR_BLACK
            end
        end
        if orig_next_paint then
            orig_next_paint(this, bb, x, y)
        end
    end

    local page_label = TextWidget:new{
        text = string.format("%d / %d", self.current_page, self.total_pages),
        face = Font:getFace("cfont", 15),
        bold = true,
        fgcolor = Blitbuffer.COLOR_BLACK,
    }

    local page_center = CenterContainer:new{
        dimen = Geom:new{ w = sw - sc(32) - (sc(85) * 2), h = sc(34) },
        page_label,
    }

    self.prev_btn = prev_btn
    self.next_btn = next_btn

    local footer_row = HorizontalGroup:new{
        align = "center",
        prev_btn,
        page_center,
        next_btn,
    }

    local footer_frame = FrameContainer:new{
        padding = sc(6),
        padding_h = sc(16),
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        width = sw,
        height = footer_h,
        footer_row,
    }

    -- ── 5. Assemble Full-Screen Window (Fixed Bottom Footer) ─────────────────
    local content_area = FrameContainer:new{
        padding = 0,
        bordersize = 0,
        width = sw,
        height = avail_content_h,
        page_content_vg,
    }

    local main_surface = FrameContainer:new{
        padding = 0,
        bordersize = theme.border_window or sc(1),
        color = Blitbuffer.COLOR_BLACK,
        background = Blitbuffer.COLOR_WHITE,
        width = sw,
        height = sh,
        VerticalGroup:new{
            align = "left",
            header_frame,
            content_area,
        }
    }

    local bottom_pinned_footer = BottomContainer:new{
        dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh },
        footer_frame,
    }

    self[1] = OverlapGroup:new{
        main_surface,
        bottom_pinned_footer,
    }
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
end

-- ── Mosaic Card (No Titles, Overlapped 3-Dot Menu, 100% Uncut Natural Aspect Ratio)
function ImageGallery:renderMosaicCard(img, cell_w, is_focused_or_idx, opt_idx)
    local idx = opt_idx or (type(is_focused_or_idx) == "number" and is_focused_or_idx) or 1
    local p = self.plugin
    local book_path = p.ui and p.ui.document and p.ui.document.file

    local thumb_w = cell_w

    local local_file = img.cached_file
    if not local_file and book_path and not img.is_spoiler then
        local_file = p.image_manager:extractImageToFile(book_path, img)
    end

    -- 1. Determine REAL natural aspect ratio from file header or metadata
    local aspect_ratio = 0.75
    if img.aspect_ratio and img.aspect_ratio > 0 then
        aspect_ratio = img.aspect_ratio
    else
        local nat_w, nat_h = getImageDimensions(local_file)
        if nat_w and nat_h and nat_w > 0 and nat_h > 0 then
            aspect_ratio = nat_h / nat_w
            img.aspect_ratio = aspect_ratio
            img.width = nat_w
            img.height = nat_h
        elseif img.width and img.height and tonumber(img.width) and tonumber(img.height) and tonumber(img.width) > 0 then
            aspect_ratio = tonumber(img.height) / tonumber(img.width)
            img.aspect_ratio = aspect_ratio
        end
    end

    aspect_ratio = math.max(0.15, math.min(1.85, aspect_ratio))
    local avail_h = self.avail_content_h or (self.sh and (self.sh - sc(140))) or 500
    local thumb_h = math.min(math.floor(thumb_w * aspect_ratio), avail_h)

    local image_widget = nil

    if img.is_spoiler and p.ai_helper and p.ai_helper.settings and p.ai_helper.settings.no_spoilers ~= false then
        local lock_icon = ImageWidget:new{
            file = getAssetPath("lock.svg"),
            width = sc(24),
            height = sc(24),
            scale_factor = 0,
            is_icon = true,
            alpha = true,
        }
        local lock_txt = TextWidget:new{
            text = p.loc:t("img_spoiler_locked") or "Spoiler Protected",
            face = Font:getFace("cfont", 12),
            bold = true,
            fgcolor = Blitbuffer.COLOR_BLACK,
        }
        local lock_vg = VerticalGroup:new{
            align = "center",
            lock_icon,
            VerticalSpan:new{ width = sc(2) },
            lock_txt,
        }
        image_widget = CenterContainer:new{
            dimen = Geom:new{ w = thumb_w, h = thumb_h },
            lock_vg,
        }
    else
        if local_file then
            -- Full uncropped natural aspect ratio display (zero pixels cropped)
            image_widget = createMosaicImageWidget(local_file, thumb_w, thumb_h)
        end
        if not image_widget then
            local placeholder_txt = TextWidget:new{
                text = "🖼 " .. (img.category or "Image"):upper(),
                face = Font:getFace("cfont", 13),
                fgcolor = theme.color_label_dim,
            }
            image_widget = CenterContainer:new{
                dimen = Geom:new{ w = thumb_w, h = thumb_h },
                placeholder_txt,
            }
        end
    end

    local is_card_focused = is_focused and (self.focus_zone == "cards")
    -- The image_frame always fills the full thumbnail area with no border/padding
    -- so the focus indicator doesn't squeeze or overlap the image content.
    local image_frame = FrameContainer:new{
        padding = 0,
        bordersize = 0,
        radius = sc(4),
        width = thumb_w,
        height = thumb_h,
        image_widget,
    }

    local dot_badge = createDotMenuBadge(sc(32))

    local star_badge = nil
    if img.is_favorite then
        star_badge = FrameContainer:new{
            width = sc(24),
            height = sc(24),
            padding = 0,
            bordersize = sc(1),
            color = Blitbuffer.COLOR_DARK_GRAY,
            background = Blitbuffer.COLOR_WHITE,
            radius = sc(4),
            CenterContainer:new{
                dimen = Geom:new{ w = sc(24), h = sc(24) },
                TextWidget:new{
                    text = "★",
                    face = Font:getFace("cfont", 13),
                    bold = true,
                    fgcolor = Blitbuffer.COLOR_BLACK,
                }
            }
        }
    end

    local overlay_children = { image_frame }

    if star_badge then
        table.insert(overlay_children, LeftContainer:new{
            dimen = Geom:new{ w = thumb_w, h = sc(28) },
            FrameContainer:new{
                padding = sc(4),
                bordersize = 0,
                star_badge,
            }
        })
    end
    table.insert(overlay_children, BottomContainer:new{
        dimen = Geom:new{ w = thumb_w, h = thumb_h },
        RightContainer:new{
            dimen = Geom:new{ w = thumb_w, h = sc(32) },
            FrameContainer:new{
                padding = sc(4),
                bordersize = 0,
                dot_badge,
            }
        }
    })

    local focus_ring = FrameContainer:new{
        padding = 0,
        bordersize = theme.border_focus or sc(3),
        color = theme.color_focus_border or Blitbuffer.COLOR_BLACK,
        background = nil,
        radius = sc(4),
        width = thumb_w,
        height = thumb_h,
        VerticalSpan:new{ width = 0 },
    }

    local focus_badge_widget = LeftContainer:new{
        dimen = Geom:new{ w = thumb_w, h = sc(28) },
        FrameContainer:new{
            padding = sc(4),
            bordersize = 0,
            FrameContainer:new{
                padding = sc(2),
                padding_h = sc(6),
                bordersize = sc(1),
                color = Blitbuffer.COLOR_WHITE,
                background = Blitbuffer.COLOR_BLACK,
                radius = sc(3),
                TextWidget:new{
                    text = "↵ OPEN",
                    face = Font:getFace("cfont", 11),
                    bold = true,
                    fgcolor = Blitbuffer.COLOR_WHITE,
                }
            }
        }
    }

    local focus_overlay = OverlapGroup:new{ focus_ring, focus_badge_widget }

    local card_container = InputContainer:new{
        dimen = Geom:new{ w = thumb_w, h = thumb_h },
        OverlapGroup:new(overlay_children),
    }
    card_container.gallery = self

    function card_container:paintTo(bb, x, y)
        self.dimen = Geom:new{ x = x, y = y, w = thumb_w, h = thumb_h }
        if self[1] then
            self[1]:paintTo(bb, x, y)
        end
        local g = self.gallery
        if g and g.focus_zone == "cards" and g.focused_index == idx then
            focus_overlay:paintTo(bb, x, y)
        end
    end

    card_container.ges_events = {
        Tap = {
            GestureRange:new{
                ges = "tap",
                range = function()
                    local d = card_container.dimen
                    if not d or not d.x or not d.y or not d.w or not d.h then
                        return Geom:new{ x = -1, y = -1, w = 1, h = 1 }
                    end
                    local g = card_container.gallery or self
                    local f_h = (g and g.footer_h) or sc(48)
                    local max_y = (g and g.sh and (g.sh - f_h)) or (d.y + d.h)
                    local safe_h = math.max(0, math.min(d.h, max_y - d.y))
                    return Geom:new{ x = d.x, y = d.y, w = d.w, h = safe_h }
                end
            }
        }
    }

    card_container.onTap = function(this, arg, ges)
        local g = card_container.gallery or self
        local f_h = (g and g.footer_h) or sc(48)
        local footer_top = (g and g.sh and (g.sh - f_h)) or (self.sh - f_h)
        local gesture = (ges and ges.pos and ges) or (arg and arg.pos and arg) or (type(ges) == "table" and ges) or (type(arg) == "table" and arg) or {}
        if gesture.pos and gesture.pos.y and gesture.pos.y >= footer_top then
            return false
        end
        if g and g.is_touch_device and g.focus_zone then
            g.focus_zone = nil
            g.focused_index = nil
            UIManager:setDirty(g, "ui")
        end
        local d = card_container.dimen
        if gesture.pos and d and d.x and d.y and d.w and d.h then
            local right_edge = d.x + d.w
            local bottom_edge = math.min(d.y + d.h, footer_top)
            local btn_hit_w = sc(48)
            local btn_hit_h = sc(48)
            if gesture.pos.x >= (right_edge - btn_hit_w) and gesture.pos.y >= (bottom_edge - btn_hit_h) then
                if p and p.showImageActions then
                    p:showImageActions(img)
                    return true
                end
            end
        end
        if p and p.openImageViewer then
            p:openImageViewer(img)
        elseif p and p._launchImageViewer then
            p:_launchImageViewer(img)
        end
        return true
    end

    return card_container, thumb_h
end

-- ── Storefront Style Grid Card (No Outer Borders, Clean Rounded Thumbnail & Spaced Footer)
function ImageGallery:renderGridCard(img, cell_w, is_focused_or_idx, opt_idx)
    local idx = opt_idx or (type(is_focused_or_idx) == "number" and is_focused_or_idx) or 1
    local p = self.plugin
    local book_path = p.ui and p.ui.document and p.ui.document.file

    local inner_w = cell_w
    local img_h = inner_w
    local card_h = img_h + sc(36)

    local local_file = img.cached_file
    if not local_file and book_path and not img.is_spoiler then
        local_file = p.image_manager:extractImageToFile(book_path, img)
    end

    local img_widget = nil
    if img.is_spoiler and p.ai_helper and p.ai_helper.settings and p.ai_helper.settings.no_spoilers ~= false then
        img_widget = CenterContainer:new{
            dimen = Geom:new{ w = inner_w, h = img_h },
            VerticalGroup:new{
                align = "center",
                ImageWidget:new{
                    file = getAssetPath("lock.svg"),
                    width = sc(24),
                    height = sc(24),
                    scale_factor = 0,
                    is_icon = true,
                    alpha = true,
                },
                VerticalSpan:new{ width = sc(2) },
                TextWidget:new{
                    text = p.loc:t("img_spoiler_locked") or "Locked",
                    face = Font:getFace("cfont", 11),
                    bold = true,
                    fgcolor = Blitbuffer.COLOR_BLACK,
                },
            },
        }
    elseif local_file then
        img_widget = createCoverImageWidget(local_file, inner_w, img_h)
        if not img_widget then
            local ok_fb, fb = pcall(function()
                return ImageWidget:new{
                    file = local_file,
                    width = inner_w,
                    height = img_h,
                    scale_factor = 0,
                    alpha = true,
                    file_do_cache = false,
                }
            end)
            img_widget = ok_fb and fb or nil
        end
    end
    if not img_widget then
        img_widget = CenterContainer:new{
            dimen = Geom:new{ w = inner_w, h = img_h },
            TextWidget:new{ text = "🖼", face = Font:getFace("cfont", 16) },
        }
    end

    local is_card_focused = is_focused and (self.focus_zone == "cards")

    local thumb_frame = FrameContainer:new{
        padding = is_card_focused and sc(2) or 0,
        bordersize = is_card_focused and (theme.border_focus or sc(3)) or sc(1),
        color = is_card_focused and (theme.color_focus_border or Blitbuffer.COLOR_BLACK) or Blitbuffer.COLOR_DARK_GRAY,
        background = is_card_focused and (theme.color_focus_bg or Blitbuffer.Color8(215)) or Blitbuffer.COLOR_WHITE,
        radius = sc(4),
        width = inner_w,
        height = img_h,
        img_widget,
    }

    local display_title = img.title or (p.loc:t("img_untitled") or "Untitled")
    local page_str = img.page and ("Page " .. tostring(img.page)) or ""
    if (not page_str or page_str == "") and img.source_book_title then
        page_str = tostring(img.source_book_title)
    end

    local btn_w = sc(24)
    local label_w = inner_w - btn_w - sc(6)

    local title_w = TextWidget:new{
        text = (img.is_favorite and "★ " or "") .. display_title,
        face = Font:getFace("cfont", 13),
        bold = true,
        fgcolor = Blitbuffer.COLOR_BLACK,
        max_width = label_w,
    }

    local meta_items = { title_w }
    if page_str and page_str ~= "" then
        local meta_w = TextWidget:new{
            text = page_str,
            face = Font:getFace("cfont", 11),
            fgcolor = Blitbuffer.COLOR_BLACK,
            max_width = label_w,
        }
        table.insert(meta_items, VerticalSpan:new{ width = sc(1) })
        table.insert(meta_items, meta_w)
    end

    local meta_vg = VerticalGroup:new(meta_items)
    meta_vg.align = "left"

    local dot_badge = createDotMenuBadge(sc(34), true)

    local footer_row = OverlapGroup:new{
        dimen = Geom:new{ w = inner_w, h = sc(32) },
        LeftContainer:new{
            dimen = Geom:new{ w = label_w, h = sc(32) },
            meta_vg,
        },
        RightContainer:new{
            dimen = Geom:new{ w = inner_w, h = sc(32) },
            dot_badge,
        },
    }

    local focus_badge_widget = LeftContainer:new{
        dimen = Geom:new{ w = inner_w, h = sc(28) },
        FrameContainer:new{
            padding = sc(4),
            bordersize = 0,
            FrameContainer:new{
                padding = sc(2),
                padding_h = sc(6),
                bordersize = sc(1),
                color = Blitbuffer.COLOR_WHITE,
                background = Blitbuffer.COLOR_BLACK,
                radius = sc(3),
                TextWidget:new{
                    text = "↵ OPEN",
                    face = Font:getFace("cfont", 11),
                    bold = true,
                    fgcolor = Blitbuffer.COLOR_WHITE,
                }
            }
        }
    }

    local thumb_overlap_children = { thumb_frame }

    local card_content = VerticalGroup:new{
        align = "left",
        OverlapGroup:new(thumb_overlap_children),
        VerticalSpan:new{ width = sc(4) },
        footer_row,
    }

    local card_frame = FrameContainer:new{
        bordersize = 0,
        color = Blitbuffer.COLOR_WHITE,
        padding = 0,
        background = Blitbuffer.COLOR_WHITE,
        radius = sc(4),
        width = cell_w,
        height = card_h,
        card_content,
    }

    local card_item = InputContainer:new{
        dimen = Geom:new{ w = cell_w, h = card_h },
        card_frame,
    }
    card_item.gallery = self

    function card_item:paintTo(bb, x, y)
        self.dimen = Geom:new{ x = x, y = y, w = cell_w, h = card_h }
        local g = self.gallery
        local is_focused = (g and g.focus_zone == "cards" and g.focused_index == idx)
        card_frame.bordersize = is_focused and (theme.border_focus or sc(3)) or 0
        card_frame.color = is_focused and (theme.color_focus_border or Blitbuffer.COLOR_BLACK) or Blitbuffer.COLOR_WHITE
        card_frame.padding = is_focused and sc(2) or 0
        card_frame.background = is_focused and (theme.color_focus_bg or Blitbuffer.Color8(215)) or Blitbuffer.COLOR_WHITE
        if self[1] then
            self[1]:paintTo(bb, x, y)
        end
        if is_focused then
            focus_badge_widget:paintTo(bb, x, y)
        end
    end

    card_item.ges_events = {
        Tap = {
            GestureRange:new{
                ges = "tap",
                range = function()
                    local d = card_item.dimen
                    if not d or not d.x or not d.y or not d.w or not d.h then
                        return Geom:new{ x = -1, y = -1, w = 1, h = 1 }
                    end
                    local g = card_item.gallery or self
                    local f_h = (g and g.footer_h) or sc(48)
                    local max_y = (g and g.sh and (g.sh - f_h)) or (d.y + d.h)
                    local safe_h = math.max(0, math.min(d.h, max_y - d.y))
                    return Geom:new{ x = d.x, y = d.y, w = d.w, h = safe_h }
                end
            }
        }
    }

    card_item.onTap = function(this, arg, ges)
        local g = card_item.gallery or self
        local f_h = (g and g.footer_h) or sc(48)
        local footer_top = (g and g.sh and (g.sh - f_h)) or (self.sh - f_h)
        local gesture = (ges and ges.pos and ges) or (arg and arg.pos and arg) or (type(ges) == "table" and ges) or (type(arg) == "table" and arg) or {}
        if gesture.pos and gesture.pos.y and gesture.pos.y >= footer_top then
            return false
        end
        if g and g.is_touch_device and g.focus_zone then
            g.focus_zone = nil
            g.focused_index = nil
            UIManager:setDirty(g, "ui")
        end
        local d = card_item.dimen
        if gesture.pos and d and d.x and d.y and d.w and d.h then
            local right_edge = d.x + d.w
            local bottom_edge = math.min(d.y + d.h, footer_top)
            local btn_hit_w = sc(48)
            local btn_hit_h = sc(48)
            if gesture.pos.x >= (right_edge - btn_hit_w) and gesture.pos.y >= (bottom_edge - btn_hit_h) then
                if p and p.showImageActions then
                    p:showImageActions(img)
                    return true
                end
            end
        end
        if p and p.openImageViewer then
            p:openImageViewer(img)
        elseif p and p._launchImageViewer then
            p:_launchImageViewer(img)
        end
        return true
    end

    return card_item
end

-- ── Storefront Style List Row ────────────────────────────────────────────────
function ImageGallery:renderListRow(img, content_w, is_focused_or_idx, opt_idx)
    local idx = opt_idx or (type(is_focused_or_idx) == "number" and is_focused_or_idx) or 1
    local p = self.plugin
    local book_path = p.ui and p.ui.document and p.ui.document.file

    local thumb_w = sc(54)
    local thumb_h = sc(72)
    local row_h = sc(86)
    local pad_h = sc(12)
    local inner_w = content_w - (pad_h * 2)

    local local_file = img.cached_file
    if not local_file and book_path and not img.is_spoiler then
        local_file = p.image_manager:extractImageToFile(book_path, img)
    end

    local thumb_widget = nil
    if img.is_spoiler and p.ai_helper and p.ai_helper.settings and p.ai_helper.settings.no_spoilers ~= false then
        thumb_widget = CenterContainer:new{
            dimen = Geom:new{ w = thumb_w, h = thumb_h },
            ImageWidget:new{
                file = getAssetPath("lock.svg"),
                width = sc(22),
                height = sc(22),
                is_icon = true,
                alpha = true,
            }
        }
    elseif local_file then
        thumb_widget = createCoverImageWidget(local_file, thumb_w, thumb_h)
        if not thumb_widget then
            local ok_fb, fb = pcall(function()
                return ImageWidget:new{
                    file = local_file,
                    width = thumb_w,
                    height = thumb_h,
                    scale_factor = 0,
                    alpha = true,
                    file_do_cache = false,
                }
            end)
            thumb_widget = ok_fb and fb or nil
        end
    end
    if not thumb_widget then
        thumb_widget = CenterContainer:new{
            dimen = Geom:new{ w = thumb_w, h = thumb_h },
            TextWidget:new{ text = "🖼", face = Font:getFace("cfont", 18) }
        }
    end

    local is_card_focused = is_focused and (self.focus_zone == "cards")

    local thumb_frame = FrameContainer:new{
        padding = 0,
        bordersize = sc(1),
        color = Blitbuffer.COLOR_DARK_GRAY,
        background = theme.color_bg_dim or Blitbuffer.COLOR_LIGHT_GRAY,
        radius = sc(3),
        width = thumb_w,
        height = thumb_h,
        thumb_widget,
    }

    local display_title = img.title or (p.loc:t("img_untitled") or "Untitled")
    local prefix = img.is_favorite and "★ " or ""

    local btn_w = sc(32)
    local text_avail_w = inner_w - thumb_w - btn_w - sc(20)

    local title_w = TextWidget:new{
        text = prefix .. display_title,
        face = Font:getFace("cfont", 16),
        bold = true,
        fgcolor = Blitbuffer.COLOR_BLACK,
        max_width = text_avail_w,
    }

    local sub_str = img.page and ("Page " .. tostring(img.page)) or ""
    if img.source_book_title then
        if sub_str ~= "" then
            sub_str = sub_str .. "  ·  " .. tostring(img.source_book_title)
        else
            sub_str = tostring(img.source_book_title)
        end
    end

    local info_items = { title_w }
    if sub_str and sub_str ~= "" then
        local sub_w = TextWidget:new{
            text = sub_str,
            face = Font:getFace("cfont", 12),
            fgcolor = Blitbuffer.Color8(75),
            max_width = text_avail_w,
        }
        table.insert(info_items, VerticalSpan:new{ width = sc(3) })
        table.insert(info_items, sub_w)
    end

    local info_vg = VerticalGroup:new(info_items)
    info_vg.align = "left"

    local left_group = HorizontalGroup:new{
        align = "center",
        thumb_frame,
        HorizontalSpan:new{ width = sc(12) },
        info_vg,
    }

    local dot_badge = createDotMenuBadge(sc(34), true)

    local row_overlap = OverlapGroup:new{
        dimen = Geom:new{ w = inner_w, h = thumb_h },
        LeftContainer:new{
            dimen = Geom:new{ w = inner_w - btn_w - sc(8), h = thumb_h },
            left_group,
        },
        RightContainer:new{
            dimen = Geom:new{ w = inner_w, h = thumb_h },
            dot_badge,
        },
    }

    local row_frame = FrameContainer:new{
        padding = sc(6),
        padding_h = pad_h,
        bordersize = sc(1),
        color = Blitbuffer.Color8(180),
        background = Blitbuffer.COLOR_WHITE,
        radius = sc(6),
        width = content_w,
        row_overlap,
    }

    local row_item = InputContainer:new{
        dimen = Geom:new{ w = content_w, h = row_h },
        row_frame,
    }
    row_item.gallery = self

    function row_item:paintTo(bb, x, y)
        self.dimen = Geom:new{ x = x, y = y, w = content_w, h = row_h }
        local g = self.gallery
        local is_card_focused = (g and g.focus_zone == "cards" and g.focused_index == idx)
        row_frame.bordersize = is_card_focused and (theme.border_focus or sc(3)) or sc(1)
        row_frame.color = is_card_focused and (theme.color_focus_border or Blitbuffer.COLOR_BLACK) or Blitbuffer.Color8(180)
        row_frame.background = is_card_focused and (theme.color_focus_bg or Blitbuffer.Color8(215)) or Blitbuffer.COLOR_WHITE
        if self[1] then
            self[1]:paintTo(bb, x, y)
        end
    end

    row_item.ges_events = {
        Tap = {
            GestureRange:new{
                ges = "tap",
                range = function()
                    local d = row_item.dimen
                    if not d or not d.x or not d.y or not d.w or not d.h then
                        return Geom:new{ x = -1, y = -1, w = 1, h = 1 }
                    end
                    local g = row_item.gallery or self
                    local f_h = (g and g.footer_h) or sc(48)
                    local max_y = (g and g.sh and (g.sh - f_h)) or (d.y + d.h)
                    local safe_h = math.max(0, math.min(d.h, max_y - d.y))
                    return Geom:new{ x = d.x, y = d.y, w = d.w, h = safe_h }
                end
            }
        }
    }

    row_item.onTap = function(this, arg, ges)
        local g = row_item.gallery or self
        local f_h = (g and g.footer_h) or sc(48)
        local footer_top = (g and g.sh and (g.sh - f_h)) or (self.sh - f_h)
        local gesture = (ges and ges.pos and ges) or (arg and arg.pos and arg) or (type(ges) == "table" and ges) or (type(arg) == "table" and arg) or {}
        if gesture.pos and gesture.pos.y and gesture.pos.y >= footer_top then
            return false
        end
        if g and g.is_touch_device and g.focus_zone then
            g.focus_zone = nil
            g.focused_index = nil
            UIManager:setDirty(g, "ui")
        end
        local d = row_item.dimen
        if gesture.pos and d and d.x and d.w then
            local right_edge = d.x + d.w
            local btn_hit_w = sc(54)
            if gesture.pos.x >= (right_edge - btn_hit_w) then
                if p and p.showImageActions then
                    p:showImageActions(img)
                    return true
                end
            end
        end
        if p and p.openImageViewer then
            p:openImageViewer(img)
        elseif p and p._launchImageViewer then
            p:_launchImageViewer(img)
        end
        return true
    end

    return row_item
end

function ImageGallery:close()
    if self.plugin and self.plugin.image_gallery_overlay == self then
        self.plugin.image_gallery_overlay = nil
    end
    UIManager:close(self, "ui")
end

return ImageGallery
