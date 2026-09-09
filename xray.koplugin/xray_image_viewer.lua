-- xray_image_viewer.lua — Custom Fullscreen Interactive Map & Image Viewer for KOReader X-Ray
-- Continuous 360° rotation, smooth pinch/scroll zoom, bounded drag-to-pan via CanvasContainer,
-- right-aligned toolbar, and always-on-top overlay.

local UIManager = require("ui/uimanager")
local Widget = require("ui/widget/widget")
local InputContainer = require("ui/widget/container/inputcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local RightContainer = require("ui/widget/container/rightcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local TextWidget = require("ui/widget/textwidget")
local ImageWidget = require("ui/widget/imagewidget")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Screen = Device.screen
local ok_ds, DataStorage = pcall(require, "datastorage")
local ok_ffiu, ffiutil = pcall(require, "ffi/util")

local plugin_path = ((...) or ""):match("(.-)[^%.]+$") or ""
local theme = require(plugin_path .. "xray_theme")

local function sc(val)
    return (Screen and Screen.scaleBySize and Screen:scaleBySize(val)) or val
end

-- Custom canvas container widget that applies bounded realtime pan offsets during paintTo
local CanvasContainer = Widget:extend{
    pan_x = 0,
    pan_y = 0,
}

function CanvasContainer:getSize()
    return { w = self.width or Screen:getWidth(), h = self.height or Screen:getHeight() }
end

function CanvasContainer:paintTo(bb, x, y)
    self.dimen = Geom:new{ x = x, y = y, w = self.width or Screen:getWidth(), h = self.height or Screen:getHeight() }
    local child = self[1]
    if child then
        local ox = x + math.floor(self.pan_x or 0)
        local oy = y + math.floor(self.pan_y or 0)
        child:paintTo(bb, ox, oy)
    end
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
    function item:getSize()
        return (frame and frame.getSize and frame:getSize()) or { w = frame.width or 0, h = frame.height or 0 }
    end
    function item:paintTo(bb, x, y)
        local fsize = (frame and frame.getSize and frame:getSize()) or { w = frame.width or 0, h = frame.height or 0 }
        self.dimen = Geom:new{ x = x, y = y, w = fsize.w or 0, h = fsize.h or 0 }
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
        if callback then pcall(callback) end
        return true
    end
    return item
end

local function createIconButton(opts)
    opts = opts or {}
    local icon_size = opts.size or sc(30)
    local btn_w = opts.width or (icon_size + sc(18))
    local btn_h = opts.height or btn_w
    local icon_widget
    if opts.text_icon then
        icon_widget = CenterContainer:new{
            dimen = Geom:new{ w = btn_w, h = btn_h },
            TextWidget:new{
                text = opts.text_icon,
                face = Font:getFace("cfont", opts.text_size or 20),
                bold = true,
                fgcolor = Blitbuffer.COLOR_BLACK,
            }
        }
    else
        icon_widget = CenterContainer:new{
            dimen = Geom:new{ w = btn_w, h = btn_h },
            ImageWidget:new{
                file = getAssetPath(opts.icon),
                width = icon_size,
                height = icon_size,
                scale_factor = 0,
                is_icon = true,
                alpha = true,
            }
        }
    end
    local frame = FrameContainer:new{
        padding = 0,
        bordersize = opts.bordersize or 0,
        color = opts.color or Blitbuffer.COLOR_DARK_GRAY,
        background = opts.background,
        radius = opts.radius or 0,
        width = btn_w,
        height = btn_h,
        icon_widget,
    }
    return makeTapItem(frame, opts.callback)
end

local ZOOM_STEPS = { 1.0, 1.25, 1.5, 2.0, 2.5, 3.0, 4.0 }

local ImageViewer = InputContainer:extend{
    covers_fullscreen = true,
    modal = true,
    plugin = nil,
    image_entry = nil,
    file_path = nil,
    rotation_angle = 0, -- 0, 90, 180, 270
    zoom_level = 1.0,   -- 1.0 (fit), 1.25, 1.5, 2.0, 2.5, 3.0, 4.0
    pan_x = 0,
    pan_y = 0,
    show_toolbar = true,
    inverted = false,
}

function ImageViewer:init()
    self.modal = true
    self.covers_fullscreen = true
    self.sw = Screen:getWidth()
    self.sh = Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.sw, h = self.sh }

    -- Use saved rotation angle if explicitly set, otherwise default to 0° (natural orientation)
    if self.image_entry and self.image_entry.rotation ~= nil then
        self.rotation_angle = self.image_entry.rotation
    else
        self.rotation_angle = self.rotation_angle or 0
    end

    local full_range = Geom:new{ x = 0, y = 0, w = self.sw, h = self.sh }

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
        self.focus_zone = self.focus_zone or "toolbar"
        self.focused_btn_idx = self.focused_btn_idx or 2 -- default to Zoom In
    else
        self.focus_zone = nil
        self.focused_btn_idx = nil
    end

    self.ges_events = {
        Tap = { GestureRange:new{ ges = "tap", range = full_range } },
        DoubleTap = { GestureRange:new{ ges = "double_tap", range = full_range } },
        Pinch = { GestureRange:new{ ges = "pinch", range = full_range } },
        Spread = { GestureRange:new{ ges = "spread", range = full_range } },
        Hold = { GestureRange:new{ ges = "hold", range = full_range } },
        HoldRelease = { GestureRange:new{ ges = "hold_release", range = full_range } },
        Pan = { GestureRange:new{ ges = "pan", range = full_range } },
        PanRelease = { GestureRange:new{ ges = "pan_release", range = full_range } },
    }

    self.key_events = {
        ZoomIn = { { "+" }, { "=" }, { "KP_Add" }, { "k" }, { "K" } },
        ZoomOut = { { "-" }, { "_" }, { "KP_Subtract" }, { "j" }, { "J" } },
        -- Arrow keys: navigate toolbar buttons (when focus_zone=="toolbar") or pan/switch images
        FocusLeft = { { "Left" } },
        FocusRight = { { "Right" } },
        FocusUp = { { "Up" } },
        FocusDown = { { "Down" } },
        Rotate = { { "r" }, { "R" } },
        Invert = { { "i" }, { "I" }, { "n" }, { "N" } },
        Minimize = { { "m" }, { "M" } },
        Actions = { { "Menu" }, { "a" }, { "A" }, { "." }, { "3" } },
        -- Enter: context-aware — activates focused toolbar button OR toggles zoom in image zone
        OpenFocused = { { "Return" }, { "KP_Enter" }, { "Enter" }, { "Select" }, { "Space" }, { "Press" } },
        PrevImage = { { "PageUp" }, { "PrevPage" }, { "p" }, { "P" }, { "[" } },
        NextImage = { { "PageDown" }, { "NextPage" }, { "]" } },
        -- Escape: context-aware — resets zoom / returns to toolbar; Back/Q always closes
        EscapeBack = { { "Escape" }, { "Back" }, { "q" }, { "Q" } },
    }

    if Device and Device.input and Device.input.group then
        if Device.input.group.Enter then table.insert(self.key_events.OpenFocused, { Device.input.group.Enter }) end
        if Device.input.group.Select then table.insert(self.key_events.OpenFocused, { Device.input.group.Select }) end
        if Device.input.group.Back then table.insert(self.key_events.EscapeBack, { Device.input.group.Back }) end
    end

    -- Ensure zoom starts at saved zoom or fit-to-viewport for the current rotation
    if self.image_entry and self.image_entry.zoom_level ~= nil then
        self.zoom_level = self.image_entry.zoom_level
        self.pan_x = self.image_entry.pan_x or 0
        self.pan_y = self.image_entry.pan_y or 0
    else
        self.zoom_level = self:getFitZoom()
        self.pan_x = self.pan_x or 0
        self.pan_y = self.pan_y or 0
    end

    self:buildUI()
