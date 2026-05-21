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
end)
