--[[
    xray_images_ui.lua
    Image viewer, image gallery presentation, image actions, renaming, and page jumping for KOReader X-Ray Plugin.
--]]

local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local ButtonDialog = require("ui/widget/buttondialog")

local plugin_path = ((...) or ""):match("(.-)[^%.]+$") or ""
local utils = require(plugin_path .. "xray_utils")
local xray_theme = require(plugin_path .. "xray_theme")

local _asset_path_cache = {}
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

local M = {}

function M:showImages(opts)
    opts = opts or {}
    self.image_tab = opts.tab or self.image_tab or "all"
    self.image_view_mode = opts.view_mode or self.image_view_mode or "mosaic"
    self.image_filter_mode = opts.filter_mode or self.image_filter_mode or "standard"

    -- Load images: prefer book_data.images from cache (preserves user customizations & rotations),
    -- fall back to scan only if no cached images exist.
    if (not self.book_data or not self.book_data.images or #self.book_data.images == 0) and self.cache_manager and self.ui and self.ui.document and self.ui.document.file then
        local loaded = self.cache_manager:loadCache(self.ui.document.file)
        if loaded and type(loaded) == "table" then
            if not self.book_data or type(self.book_data) ~= "table" then
                self.book_data = loaded
            elseif loaded.images and #loaded.images > 0 then
                self.book_data.images = loaded.images
            end
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
            if #scanned > 0 then
                self.book_data.images = self.images
                if self.cache_manager and self.ui.document.file then
                    self.cache_manager:asyncSaveCache(self.ui.document.file, self.book_data)
                end
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
    local is_spoiler = image_entry.is_spoiler and not image_entry.spoiler_revealed
    if is_spoiler and self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.spoiler_setting ~= "full_book" and self.ai_helper.settings.no_spoilers ~= false then
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
                image_entry.spoiler_revealed = true
                if self.images then
                    for _, img in ipairs(self.images) do
                        if img.id == image_entry.id or img.href == image_entry.href then
                            img.is_spoiler = false
                            img.spoiler_revealed = true
                        end
                    end
                end
                if self.book_data and self.book_data.images then
                    for _, img in ipairs(self.book_data.images) do
                        if img.id == image_entry.id or img.href == image_entry.href then
                            img.is_spoiler = false
                            img.spoiler_revealed = true
                        end
                    end
                end
                if self.image_gallery_overlay then
                    self.image_gallery_overlay.cached_pages = nil
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