end

function ImageViewer:saveRotation()
    if self.image_entry then
        self.image_entry.rotation = self.rotation_angle
    end
    local p = self.plugin
    if p and self.image_entry then
        if not p.book_data and p.cache_manager and p.ui and p.ui.document and p.ui.document.file then
            p.book_data = p.cache_manager:loadCache(p.ui.document.file) or {}
        end
        if not p.image_manager then
            local ImageManager = require(plugin_path .. "xray_imagemanager")
            p.image_manager = ImageManager:new(p)
        end
        if p.image_manager and p.book_data then
            local cur_id = self.image_entry.id or self.image_entry.href or self.image_entry.src or self.image_entry.title
            if cur_id then
                p.image_manager:setImageRotation(p.book_data, cur_id, self.rotation_angle)
            end
        end
        if p.cache_manager and p.ui and p.ui.document and p.ui.document.file and p.book_data then
            p.cache_manager:asyncSaveCache(p.ui.document.file, p.book_data)
        end
    end
end

function ImageViewer:saveZoomAndPan()
    if self.image_entry then
        self.image_entry.zoom_level = self.zoom_level
        self.image_entry.pan_x = self.pan_x
        self.image_entry.pan_y = self.pan_y
    end
    local p = self.plugin
    if p and self.image_entry then
        if not p.book_data and p.cache_manager and p.ui and p.ui.document and p.ui.document.file then
            p.book_data = p.cache_manager:loadCache(p.ui.document.file) or {}
        end
        if not p.image_manager then
            local ImageManager = require(plugin_path .. "xray_imagemanager")
            p.image_manager = ImageManager:new(p)
        end
        if p.image_manager and p.book_data then
            local cur_id = self.image_entry.id or self.image_entry.href or self.image_entry.src or self.image_entry.title
            if cur_id then
                p.image_manager:setImageZoom(p.book_data, cur_id, self.zoom_level, self.pan_x, self.pan_y)
            end
        end
        if p.cache_manager and p.ui and p.ui.document and p.ui.document.file and p.book_data then
            p.cache_manager:asyncSaveCache(p.ui.document.file, p.book_data)
        end
    end
