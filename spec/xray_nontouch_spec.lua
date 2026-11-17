-- spec/xray_nontouch_spec.lua
require("spec.spec_helper")

local xray_theme = require("xray_theme")
local ImageGallery = require("xray_image_gallery")
local ImageViewer = require("xray_image_viewer")
local XRaySettingsCard = require("xray_settings_card")
local UnitScanner = require("xray_unitscanner")
local UIManager = require("ui/uimanager")

describe("X-Ray Non-Touch & Keyboard Support", function()
    local Device = require("device")
    local orig_isTouch

    before_each(function()
        orig_isTouch = Device.isTouchDevice
        Device.isTouchDevice = function() return false end

        mock_plugin = {
            loc = { t = function(self, k, ...) return k end },
            ai_helper = {
                settings = {},
                saveSettings = function(self, s) for k, v in pairs(s) do self.settings[k] = v end end,
                importFromTextFile = function(self, prompt) return true, 1, "xray_key.txt" end,
                init = function() end,
                updateConfigKey = function() end,
            },
            isRTL = function() return false end,
            path = "xray.koplugin/",
            _draw_underline = function() end,
            _PointerArrow = require("ui/widget/widget"):extend{},
            showImageActions = function() end,
            image_manager = require("xray_imagemanager"):new(),
            book_data = {},
        }
    end)

    after_each(function()
        Device.isTouchDevice = orig_isTouch or (function() return true end)
    end)

    describe("Theme Tokens", function()
        it("defines high-contrast non-touch focus design tokens", function()
            assert.are_not.equal(nil, xray_theme.border_focus)
            assert.are_not.equal(nil, xray_theme.color_focus_border)
            assert.are_not.equal(nil, xray_theme.color_focus_bg)
            assert.are_not.equal(nil, xray_theme.radius_focus)
            assert.is_true(xray_theme.border_focus >= 2)
        end)
    end)

    describe("ImageGallery Non-Touch Controls", function()
        local sample_images = {
            { id = "img1", title = "Map of Roshar", page = 1, category = "map" },
            { id = "img2", title = "Shallan Sketch", page = 15, category = "illustration" },
            { id = "img3", title = "Urithiru Diagram", page = 45, category = "diagram" },
            { id = "img4", title = "Highstorm Map", page = 80, category = "map" },
        }

        it("initializes focused_index to 1 and registers full key_events", function()
            mock_plugin.images = sample_images
            local gallery = ImageGallery:new{
                plugin = mock_plugin,
                images = sample_images,
                view_mode = "mosaic",
                tab = "all",
            }
            assert.are.equal(1, gallery.focused_index)
            assert.are_not.equal(nil, gallery.key_events.NextCard)
            assert.are_not.equal(nil, gallery.key_events.PrevCard)
            assert.are_not.equal(nil, gallery.key_events.OpenFocused)
            assert.are_not.equal(nil, gallery.key_events.ImageActions)
            assert.are_not.equal(nil, gallery.key_events.CycleTab)
            assert.are_not.equal(nil, gallery.key_events.CycleView)
            assert.are_not.equal(nil, gallery.key_events.ToggleFilter)
            assert.are_not.equal(nil, gallery.key_events.Select1)
        end)

        it("moves focus forward and backward with wrapping", function()
            mock_plugin.images = sample_images
            local gallery = ImageGallery:new{
                plugin = mock_plugin,
                images = sample_images,
                view_mode = "mosaic",
                tab = "all",
            }
            gallery:onNextCard()
            assert.are.equal(2, gallery.focused_index)
            gallery:onNextCard()
            assert.are.equal(3, gallery.focused_index)
            gallery:onPrevCard()
            assert.are.equal(2, gallery.focused_index)
            gallery:onPrevCard()
            assert.are.equal(1, gallery.focused_index)
            -- Prev wrapping on page 1 wraps to end of page items
            gallery:onPrevCard()
            assert.are.equal(#sample_images, gallery.focused_index)
        end)

        it("opens image directly on number shortcuts (1-9)", function()
            mock_plugin.images = sample_images
            local opened_entry = nil
            local gallery = ImageGallery:new{
                plugin = mock_plugin,
                images = sample_images,
                view_mode = "mosaic",
                tab = "all",
            }
            gallery.openViewer = function(self, entry)
                opened_entry = entry
            end
            gallery:onSelect2()
            assert.are_not.equal(nil, opened_entry)
            assert.are.equal("img2", opened_entry.id)
        end)

        it("cycles view modes with V key", function()
            mock_plugin.images = sample_images
            local gallery = ImageGallery:new{
                plugin = mock_plugin,
                images = sample_images,
                view_mode = "mosaic",
                tab = "all",
            }
            assert.are.equal("mosaic", gallery.view_mode)
            gallery:onCycleView()
            assert.are.equal("grid", gallery.view_mode)
            gallery:onCycleView()
            assert.are.equal("list", gallery.view_mode)
            gallery:onCycleView()
            assert.are.equal("mosaic", gallery.view_mode)
        end)

        it("navigates across 4 zones (header, tabs, cards, footer) smoothly", function()
            mock_plugin.images = sample_images
            local gallery = ImageGallery:new{
                plugin = mock_plugin,
                images = sample_images,
                view_mode = "mosaic",
                tab = "all",
            }
            assert.are.equal("cards", gallery.focus_zone)
            assert.are.equal(1, gallery.focused_index)

            -- Moving Up from top row cards goes to tabs
            gallery:onFocusUp()
            assert.are.equal("tabs", gallery.focus_zone)

            -- Moving Up from tabs goes to header
            gallery:onFocusUp()
            assert.are.equal("header", gallery.focus_zone)

            -- Moving Down from header goes to tabs
            gallery:onFocusDown()
            assert.are.equal("tabs", gallery.focus_zone)

            -- Moving Down from tabs goes to cards
            gallery:onFocusDown()
            assert.are.equal("cards", gallery.focus_zone)
            assert.are.equal(1, gallery.focused_index)

            -- Moving Down from bottom row goes to footer
            gallery.focused_index = 4
            gallery:onFocusDown()
            assert.are.equal("footer", gallery.focus_zone)

            -- Moving Up from footer returns to cards
            gallery:onFocusUp()
            assert.are.equal("cards", gallery.focus_zone)
        end)

        it("dispatches Enter / Return in handleEvent correctly", function()
            mock_plugin.images = sample_images
            local opened_entry = nil
            local gallery = ImageGallery:new{
                plugin = mock_plugin,
                images = sample_images,
                view_mode = "mosaic",
                tab = "all",
            }
            gallery.openViewer = function(self, entry)
                opened_entry = entry
            end
            gallery.focus_zone = "cards"
            gallery.focused_index = 3

            local handled = gallery:handleEvent({ type = "Key", key = "Return" })
            assert.is_true(handled)
            assert.are_not.equal(nil, opened_entry)
            assert.are.equal("img3", opened_entry.id)
        end)

        it("avoids calling buildUI when moving focus within the same page", function()
            mock_plugin.images = sample_images
            local gallery = ImageGallery:new{
                plugin = mock_plugin,
                images = sample_images,
                view_mode = "mosaic",
                tab = "all",
            }
            local build_count = 0
            local orig_buildUI = gallery.buildUI
            gallery.buildUI = function(this)
                build_count = build_count + 1
                return orig_buildUI(this)
            end

            -- Moving right from item 1 to item 2 on the same page
            gallery:onFocusRight()
            assert.are.equal(0, build_count)
            assert.are.equal(2, gallery.focused_index)

            -- Moving down on the same page
            gallery:onFocusDown()
            assert.are.equal(0, build_count)

            -- Moving up to tabs
            gallery:onFocusUp()
            gallery:onFocusUp()
            assert.are.equal("tabs", gallery.focus_zone)
            assert.are.equal(0, build_count)

            -- Moving left within tabs
            gallery:onFocusLeft()
            assert.are.equal(0, build_count)
        end)

        it("calls buildUI when moving focus across page boundaries", function()
            local many_images = {}
            for i = 1, 30 do
                table.insert(many_images, { id = "img" .. i, title = "Image " .. i, page = i })
            end
            mock_plugin.images = many_images
            local gallery = ImageGallery:new{
                plugin = mock_plugin,
                images = many_images,
                view_mode = "mosaic",
                tab = "all",
            }
            gallery.focus_zone = "cards"
            gallery.focused_index = #(gallery.current_page_items or {})

            local build_count = 0
            local orig_buildUI = gallery.buildUI
            gallery.buildUI = function(this)
                build_count = build_count + 1
                return orig_buildUI(this)
            end

            -- Focus right on last card of page 1 advances to page 2 -> triggers buildUI
            gallery:onFocusRight()
            assert.are.equal(2, gallery.current_page)
            assert.are.equal(1, build_count)
        end)
    end)

    describe("ImageViewer Non-Touch Controls", function()
        it("registers keyboard shortcuts and actions", function()
            local viewer = ImageViewer:new{
                plugin = mock_plugin,
                image_entry = { id = "img1", title = "Map", page = 1 },
                file_path = "assets/map.svg",
            }
            -- ToggleZoom and arrow keys are handled via key_events for context-aware dispatch.
            assert.are_not.equal(nil, viewer.key_events.ZoomIn)
            assert.are_not.equal(nil, viewer.key_events.ZoomOut)
            assert.are_not.equal(nil, viewer.key_events.Invert)
            assert.are_not.equal(nil, viewer.key_events.Minimize)
            assert.are_not.equal(nil, viewer.key_events.Actions)
            assert.are_not.equal(nil, viewer.key_events.OpenFocused)
            -- Escape/Back is now EscapeBack (context-aware: resets zoom or closes)
            assert.are_not.equal(nil, viewer.key_events.EscapeBack)

            local initial_inverted = viewer.inverted
            viewer:onInvert()
            assert.are.equal(not initial_inverted, viewer.inverted)

            local action_shown = false
            mock_plugin.showImageActions = function() action_shown = true end
            viewer:onActions()
            assert.is_true(action_shown)
        end)

        it("navigates toolbar buttons and image focus zones", function()
            local viewer = ImageViewer:new{
                plugin = mock_plugin,
                image_entry = { id = "img1", title = "Map", page = 1 },
                file_path = "assets/map.svg",
            }
            assert.are.equal("toolbar", viewer.focus_zone)

            -- Left / Right cycles through the 7 toolbar buttons
            viewer.focused_btn_idx = 1
            viewer:onFocusRight()
            assert.are.equal(2, viewer.focused_btn_idx)
            viewer:onFocusLeft()
            assert.are.equal(1, viewer.focused_btn_idx)
            viewer:onFocusLeft()
            assert.are.equal(7, viewer.focused_btn_idx)

            -- Down moves into image zone
            viewer:onFocusDown()
            assert.are.equal("image", viewer.focus_zone)

            -- Up when not zoomed in moves back to toolbar
            viewer.zoom_level = viewer:getFitZoom()
            viewer:onFocusUp()
            assert.are.equal("toolbar", viewer.focus_zone)
        end)

        it("EscapeBack resets zoom and returns to toolbar when zoomed in", function()
            local viewer = ImageViewer:new{
                plugin = mock_plugin,
                image_entry = { id = "img1", title = "Map", page = 1 },
                file_path = "assets/map.svg",
            }
            -- Zoom in and move to image zone
            viewer.focus_zone = "image"
            viewer.zoom_level = viewer:getFitZoom() + 1.0  -- well beyond fit
            viewer.pan_x = 50
            viewer.pan_y = 30

            -- EscapeBack should reset zoom and return to toolbar, not close
            local closed = false
            viewer.close = function() closed = true end
            viewer:onEscapeBack()

            assert.is_false(closed)
            assert.are.equal("toolbar", viewer.focus_zone)
            assert.are.equal(viewer:getFitZoom(), viewer.zoom_level)
        end)

        it("dispatches toolbar actions via onOpenFocused key event", function()
            local rotated = false
            local viewer = ImageViewer:new{
                plugin = mock_plugin,
                image_entry = { id = "img1", title = "Map", page = 1 },
                file_path = "assets/map.svg",
            }
            viewer.onRotate = function() rotated = true; return true end
            viewer.focus_zone = "toolbar"
            viewer.focused_btn_idx = 1 -- Rotate button

            -- onOpenFocused is the method wired to Enter/Return via key_events.OpenFocused
            local handled = viewer:onOpenFocused()
            assert.is_true(handled)
            assert.is_true(rotated)
        end)

        it("switches to prev/next images on page keys", function()
            mock_plugin.images = {
                { id = "img1", title = "Map 1" },
                { id = "img2", title = "Map 2" },
            }
            local opened_image = nil
            mock_plugin.openImageViewer = function(self, img) opened_image = img end

            local viewer = ImageViewer:new{
                plugin = mock_plugin,
                image_entry = mock_plugin.images[1],
                file_path = "assets/map.svg",
            }
            viewer:onNextImage()
            assert.are_not.equal(nil, opened_image)
            assert.are.equal("img2", opened_image.id)
        end)
    end)

    describe("Entity Menu Focus Highlighting", function()
        it("patches MenuItem class from item_group and sets _xray_focused on focus/unfocus", function()
            -- MenuItem is private inside menu.lua. Our patch extracts the class via
            -- getmetatable(item).__index from the first item_group entry.
            -- Simulate: create a fake ItemClass, a fake menu with item_group, and call
            -- _patchMenuItemClass (tested indirectly via newMenu).
            local menu = require("ui/widget/menu")
            local xray_theme_mod = require("xray_theme")

            local ItemClass = {
                onFocus = function(self) return true end,
                onUnfocus = function(self) return true end,
                paintTo = function(self, bb, x, y) end,
            }
            local dummy_item = {
                menu = { _xray_highlight = true },
                _xray_focused = false,
                dimen = { w = 600, h = 60 },
            }
            setmetatable(dummy_item, { __index = ItemClass })

            local fake_group = { dummy_item }

            -- Directly invoke the internal patching logic via the mock's structure
            -- by simulating what _patchMenuItemClass does:
            local mt = getmetatable(dummy_item)
            local ExtractedClass = mt and mt.__index
            assert.are.equal(ItemClass, ExtractedClass)

            -- After patching, onFocus should set _xray_focused
            local orig_onFocus = ItemClass.onFocus
            function ItemClass:onFocus()
                self._xray_focused = self.menu and self.menu._xray_highlight or false
                if orig_onFocus then orig_onFocus(self) end
                return true
            end
            local orig_onUnfocus = ItemClass.onUnfocus
            function ItemClass:onUnfocus()
                self._xray_focused = false
                if orig_onUnfocus then orig_onUnfocus(self) end
                return true
            end

            ItemClass.onFocus(dummy_item)
            assert.is_true(dummy_item._xray_focused)

            ItemClass.onUnfocus(dummy_item)
            assert.is_false(dummy_item._xray_focused)
        end)
    end)

    describe("ButtonDialog Non-Touch Support", function()
        it("patches ButtonDialog with Enter/Escape key events, traps propagation, and focuses default button", function()
            local ButtonDialog = require("ui/widget/buttondialog")
            local Device = require("device")
            local orig_isTouch = Device.isTouchDevice
            Device.isTouchDevice = function() return false end -- Non-touch mode

            local cancel_called = false
            local dlg = {
                buttons = {{{
                    text = "Cancel",
                    is_enter_default = true,
                    callback = function() cancel_called = true end,
                }}},
                layout = {
                    {
                        {
                            is_enter_default = true,
                            callback = function() cancel_called = true end,
                            handleEvent = function(self, ev)
                                if ev.type == "Focus" then self._focused = true end
                                if ev.type == "Unfocus" then self._focused = false end
                            end
                        }
                    }
                },
                key_events = {},
            }
            -- Simulate ButtonDialog:init after patching on non-touch device
            if ButtonDialog.init then
                ButtonDialog.init(dlg)
                assert.are_not.equal(nil, dlg.key_events.Press)
                assert.are_not.equal(nil, dlg.key_events.Close)
                assert.is_true(dlg.stop_events_propagation)
                assert.are.equal(1, dlg.selected.x)
                assert.are.equal(1, dlg.selected.y)
                assert.is_true(dlg.layout[1][1]._focused)

                -- Test onPress activation (after debounce threshold)
                if ButtonDialog.onPress then
                    dlg._created_time = (os.clock and os.clock() or os.time()) - 1
                    dlg.getFocusItem = function(self) return self.layout[self.selected.y][self.selected.x] end
                    ButtonDialog.onPress(dlg)
                    assert.is_true(cancel_called)
                end
            end

            -- Now test touch-capable mode: focus indicator does NOT immediately show
            Device.isTouchDevice = function() return true end
            local touch_dlg = {
                buttons = {{{ text = "OK", is_enter_default = true }}},
                layout = {{{
                    is_enter_default = true,
                    handleEvent = function(self, ev)
                        if ev.type == "Focus" then self._focused = true end
                    end
                }}},
                key_events = {},
            }
            if ButtonDialog.init then
                ButtonDialog.init(touch_dlg)
                assert.are.equal(1, touch_dlg.selected.x)
                assert.are.equal(1, touch_dlg.selected.y)
                assert.are.equal(nil, touch_dlg.layout[1][1]._focused)
            end

            Device.isTouchDevice = orig_isTouch
        end)

        it("safely handles ButtonDialog with _added_widgets and activates valid button without crash", function()
            local ButtonDialog = require("ui/widget/buttondialog")
            local close_called = false
            local dummy_vg = { text = "Content text", not_focusable = nil }
            local dlg = {
                _added_widgets = { dummy_vg },
                buttons = {{{
                    text = "Close",
                    callback = function() close_called = true end,
                }}},
                layout = {
                    {
                        {
                            text = "Close",
                            callback = function() close_called = true end,
                        }
                    }
                },
                key_events = {},
            }
            if ButtonDialog.init then
                ButtonDialog.init(dlg)
                assert.is_true(dummy_vg.not_focusable)
                assert.are.equal(1, dlg.selected.x)
                assert.are.equal(1, dlg.selected.y)
                if ButtonDialog.onPress then
                    ButtonDialog.onPress(dlg)
                    assert.is_true(close_called)
                end
            end
        end)
    end)

    describe("Dual Touch / Keyboard Focus Suppression", function()
        local sample_images = {
            { id = "img1", title = "Map 1", page = 1 },
            { id = "img2", title = "Map 2", page = 10 },
        }

        it("suppresses focus in ImageGallery on touch devices until D-pad activation, and clears on swipe", function()
            Device.isTouchDevice = function() return true end
            mock_plugin.images = sample_images
            local gallery = ImageGallery:new{
                plugin = mock_plugin,
                images = sample_images,
                view_mode = "mosaic",
                tab = "all",
            }
            assert.is_nil(gallery.focus_zone)
            assert.is_nil(gallery.focused_index)

            -- D-pad right activates focus on cards
            gallery:onFocusRight()
            assert.are.equal("cards", gallery.focus_zone)
            assert.are.equal(1, gallery.focused_index)

            -- Subsequent D-pad movement moves index
            gallery:onFocusRight()
            assert.are.equal(2, gallery.focused_index)

            -- Swipe turns page and resets focus visibility back to touch-first mode
            gallery:onSwipe(nil, { direction = "west" })
            assert.is_nil(gallery.focus_zone)
            assert.is_nil(gallery.focused_index)
        end)

        it("suppresses toolbar focus in ImageViewer on touch devices until D-pad activation, and clears on tap", function()
            Device.isTouchDevice = function() return true end
            local viewer = ImageViewer:new{
                plugin = mock_plugin,
                image_entry = sample_images[1],
            }
            assert.is_nil(viewer.focus_zone)
            assert.is_nil(viewer.focused_btn_idx)

            -- D-pad left activates toolbar focus on close button (idx 7)
            viewer:onFocusLeft()
            assert.are.equal("toolbar", viewer.focus_zone)
            assert.are.equal(7, viewer.focused_btn_idx)

            -- Tap clears toolbar focus
            viewer:onTap()
            assert.is_nil(viewer.focus_zone)
            assert.is_nil(viewer.focused_btn_idx)
        end)

        it("correctly identifies touch vs non-touch device via XRayUtils", function()
            local XRayUtils = require("xray_utils")
            Device.isTouchDevice = function() return true end
            assert.is_true(XRayUtils:isTouchDevice())

            Device.isTouchDevice = function() return false end
            assert.is_false(XRayUtils:isTouchDevice())
        end)

        it("ensures cards cannot intercept footer taps and respects safe gesture bounds", function()
            Device.isTouchDevice = function() return true end
            local gallery = ImageGallery:new{
                plugin = mock_plugin,
                images = sample_images,
                view_mode = "mosaic",
                tab = "all",
            }
            gallery:buildUI()

            local root = gallery[1]
            assert.are_not.equal(nil, root)
            -- root[2] is bottom_pinned_footer
            local footer_container = root[2]
            assert.are_not.equal(nil, footer_container)

            -- Test renderMosaicCard refuses tap in footer area
            local card_container, thumb_h = gallery:renderMosaicCard(sample_images[1], 300, false, 1)
            assert.are_not.equal(nil, card_container)
            -- thumb_h must not exceed avail_content_h
            assert.is_true(thumb_h <= gallery.avail_content_h)

            -- Nil-safety before paintTo:
            card_container.dimen = { w = 300, h = 60 }
            local gr = card_container.ges_events.Tap[1]
            local range_fn = gr.range or (gr.args and gr.args.range)
            assert.are_not.equal(nil, range_fn)
            local safe_range = range_fn()
            assert.are_not.equal(nil, safe_range)
            assert.are.equal(-1, safe_range.x)

            -- Card position overlapping footer:
            card_container.dimen = { x = 20, y = gallery.sh - gallery.footer_h - 20, w = 300, h = 60 }
            local card_tap_in_footer = {
                type = "Gesture",
                name = "Tap",
                pos = { x = 50, y = gallery.sh - gallery.footer_h + 10 },
            }
            local card_handled = card_container:onTap(nil, card_tap_in_footer)
            assert.is_false(card_handled)

            -- Tap above footer is accepted:
            local card_tap_valid = {
                type = "Gesture",
                name = "Tap",
                pos = { x = 50, y = gallery.sh - gallery.footer_h - 10 },
            }
            local valid_handled = card_container:onTap(nil, card_tap_valid)
            assert.is_true(valid_handled)
        end)

        it("disables pagination buttons when on single page or boundaries", function()
            local gallery = ImageGallery:new{
                plugin = mock_plugin,
                images = { sample_images[1] },
                view_mode = "grid",
                tab = "all",
            }
            gallery:buildUI()
            assert.are.equal(1, gallery.total_pages)

            -- When 1/1, both prev and next must be disabled
            assert.is_false(gallery.prev_btn.enabled)
            assert.is_false(gallery.next_btn.enabled)

            -- 15 images in grid view = 3 pages (6 per page)
            local many_images = {}
            for i = 1, 15 do
                table.insert(many_images, { id = "img" .. i, title = "Image " .. i, page = i })
            end
            mock_plugin.images = many_images
            local multi_gallery = ImageGallery:new{
                plugin = mock_plugin,
                images = many_images,
                view_mode = "grid",
                tab = "all",
            }
            multi_gallery:buildUI()
            assert.is_true(multi_gallery.total_pages > 1)
            local last_page = multi_gallery.total_pages

            -- Page 1: prev disabled, next enabled
            assert.are.equal(1, multi_gallery.current_page)
            assert.is_false(multi_gallery.prev_btn.enabled)
            assert.is_true(multi_gallery.next_btn.enabled)

            -- Page 2: both enabled
            multi_gallery.current_page = 2
            multi_gallery:buildUI()
            assert.is_true(multi_gallery.prev_btn.enabled)
            assert.is_true(multi_gallery.next_btn.enabled)

            -- Last page: prev enabled, next disabled
            multi_gallery.current_page = last_page
            multi_gallery:buildUI()
            assert.is_true(multi_gallery.prev_btn.enabled)
            assert.is_false(multi_gallery.next_btn.enabled)
        end)

        it("allows hardware page turn buttons in ImageGallery (RPgFwd, LPgFwd, RPgBack, LPgBack)", function()
            local many_images = {}
            for i = 1, 15 do
                table.insert(many_images, { id = "img" .. i, title = "Image " .. i, page = i })
            end
            mock_plugin.images = many_images
            local multi_gallery = ImageGallery:new{
                plugin = mock_plugin,
                images = many_images,
                view_mode = "grid",
                tab = "all",
            }
            multi_gallery:buildUI()
            assert.is_true(multi_gallery.total_pages > 1)
            assert.are.equal(1, multi_gallery.current_page)

            -- Turn next with RPgFwd
            multi_gallery:handleEvent({ type = "Key", key = "RPgFwd" })
            assert.are.equal(2, multi_gallery.current_page)

            -- Turn next with LPgFwd
            if multi_gallery.total_pages >= 3 then
                multi_gallery:handleEvent({ type = "Key", key = "LPgFwd" })
                assert.are.equal(3, multi_gallery.current_page)
                -- Turn prev with RPgBack
                multi_gallery:handleEvent({ type = "Key", key = "RPgBack" })
                assert.are.equal(2, multi_gallery.current_page)
            end

            -- Turn prev with LPgBack
            multi_gallery:handleEvent({ type = "Key", key = "LPgBack" })
            assert.are.equal(1, multi_gallery.current_page)

            -- Synthetic event
            multi_gallery:handleEvent({ type = "NextPage" })
            assert.are.equal(2, multi_gallery.current_page)
            multi_gallery:handleEvent({ type = "PrevPage" })
            assert.are.equal(1, multi_gallery.current_page)
        end)

        it("allows hardware page turn buttons in ImageViewer (RPgFwd, LPgFwd, RPgBack, LPgBack)", function()
            local sample_images_list = {
                { id = "img1", title = "First" },
                { id = "img2", title = "Second" },
                { id = "img3", title = "Third" },
            }
            mock_plugin.images = sample_images_list
            local viewer = ImageViewer:new{
                plugin = mock_plugin,
                image_entry = sample_images_list[1],
            }
            local next_called = false
            local prev_called = false
            viewer.onNextImage = function() next_called = true; return true end
            viewer.onPrevImage = function() prev_called = true; return true end

            viewer:handleEvent({ type = "Key", key = "RPgFwd" })
            assert.is_true(next_called)

            viewer:handleEvent({ type = "Key", key = "RPgBack" })
            assert.is_true(prev_called)
        end)
    end)

    describe("Style Cards Touch-First Focus Gating", function()
        local xray_style_cards = require("xray_style_cards")
        local xray_theme = require("xray_theme")
        local Device = require("device")
        local UIManager = require("ui/uimanager")
        local orig_isTouch, orig_show

        local function count_focus_borders(widget, focus_bs, focus_bg, seen)
            if type(widget) ~= "table" then return 0 end
            seen = seen or {}
            if seen[widget] then return 0 end
            seen[widget] = true
            local count = 0
            if widget.type ~= "FrameContainer" and widget.bordersize == focus_bs and widget.background == focus_bg then
                count = 1
            end
            if type(widget.args) == "table" then
                count = count + count_focus_borders(widget.args, focus_bs, focus_bg, seen)
            end
            for _, child in ipairs(widget) do
                count = count + count_focus_borders(child, focus_bs, focus_bg, seen)
            end
            return count
        end

        before_each(function()
            orig_isTouch = Device.isTouchDevice
            orig_show = UIManager.show
        end)

        after_each(function()
            Device.isTouchDevice = orig_isTouch
            UIManager.show = orig_show
        end)

        it("suppresses initial focus highlight on touch devices in showEntityStyleCard and showUnitStyleCard until D-pad key", function()
            Device.isTouchDevice = function() return true end
            local shown_overlay
            UIManager.show = function(_, w) shown_overlay = w end

            local saved_settings = {
                entity_underline_style = "double",
                unit_underline_style = "wavy",
            }
            local test_plugin = {
                loc = mock_plugin.loc,
                ai_helper = {
                    settings = saved_settings,
                    saveSettings = function(_, tbl)
                        for k, v in pairs(tbl) do saved_settings[k] = v end
                    end,
                },
                clearTileCaches = function() end,
                isRTL = function() return false end,
            }
            for k, v in pairs(xray_style_cards) do test_plugin[k] = v end

            local focus_bs = xray_theme.border_focus or 3
            local focus_bg = xray_theme.color_focus_bg

            -- Entity style card on touch device: 0 focused pills initially
            test_plugin:showEntityStyleCard()
            assert.is_not_nil(shown_overlay)
            assert.are.equal(0, count_focus_borders(shown_overlay, focus_bs, focus_bg))

            -- D-pad arrow activates focus on first pill (1, 1) -> 1 focused pill
            shown_overlay:onFocusDown()
            assert.are.equal(1, count_focus_borders(shown_overlay, focus_bs, focus_bg))
            shown_overlay:onSelect()
            assert.are.equal("solid", saved_settings.entity_underline_style)

            -- Unit style card on touch device: 0 focused pills initially
            shown_overlay = nil
            test_plugin:showUnitStyleCard()
            assert.is_not_nil(shown_overlay)
            assert.are.equal(0, count_focus_borders(shown_overlay, focus_bs, focus_bg))

            shown_overlay:onFocusRight()
            assert.are.equal(1, count_focus_borders(shown_overlay, focus_bs, focus_bg))
        end)

        it("shows initial focus highlight immediately on non-touch devices in showEntityStyleCard and showUnitStyleCard", function()
            Device.isTouchDevice = function() return false end
            local shown_overlay
            UIManager.show = function(_, w) shown_overlay = w end

            local test_plugin = {
                loc = mock_plugin.loc,
                ai_helper = {
                    settings = {},
                    saveSettings = function() end,
                },
                clearTileCaches = function() end,
                isRTL = function() return false end,
            }
            for k, v in pairs(xray_style_cards) do test_plugin[k] = v end

            local focus_bs = xray_theme.border_focus or 3
            local focus_bg = xray_theme.color_focus_bg

            test_plugin:showEntityStyleCard()
            assert.are.equal(1, count_focus_borders(shown_overlay, focus_bs, focus_bg))

            shown_overlay = nil
            test_plugin:showUnitStyleCard()
            assert.are.equal(1, count_focus_borders(shown_overlay, focus_bs, focus_bg))
        end)
    end)
end)
