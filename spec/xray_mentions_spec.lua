-- xray_mentions_spec.lua
require("spec/spec_helper")
local xray_mentions = require("xray_mentions")
local xray_ui = require("xray_ui")

describe("xray_mentions", function()
    local plugin

    before_each(function()
        plugin = createMockPlugin()
        for k, v in pairs(xray_mentions) do plugin[k] = v end
        plugin.closeAllMenus = xray_ui.closeAllMenus
        _G.ui_tracker.shown = {}; _G.ui_tracker.last_shown = nil; _G.ui_tracker.closed = {}
    end)

    describe("showReturnBanner", function()
        local test_mentions = { {page = 10}, {page = 20}, {page = 30} }

        it("should show a ButtonDialog for return navigation", function()
            plugin:showReturnBanner(5, "Frodo", test_mentions, 20)
            local last = _G.ui_tracker.last_shown
            assert.is_not_nil(last)
            assert.are.equal("ButtonDialog", last.type)
        end)

        it("should register xray_highlights view module when showHighlightOverlay is called", function()
            local registered_modules = {}
            plugin.ui.view = {
                dialog = {},
                view_modules = registered_modules,
                registerViewModule = function(self, name, module)
                    registered_modules[name] = module
                end
            }

            local mock_boxes = {
                { x = 10, y = 20, w = 100, h = 15 }
            }
            plugin._banner_natural_h = 100

            plugin:showHighlightOverlay(mock_boxes)

            assert.is_not_nil(registered_modules["xray_highlights"])
            assert.is_not_nil(registered_modules["xray_highlights"].paintTo)

            local inverted_rects = {}
            local mock_bb = {
                invertRect = function(self, x, y, w, h)
                    table.insert(inverted_rects, {x = x, y = y, w = w, h = h})
                end
            }

            registered_modules["xray_highlights"]:paintTo(mock_bb, 0, 0)

            assert.are.equal(1, #inverted_rects)
            assert.are.equal(10, inverted_rects[1].x)
            assert.are.equal(20, inverted_rects[1].y)
            assert.are.equal(100, inverted_rects[1].w)
            assert.are.equal(15, inverted_rects[1].h)
        end)

        it("should unregister xray_highlights view module when clearHighlightOverlay is called", function()
            local registered_modules = {
                xray_highlights = { paintTo = function() end }
            }
            plugin.ui.view = {
                dialog = {},
                view_modules = registered_modules
            }

            plugin:clearHighlightOverlay()

            assert.is_nil(registered_modules["xray_highlights"])
        end)

        it("should only paint child content and not highlights in banner's wrapper paintTo", function()
            local mock_child = {
                getSize = function() return { w = 100, h = 50 } end,
                paintTo = function() end
            }
            local button_dialog_new = package.loaded["ui/widget/buttondialog"].new
            package.loaded["ui/widget/buttondialog"].new = function(a, b)
                local dialog = button_dialog_new(a, b)
                dialog[1] = { mock_child, dimen = { x = 0, y = 0, w = 600, h = 100 } }
                dialog.movable = { dimen = { x = 0, y = 0, w = 600, h = 100 } }
                dialog.dimen = dialog.movable.dimen
                return dialog
            end

            local inverted_rects = {}
            local mock_bb = {
                invertRect = function(self, x, y, w, h)
                    table.insert(inverted_rects, {x = x, y = y, w = w, h = h})
                end
            }

            local child_painted = false
            mock_child.paintTo = function(this, bb, x, y)
                child_painted = true
            end

            plugin:showReturnBanner(5, "Frodo", test_mentions, 20)

            local last = _G.ui_tracker.last_shown
            assert.is_not_nil(last)
            assert.is_not_nil(last[1])
            assert.is_not_nil(last[1].paintTo)

            last[1].paintTo(last[1], mock_bb, 0, 700)

            assert.is_true(child_painted)
            assert.are.equal(0, #inverted_rects)

            package.loaded["ui/widget/buttondialog"].new = button_dialog_new
        end)
    end)

    describe("Jump Logic with Flag", function()
        it("should set the pending_return_banner flag instead of showing immediately", function()
            plugin.last_pageno = 100
            local entity = { name = "Frodo", mentions = { {page = 10} } }
            local items = plugin:buildMentionsMenuItems(entity)
            local mention_item = nil
            for _, itm in ipairs(items) do
                if itm.text:find("p.10") then mention_item = itm; break end
            end
            
            mention_item.callback()
            assert.is_not_nil(plugin.pending_return_banner)
            assert.are.equal(100, plugin.pending_return_banner.return_page)
            assert.is_nil(_G.ui_tracker.last_shown)
        end)
    end)

    describe("showImageReturnBanner", function()
        it("should show a ButtonDialog with Back to Reading, Images & Maps, and Close", function()
            local img_entry = { title = "Shire Map", href = "shire_map.jpg", page = 488 }
            plugin:showImageReturnBanner(2, img_entry, 488)
            local last = _G.ui_tracker.last_shown
            assert.is_not_nil(last)
            assert.are.equal("ButtonDialog", last.type)
            local args = last.args or last
            assert.is_true(args.title:find("Shire Map") ~= nil)
            assert.is_true(args.title:find("488") ~= nil)
            -- 3 buttons: Back, Images & Maps, and Close (no arrow buttons)
            assert.is_not_nil(args.buttons)
            assert.are.equal(1, #args.buttons)
            assert.are.equal(3, #args.buttons[1])
            assert.is_not_nil(args.buttons[1][1].text)
            assert.is_true(args.buttons[1][2].text:lower():find("image") ~= nil)
            assert.are.equal("\xE2\x9C\x95", args.buttons[1][3].text)
        end)
    end)

    describe("showMentionsMenu", function()
        it("should show an EntityListOverlay with mode mentions, modal true, and 'ui' refreshtype", function()
            local entity = { name = "Eric Wardle", mentions = { { page = 9, chapter = "Prologue", snippet = "Ambulance is two minutes away" } } }
            plugin:showMentionsMenu(entity)
            local last = _G.ui_tracker.last_shown
            assert.is_not_nil(last)
            assert.is_true(last.modal == true)
            assert.are.equal("mentions", last.mode)
            assert.are.equal("Eric Wardle", last.entity.name)
            assert.are.equal(1, #last.raw_items)
            assert.are.equal("ui", _G.ui_tracker.last_refreshtype)
            assert.is_not_nil(plugin.mentions_menu)

            -- Close should nil mentions_menu
            last:close()
            assert.is_nil(plugin.mentions_menu)
        end)

        it("should show mentions over characters menu and dismiss details dialog cleanly", function()
            for k, v in pairs(xray_ui) do plugin[k] = v end
            plugin.ui.document.getPageCount = function() return 100 end
            local ChapterAnalyzer = require("xray_chapteranalyzer")
            plugin.chapter_analyzer = ChapterAnalyzer:new{ plugin = plugin }
            plugin.characters = { { name = "Alice", mentions = { { page = 5, chapter = "Ch1" } } } }

            -- 1. Open characters menu
            plugin:showCharacters()
            assert.is_not_nil(plugin.char_menu)
            assert.are.equal("characters", plugin.char_menu.mode)

            -- 2. Open character details
            plugin.char_menu:onItemSelect(plugin.characters[1])
            assert.is_not_nil(plugin.active_details_dialog)

            -- 3. Click Find Mentions
            local find_mentions_btn = plugin.active_details_dialog.buttons[1][1]
            assert.are.equal("find_mentions", find_mentions_btn.text)
            find_mentions_btn.callback()

            -- Details dialog closed, mentions menu shown with 'ui' refreshtype
            assert.is_nil(plugin.active_details_dialog)
            assert.is_not_nil(plugin.mentions_menu)
            assert.are.equal("mentions", plugin.mentions_menu.mode)
            assert.are.equal("ui", _G.ui_tracker.last_refreshtype)
            assert.is_not_nil(plugin.char_menu) -- Char menu remains underneath

            -- Closing mentions menu keeps char_menu underneath
            plugin.mentions_menu:close()
            assert.is_nil(plugin.mentions_menu)
            assert.is_not_nil(plugin.char_menu)
        end)
    end)

    describe("Back to reading button and _doReturnJump", function()
        it("should navigate back to return_page when Back button is tapped in showReturnBanner", function()
            local handled_events = {}
            plugin.ui.handleEvent = function(self_arg, event)
                table.insert(handled_events, event)
            end
            local test_mentions = { {page = 10}, {page = 20} }
            plugin:showReturnBanner(42, "Frodo", test_mentions, 10)

            local last = _G.ui_tracker.last_shown
            assert.is_not_nil(last)
            local back_btn = last.buttons[1][2]
            assert.is_not_nil(back_btn)
            assert.is_not_nil(back_btn.callback)

            back_btn.callback()
            assert.are.equal(1, #handled_events)
            assert.are.equal("GotoPage", handled_events[1].name)
            assert.are.equal(42, handled_events[1].args)
            assert.is_nil(plugin.return_banner)
        end)

        it("should fall back to return_page_origin if return_page argument is nil", function()
            local handled_events = {}
            plugin.ui.handleEvent = function(self_arg, event)
                table.insert(handled_events, event)
            end
            plugin.return_page_origin = 77
            plugin:_doReturnJump(nil)

            assert.are.equal(1, #handled_events)
            assert.are.equal("GotoPage", handled_events[1].name)
            assert.are.equal(77, handled_events[1].args)
        end)

        it("should correctly resolve return_pg in EntityListOverlay mentions tap", function()
            local EntityListOverlay = require("xray_entity_list")
            plugin.ui.getCurrentPage = function() return 65 end
            plugin.last_pageno = 65
            local handled_events = {}
            plugin.ui.handleEvent = function(self_arg, event)
                table.insert(handled_events, event)
            end

            local overlay = EntityListOverlay:new{
                mode = "mentions",
                entity = { name = "Frodo" },
                raw_items = { { page = 12 } },
                plugin = plugin,
            }
            overlay:onItemSelect({ page = 12 })

            assert.is_not_nil(plugin.pending_return_banner)
            assert.are.equal(65, plugin.pending_return_banner.return_page)
        end)
    end)
end)