end

function ImageViewer:paintTo(bb, x, y)
    self.dimen = Geom:new{ x = x, y = y, w = self.sw, h = self.sh }
    if self[1] then
        self[1]:paintTo(bb, x, y)
    end
end

-- The minimum zoom that fits the whole image in the viewport.
-- zoom_level=1.0 gives a box = viewport (with dim-swap for rotated images), which ImageWidget
-- letterboxes to fill correctly. Sub-1.0 zoom would double-shrink the image unnecessarily.
function ImageViewer:getFitZoom()
    return 1.0
end

-- Clamp panning so the image can never be dragged fully off the screen.
function ImageViewer:clampPan()
    local toolbar_h = sc(48)
    local viewport_h = self.sh - toolbar_h
    local is_sideways = (self.rotation_angle == 90 or self.rotation_angle == 270)

    local vp_w = self.sw
    local vp_h = viewport_h

    local img_w, img_h = getImageDimensions(self.file_path)
    local rot_w, rot_h
    if is_sideways then
        rot_w = img_h
        rot_h = img_w
    else
        rot_w = img_w
        rot_h = img_h
    end

    local rendered_w, rendered_h
    if rot_w and rot_h and rot_w > 0 and rot_h > 0 then
        local box_w = math.floor(vp_w * self.zoom_level)
        local box_h = math.floor(vp_h * self.zoom_level)
        local scale = math.min(box_w / rot_w, box_h / rot_h)
        rendered_w = math.floor(rot_w * scale)
        rendered_h = math.floor(rot_h * scale)
    else
        rendered_w = math.floor(vp_w * self.zoom_level)
        rendered_h = math.floor(vp_h * self.zoom_level)
    end

    local max_pan_x = math.max(0, math.floor((rendered_w - vp_w) / 2))
    local max_pan_y = math.max(0, math.floor((rendered_h - vp_h) / 2))

    self.pan_x = math.max(-max_pan_x, math.min(max_pan_x, self.pan_x or 0))
    self.pan_y = math.max(-max_pan_y, math.min(max_pan_y, self.pan_y or 0))
end

function ImageViewer:onTap(arg, ges)
    self._last_pan_pos = nil
    if self.is_touch_device and self.focus_zone then
        self.focus_zone = nil
        self.focused_btn_idx = nil
        self:buildUI()
        UIManager:setDirty(self, "ui")
    end
    return true
end

function ImageViewer:onDoubleTap(arg, ges)
    self._last_pan_pos = nil
    local fit_zoom = self:getFitZoom()
    if self.zoom_level > fit_zoom + 0.05 then
        self.zoom_level = fit_zoom
        self.pan_x = 0
        self.pan_y = 0
    else
        self.zoom_level = 2.0
    end
    self:clampPan()
    self:saveZoomAndPan()
    self:buildUI()
    UIManager:setDirty(self, "ui")
    return true
end

function ImageViewer:onPinch(arg, ges)
    self._last_pan_pos = nil
    self:onZoomOut()
    return true
end

function ImageViewer:onSpread(arg, ges)
    self._last_pan_pos = nil
    self:onZoomIn()
    return true
end

function ImageViewer:onZoomIn()
    self._last_pan_pos = nil
    local fit_zoom = self:getFitZoom()
    -- Build effective zoom steps: fit_zoom (if sub-1) + all standard steps >= fit_zoom
    local steps = {}
    if fit_zoom < 0.99 then
        table.insert(steps, fit_zoom)
    end
    for _, z in ipairs(ZOOM_STEPS) do
        if z >= fit_zoom - 0.01 then  -- include fit_zoom-level entries too
            table.insert(steps, z)
        end
    end
    if #steps == 0 then steps = ZOOM_STEPS end

    local current_idx = 1
    for i, z in ipairs(steps) do
        if math.abs(self.zoom_level - z) < 0.05 then
            current_idx = i
            break
        end
    end
    if current_idx < #steps then
        self.zoom_level = steps[current_idx + 1]
        self:clampPan()
        self:saveZoomAndPan()
        self:buildUI()
        UIManager:setDirty(self, "ui")
    end
end

function ImageViewer:onZoomOut()
    self._last_pan_pos = nil
    local fit_zoom = self:getFitZoom()
    -- Build effective zoom steps: fit_zoom (if sub-1) + all standard steps >= fit_zoom
    local steps = {}
    if fit_zoom < 0.99 then
        table.insert(steps, fit_zoom)
    end
    for _, z in ipairs(ZOOM_STEPS) do
        if z >= fit_zoom - 0.01 then  -- include fit_zoom-level entries too
            table.insert(steps, z)
        end
    end
    if #steps == 0 then steps = ZOOM_STEPS end

    local current_idx = 1
    for i, z in ipairs(steps) do
        if math.abs(self.zoom_level - z) < 0.05 then
            current_idx = i
            break
        end
    end
    if current_idx > 1 then
        self.zoom_level = steps[current_idx - 1]
        self:clampPan()
        self:saveZoomAndPan()
        self:buildUI()
        UIManager:setDirty(self, "ui")
    end
end

function ImageViewer:onPanLeft()
    self.pan_x = self.pan_x + sc(50)
    self:clampPan()
    if self.canvas_container then self.canvas_container.pan_x = (self._base_x or 0) + self.pan_x end
    self:saveZoomAndPan()
    UIManager:setDirty(self, "ui")
    return true
end

function ImageViewer:onPanRight()
    self.pan_x = self.pan_x - sc(50)
    self:clampPan()
    if self.canvas_container then self.canvas_container.pan_x = (self._base_x or 0) + self.pan_x end
    self:saveZoomAndPan()
    UIManager:setDirty(self, "ui")
    return true
end

function ImageViewer:onPanUp()
    self.pan_y = self.pan_y + sc(50)
    self:clampPan()
    if self.canvas_container then self.canvas_container.pan_y = (self._base_y or 0) + self.pan_y end
    self:saveZoomAndPan()
    UIManager:setDirty(self, "ui")
    return true
end

function ImageViewer:onPanDown()
    self.pan_y = self.pan_y - sc(50)
    self:clampPan()
    if self.canvas_container then self.canvas_container.pan_y = (self._base_y or 0) + self.pan_y end
    self:saveZoomAndPan()
    UIManager:setDirty(self, "ui")
    return true
end

function ImageViewer:onRotate()
    self._last_pan_pos = nil
    -- Clockwise 90° rotation (matches rotate-cw.svg icon direction)
    self.rotation_angle = ((self.rotation_angle or 0) + 270) % 360
    self:saveRotation()
    -- Reset zoom to fit the image in the new orientation
    self.zoom_level = self:getFitZoom()
    self.pan_x = 0
    self.pan_y = 0
    self:clampPan()
    self:saveZoomAndPan()
    self:buildUI()
    UIManager:setDirty(self, "ui")
    return true
end

function ImageViewer:onInvert()
    self.inverted = not self.inverted
    self:buildUI()
    UIManager:setDirty(self, "ui")
    return true
end

function ImageViewer:onMinimize()
    self:minimize()
    return true
end

function ImageViewer:onActions()
    local p = self.plugin
    if p and p.showImageActions and self.image_entry then
        p:showImageActions(self.image_entry)
    end
    return true
end

function ImageViewer:onToggleZoom()
    return self:onDoubleTap()
end

function ImageViewer:onPrevImage()
    local p = self.plugin
    if not p or not p.images or #p.images <= 1 then return true end
    local cur_idx = 1
    local cur_id = self.image_entry and (self.image_entry.id or self.image_entry.src or self.image_entry.href or self.image_entry.title)
    for i, img in ipairs(p.images) do
        local id = img.id or img.src or img.href or img.title
        if id == cur_id then cur_idx = i; break end
    end
    local prev_idx = (cur_idx > 1) and (cur_idx - 1) or #p.images
    local next_img = p.images[prev_idx]
    if next_img then
        self:close()
        if p.openImageViewer then
            p:openImageViewer(next_img)
        elseif p._launchImageViewer then
            p:_launchImageViewer(next_img)
        end
    end
    return true
end

function ImageViewer:onNextImage()
    local p = self.plugin
    if not p or not p.images or #p.images <= 1 then return true end
    local cur_idx = 1
    local cur_id = self.image_entry and (self.image_entry.id or self.image_entry.src or self.image_entry.href or self.image_entry.title)
    for i, img in ipairs(p.images) do
        local id = img.id or img.src or img.href or img.title
        if id == cur_id then cur_idx = i; break end
    end
    local next_idx = (cur_idx < #p.images) and (cur_idx + 1) or 1
    local next_img = p.images[next_idx]
    if next_img then
        self:close()
        if p.openImageViewer then
            p:openImageViewer(next_img)
        elseif p._launchImageViewer then
            p:_launchImageViewer(next_img)
        end
    end
    return true
end

function ImageViewer:onFocusUp()
    if not self.focus_zone or self.focus_zone == "image" then
        local fit_zoom = self:getFitZoom()
        if self.focus_zone == "image" and self.zoom_level > (fit_zoom + 0.05) then
            return self:onPanUp()
        else
            self.focus_zone = "toolbar"
            self.focused_btn_idx = self.focused_btn_idx or 2
            self:buildUI()
            UIManager:setDirty(self, "ui")
        end
    end
    return true
end

function ImageViewer:onFocusDown()
    if not self.focus_zone or self.focus_zone == "toolbar" then
        self.focus_zone = "image"
        self:buildUI()
        UIManager:setDirty(self, "ui")
    elseif self.focus_zone == "image" then
        local fit_zoom = self:getFitZoom()
        if self.zoom_level > (fit_zoom + 0.05) then
            return self:onPanDown()
        else
            return self:onToggleZoom()
        end
    end
    return true
end

function ImageViewer:onFocusLeft()
    if not self.focus_zone or self.focus_zone == "toolbar" then
        self.focus_zone = "toolbar"
        if not self.focused_btn_idx then
            self.focused_btn_idx = 7
        else
            self.focused_btn_idx = (self.focused_btn_idx > 1) and (self.focused_btn_idx - 1) or 7
        end
        self:buildUI()
        UIManager:setDirty(self, "ui")
    elseif self.focus_zone == "image" then
        local fit_zoom = self:getFitZoom()
        if self.zoom_level > (fit_zoom + 0.05) then
            return self:onPanLeft()
        else
            return self:onPrevImage()
        end
    end
    return true
end

function ImageViewer:onFocusRight()
    if not self.focus_zone or self.focus_zone == "toolbar" then
        self.focus_zone = "toolbar"
        if not self.focused_btn_idx then
            self.focused_btn_idx = 1
        else
            self.focused_btn_idx = (self.focused_btn_idx < 7) and (self.focused_btn_idx + 1) or 1
        end
        self:buildUI()
        UIManager:setDirty(self, "ui")
    elseif self.focus_zone == "image" then
        local fit_zoom = self:getFitZoom()
        if self.zoom_level > (fit_zoom + 0.05) then
            return self:onPanRight()
        else
            return self:onNextImage()
        end
    end
    return true
end

function ImageViewer:onOpenFocused()
    if self.focus_zone == "toolbar" then
        if self.focused_btn_idx == 1 then
            return self:onRotate()
        elseif self.focused_btn_idx == 2 then
            return self:onZoomIn()
        elseif self.focused_btn_idx == 3 then
            return self:onZoomOut()
        elseif self.focused_btn_idx == 4 then
            return self:onInvert()
        elseif self.focused_btn_idx == 5 then
            return self:onActions()
        elseif self.focused_btn_idx == 6 then
            return self:onMinimize()
        elseif self.focused_btn_idx == 7 then
            return self:onEscapeBack()
        end
    else
        return self:onToggleZoom()
    end
    return true
end

function ImageViewer:onEscapeBack()
    -- If we are zoomed in (pan mode), first reset zoom and return focus to toolbar
    if self.focus_zone == "image" then
        local fit_zoom = self:getFitZoom()
        if self.zoom_level > (fit_zoom + 0.05) then
            -- Reset zoom to fit view and move focus to toolbar
            self.zoom_level = fit_zoom
            self.pan_x = 0
            self.pan_y = 0
            self.focus_zone = "toolbar"
            self:buildUI()
            UIManager:setDirty(self, "ui")
            return true
        end
    end
    -- Not zoomed or already in toolbar: close the viewer
    self:close()
    return true
end

function ImageViewer:onClose()
    self:close()
    return true
end

function ImageViewer:handleEvent(ev)
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
        elseif key == "+" or key == "=" or key == "KP_Add" or key == "k" or key == "K" then
            return self:onZoomIn()
        elseif key == "-" or key == "_" or key == "KP_Subtract" or key == "j" or key == "J" then
            return self:onZoomOut()
        elseif key == "r" or key == "R" then
            return self:onRotate()
        elseif key == "i" or key == "I" or key == "n" or key == "N" then
            return self:onInvert()
        elseif key == "m" or key == "M" then
            return self:onMinimize()
        elseif key == "a" or key == "A" or key == "Menu" or key == "." or key == "3" then
            return self:onActions()
        elseif key == "p" or key == "P" or key == "PageUp" or key == "PrevPage" or key == "[" then
            return self:onPrevImage()
        elseif key == "PageDown" or key == "NextPage" or key == "]" then
            return self:onNextImage()
        elseif key == "Escape" or key == "Back" or key == "q" or key == "Q" then
            return self:onClose()
        end
    end
    return InputContainer.handleEvent(self, ev)
end

function ImageViewer:onHold(arg, ges)
    if ges and ges.pos then
        self._last_pan_pos = { x = ges.pos.x, y = ges.pos.y }
    end
    return true
end

function ImageViewer:onPan(arg, ges)
    if not ges then return end

    -- 1. Mouse wheel zoom handling
    if ges.from_mousewheel or ges.mousewheel_direction then
        local delta = 0
        if ges.mousewheel_direction then
            delta = ges.mousewheel_direction
        elseif ges.relative and ges.relative.y then
            delta = (ges.relative.y > 0 and 1 or -1)
        end
        if delta > 0 then
            self:onZoomIn()
        elseif delta < 0 then
            self:onZoomOut()
        end
        return true
    end

    -- 2. Smooth 1:1 Touch Drag Panning (Wander-free, Glitch-free)
    local dx = 0
    local dy = 0
    if ges.pos then
        if self._last_pan_pos then
            dx = ges.pos.x - self._last_pan_pos.x
            dy = ges.pos.y - self._last_pan_pos.y
        end
        self._last_pan_pos = { x = ges.pos.x, y = ges.pos.y }
    end

    -- Filter out anomalous large single-frame jump spikes
    local max_single_step = sc(80)
    if math.abs(dx) > max_single_step or math.abs(dy) > max_single_step then
        return true
    end

    if dx ~= 0 or dy ~= 0 then
        self.pan_x = (self.pan_x or 0) + dx
        self.pan_y = (self.pan_y or 0) + dy
        self:clampPan()
        if self.canvas_container then
            -- Add stored centering offset so the live-pan matches buildUI's layout
            local bx = self._base_x or 0
            local by = self._base_y or 0
            self.canvas_container.pan_x = bx + self.pan_x
            self.canvas_container.pan_y = by + self.pan_y
        end
        UIManager:setDirty(self, "ui")
        return true
    end
end

function ImageViewer:onHoldRelease(arg, ges)
    self._last_pan_pos = nil
    self:saveZoomAndPan()
    return true
end

function ImageViewer:onPanRelease(arg, ges)
    self._last_pan_pos = nil
    self:saveZoomAndPan()
    return true
end

function ImageViewer:buildUI()
    local sw = self.sw
    local sh = self.sh
    local p = self.plugin
    local img = self.image_entry or {}

    -- ── 1. Top Controls Toolbar (Right-Aligned, Fixed Height) ─────────────────
    local toolbar_h = sc(64)
    local bar_content_h = sc(48)
    local btn_size = sc(30)
    local btn_frame_w = sc(48)
    local btn_gap = sc(6)
    local num_btns = 7
    local actions_total_w = (btn_frame_w * num_btns) + (btn_gap * (num_btns - 1))

    local is_rotate_focused = (self.focus_zone == "toolbar" and self.focused_btn_idx == 1)
    local is_zoomin_focused = (self.focus_zone == "toolbar" and self.focused_btn_idx == 2)
    local is_zoomout_focused = (self.focus_zone == "toolbar" and self.focused_btn_idx == 3)
    local is_night_focused = (self.focus_zone == "toolbar" and self.focused_btn_idx == 4)
    local is_menu_focused = (self.focus_zone == "toolbar" and self.focused_btn_idx == 5)
    local is_min_focused = (self.focus_zone == "toolbar" and self.focused_btn_idx == 6)
    local is_close_focused = (self.focus_zone == "toolbar" and self.focused_btn_idx == 7)

    local rotate_btn = createIconButton{
        icon = "rotate-cw.svg",
        size = btn_size,
        width = btn_frame_w,
        height = bar_content_h,
        bordersize = is_rotate_focused and sc(2) or 0,
        color = is_rotate_focused and (theme.color_focus_border or Blitbuffer.COLOR_BLACK) or nil,
        background = is_rotate_focused and (theme.color_focus_bg or Blitbuffer.Color8(215)) or nil,
        radius = sc(4),
        callback = function()
            self:onRotate()
        end,
    }

    local zoom_in_btn = createIconButton{
        icon = "zoom-in.svg",
        size = btn_size,
        width = btn_frame_w,
        height = bar_content_h,
        bordersize = is_zoomin_focused and sc(2) or 0,
        color = is_zoomin_focused and (theme.color_focus_border or Blitbuffer.COLOR_BLACK) or nil,
        background = is_zoomin_focused and (theme.color_focus_bg or Blitbuffer.Color8(215)) or nil,
        radius = sc(4),
        callback = function()
            self:onZoomIn()
        end,
    }

    local zoom_out_btn = createIconButton{
        icon = "zoom-out.svg",
        size = btn_size,
        width = btn_frame_w,
        height = bar_content_h,
        bordersize = is_zoomout_focused and sc(2) or 0,
        color = is_zoomout_focused and (theme.color_focus_border or Blitbuffer.COLOR_BLACK) or nil,
        background = is_zoomout_focused and (theme.color_focus_bg or Blitbuffer.Color8(215)) or nil,
        radius = sc(4),
        callback = function()
            self:onZoomOut()
        end,
    }

    local night_btn = createIconButton{
        icon = "moon.svg",
        size = btn_size,
        width = btn_frame_w,
        height = bar_content_h,
        bordersize = is_night_focused and sc(2) or 0,
        color = is_night_focused and (theme.color_focus_border or Blitbuffer.COLOR_BLACK) or nil,
        background = is_night_focused and (theme.color_focus_bg or Blitbuffer.Color8(215)) or nil,
        radius = sc(4),
        callback = function()
            self.inverted = not self.inverted
            self:buildUI()
            UIManager:setDirty(self, "ui")
        end,
    }

    local menu_btn = createIconButton{
        icon = "more-vertical.svg",
        size = btn_size,
        width = btn_frame_w,
        height = bar_content_h,
        bordersize = is_menu_focused and sc(2) or 0,
        color = is_menu_focused and (theme.color_focus_border or Blitbuffer.COLOR_BLACK) or nil,
        background = is_menu_focused and (theme.color_focus_bg or Blitbuffer.Color8(215)) or nil,
        radius = sc(4),
        callback = function()
            if p and p.showImageActions then
                p:showImageActions(img)
            end
        end,
    }

    local minimize_btn = createIconButton{
        icon = "minus.svg",
        size = btn_size,
        width = btn_frame_w,
        height = bar_content_h,
        bordersize = is_min_focused and sc(2) or 0,
        color = is_min_focused and (theme.color_focus_border or Blitbuffer.COLOR_BLACK) or nil,
        background = is_min_focused and (theme.color_focus_bg or Blitbuffer.Color8(215)) or nil,
        radius = sc(4),
        callback = function()
            self:minimize()
        end,
    }

    local close_btn = createIconButton{
        icon = "x.svg",
        size = btn_size,
        width = btn_frame_w,
        height = bar_content_h,
        bordersize = is_close_focused and sc(2) or 0,
        color = is_close_focused and (theme.color_focus_border or Blitbuffer.COLOR_BLACK) or nil,
        background = is_close_focused and (theme.color_focus_bg or Blitbuffer.Color8(215)) or nil,
        radius = sc(4),
        callback = function()
            self:close()
        end,
    }

    local header_actions = HorizontalGroup:new{
        align = "center",
        rotate_btn,
        HorizontalSpan:new{ width = btn_gap },
        zoom_in_btn,
        HorizontalSpan:new{ width = btn_gap },
        zoom_out_btn,
        HorizontalSpan:new{ width = btn_gap },
        night_btn,
        HorizontalSpan:new{ width = btn_gap },
        menu_btn,
        HorizontalSpan:new{ width = btn_gap },
        minimize_btn,
        HorizontalSpan:new{ width = btn_gap },
        close_btn,
    }

    local title_max_w = sw - sc(28) - actions_total_w - sc(16)

    local display_title = (img.title or "Image")

    local title_label = TextWidget:new{
        text = (img.is_favorite and "★ " or "") .. display_title,
        face = Font:getFace("cfont", 18),
        bold = true,
        fgcolor = Blitbuffer.COLOR_BLACK,
        max_width = title_max_w,
    }

    local viewport_h = sh - toolbar_h
    self.viewport_h = viewport_h

    local row_w = sw - sc(24)
    local top_bar_row = OverlapGroup:new{
        dimen = Geom:new{ w = row_w, h = bar_content_h },
        LeftContainer:new{
            dimen = Geom:new{ w = title_max_w, h = bar_content_h },
            title_label,
        },
        RightContainer:new{
            dimen = Geom:new{ w = row_w, h = bar_content_h },
            header_actions,
        },
    }

    local toolbar_widget = FrameContainer:new{
        padding = sc(8),
        padding_h = sc(12),
        bordersize = sc(1),
        color = Blitbuffer.COLOR_BLACK,
        background = Blitbuffer.COLOR_WHITE,
        radius = sc(4),
        width = sw,
        height = toolbar_h,
        top_bar_row,
    }

    -- ── 2. Full-Screen Image Viewport with Custom CanvasContainer ─────────────
    -- Viewport size
    local vp_w = sw
    local vp_h = viewport_h

    -- Box given to ImageWidget (always matches viewport scaled by zoom_level).
    -- KOReader rotates the bitmap and scales it to fit within width/height, centering it.
    local img_box_w = math.floor(vp_w * self.zoom_level)
    local img_box_h = math.floor(vp_h * self.zoom_level)

    -- Centering offset for zoom > 1.0 (at zoom 1.0, base_x = 0, base_y = 0)
    local base_x = math.floor((vp_w - img_box_w) / 2)
    local base_y = math.floor((vp_h - img_box_h) / 2)
    self._base_x = base_x
    self._base_y = base_y

    local ok_img, image_widget = pcall(function()
        return ImageWidget:new{
            file = self.file_path,
            width = img_box_w,
            height = img_box_h,
            rotation_angle = self.rotation_angle,
            scale_factor = 0,
            invert = self.inverted,
            alpha = true,
            file_do_cache = false,
        }
    end)
    if not ok_img or not image_widget then
        image_widget = TextWidget:new{
            text = "Failed to load image",
            face = Font:getFace("cfont", 16),
            bold = true,
        }
    end

    self.canvas_container = CanvasContainer:new{
        width = vp_w,
        height = vp_h,
        rotation_angle = self.rotation_angle,
        pan_x = base_x + (self.pan_x or 0),
        pan_y = base_y + (self.pan_y or 0),
        image_widget,
    }

    local image_surface = FrameContainer:new{
        padding = 0,
        bordersize = 0,
        background = self.inverted and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE,
        width = vp_w,
        height = vp_h,
        self.canvas_container,
    }

    -- ── 3. Assemble Non-Overlapping Structured Layout (Toolbar ALWAYS on Top) ─
    local image_layer = FrameContainer:new{
        padding = 0,
        bordersize = 0,
        background = self.inverted and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE,
        width = sw,
        height = sh,
        VerticalGroup:new{
            align = "left",
            VerticalSpan:new{ width = toolbar_h },
            image_surface,
        }
    }

    self[1] = FrameContainer:new{
        padding = 0,
        bordersize = 0,
        background = self.inverted and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE,
        width = sw,
        height = sh,
        OverlapGroup:new{
            image_layer,
            toolbar_widget,
        }
    }
end

function ImageViewer:minimize()
    self:saveRotation()
    self:saveZoomAndPan()
    local p = self.plugin
    local state = {
        image_entry = self.image_entry,
        file_path = self.file_path,
        rotation_angle = self.rotation_angle,
        zoom_level = self.zoom_level,
        pan_x = self.pan_x,
        pan_y = self.pan_y,
        inverted = self.inverted,
    }
    if p then
        p.last_minimized_state = state
        if p.book_data then
            p.book_data.last_minimized_state = state
            if p.cache_manager and p.ui and p.ui.document and p.ui.document.file then
                p.cache_manager:asyncSaveCache(p.ui.document.file, p.book_data)
            end
        end
        if p.closeAllMenus then
            p:closeAllMenus()
        end
    end
    self:close(true)
    if p and p.image_gallery_overlay then
        local ov = p.image_gallery_overlay
        p.image_gallery_overlay = nil
        UIManager:close(ov, "ui")
    end
    if p and p.closeAllMenus then
        p:closeAllMenus()
    end
end

function ImageViewer:close(is_minimizing)
    self:saveRotation()
    self:saveZoomAndPan()
    local was_resumed = self.is_resumed or (self.plugin and self.plugin.last_minimized_state ~= nil)
    if not is_minimizing and self.plugin then
        self.plugin.last_minimized_state = nil
        if self.plugin.book_data then
            self.plugin.book_data.last_minimized_state = nil
            if self.plugin.cache_manager and self.plugin.ui and self.plugin.ui.document and self.plugin.ui.document.file then
                self.plugin.cache_manager:asyncSaveCache(self.plugin.ui.document.file, self.plugin.book_data)
            end
        end
    end
    if self.plugin and self.plugin.active_image_viewer == self then
        self.plugin.active_image_viewer = nil
    end
    UIManager:close(self, "ui")

    if not is_minimizing and was_resumed and self.plugin and self.plugin.showImages then
        self.plugin:showImages{ force_gallery = true }
    end
end

return ImageViewer

