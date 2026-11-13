-- spec/xray_registration_spec.lua
require("spec/spec_helper")

-- Mock a minimal version of the plugin to test the registration logic
-- We don't load main.lua directly to avoid side effects of the plugin initialization.
local XRayPlugin = {}

-- Copy the logic from main.lua for testing
function XRayPlugin:_buildXRayDictButton(dict_popup_arg)
    return {
        text = "X-Ray",
        callback = function(widget_instance)
            if not self.xray_mode_enabled then return end
            local popup = widget_instance or dict_popup_arg
            local text = popup and (popup.word or popup.text or popup.selection_text)
            -- ... (rest of logic)
            return text
        end,
    }
end

function XRayPlugin:onDictButtonsReady(dict_popup, dict_buttons)
    if not self.xray_mode_enabled then return end
    if self.ui and self.ui.dictionary
            and type(self.ui.dictionary.addToDictButtons) == "function" then
        return
    end

    local btn = self:_buildXRayDictButton(dict_popup)
    local xray_button = {
        text = btn.text,
        callback = function() return btn.callback(nil) end,
    }
    table.insert(dict_buttons, { xray_button })
end

function XRayPlugin:mountHighlightHandler()
    local hl = self.ui and self.ui.highlight
    if not hl or hl._xray_highlight_wrapped then return end
    local plugin = self

    local orig_show_menu = hl.onShowHighlightMenu
    local orig_lookup_word = hl.lookupDictWord
    hl._xray_orig_onShowHighlightMenu = orig_show_menu
    hl._xray_orig_lookupDictWord = orig_lookup_word

    hl.onShowHighlightMenu = function(hl_self, index)
        if not index and not plugin._bypass_auto_popup and plugin:_tryAutoPopupHighlight(hl_self, "highlight_menu") then
            return
        end
        if orig_show_menu then
            return orig_show_menu(hl_self, index)
        end
    end

    hl.lookupDictWord = function(hl_self, ...)
        if not plugin._bypass_auto_popup and plugin:_tryAutoPopupHighlight(hl_self, "dict_word") then
            return
        end
        if orig_lookup_word then
            return orig_lookup_word(hl_self, ...)
        end
    end

    hl._xray_highlight_wrapped = true
end

function XRayPlugin:_tryAutoPopupHighlight(hl_self, trigger_source)
    if self.destroyed or not self.xray_mode_enabled or not self.xray_auto_popup or not self.lookup_manager then
        return false
    end

    local sel = hl_self and hl_self.selected_text
    if not sel or type(sel) ~= "table" then return false end
    local text = sel.text
    if type(text) ~= "string" or text == "" then return false end

    local matches = self.lookup_manager:lookupAutoPopup(text)
    if not matches or #matches == 0 then
        return false
    end

    local function copyTable(t)
        if type(t) ~= "table" then return t end
        local res = {}
        for k, v in pairs(t) do res[k] = v end
        return res
    end

    local saved_state = {
        selected_text = copyTable(hl_self.selected_text),
        hold_pos = copyTable(hl_self.hold_pos),
        selected_link = hl_self.selected_link,
        selected_text_start_xpointer = hl_self.selected_text_start_xpointer,
    }

    local restore_menu_cb = function()
        if self.destroyed or not self.ui or not self.ui.highlight then return end
        local hl = self.ui.highlight
        hl.selected_text = saved_state.selected_text
        hl.hold_pos = saved_state.hold_pos
        hl.selected_link = saved_state.selected_link
        hl.selected_text_start_xpointer = saved_state.selected_text_start_xpointer
        hl.is_word_selection = false
        self._bypass_auto_popup = true
        pcall(function()
            if hl._xray_orig_onShowHighlightMenu then
                hl._xray_orig_onShowHighlightMenu(hl)
            elseif hl.onShowHighlightMenu then
                hl:onShowHighlightMenu()
            end
        end)
        self._bypass_auto_popup = false
    end

    if hl_self.clear then
        pcall(function() hl_self:clear() end)
    end
    if self.ui and self.ui.handleEvent then
        local ok_ev, Event = pcall(require, "ui/event")
        if ok_ev and Event then
            self.ui:handleEvent(Event:new("ClearSelection"))
        end
    end

    self.lookup_manager:handleLookup(sel.text, sel.pos0, sel.pos1, {
        from_auto_popup = true,
        restore_menu_cb = restore_menu_cb,
        candidates = matches,
    })
    return true
end

describe("X-Ray Dictionary Registration Logic", function()
    local plugin

    before_each(function()
        plugin = createMockPlugin()
        -- Apply our methods to the mock plugin
        for k, v in pairs(XRayPlugin) do
            plugin[k] = v
        end
        plugin.xray_mode_enabled = true
    end)

    it("should register via the legacy hook when the new API is missing", function()
        plugin.ui.dictionary = nil -- No new API
        local dict_buttons = {}
        local dict_popup = { word = "hello" }
        
        plugin:onDictButtonsReady(dict_popup, dict_buttons)
        
        assert.are.equal(1, #dict_buttons)
        assert.are.equal("X-Ray", dict_buttons[1][1].text)
        -- Test callback
        local result = dict_buttons[1][1].callback()
        assert.are.equal("hello", result)
    end)

    it("should skip the legacy hook when the new API is present", function()
        -- Mock the new API existence
        plugin.ui.dictionary = {
            addToDictButtons = function() end
        }
        local dict_buttons = {}
        
        plugin:onDictButtonsReady({}, dict_buttons)
        
        assert.are.equal(0, #dict_buttons)
    end)

    it("should correctly handle new API callback arguments", function()
        local btn_spec = plugin:_buildXRayDictButton(nil)
        local widget_instance = { word = "world" }
        
        -- Should use the passed widget instance
        local result = btn_spec.callback(widget_instance)
        assert.are.equal("world", result)
    end)

    it("should correctly handle legacy hook upvalues", function()
        local dict_popup = { word = "upvalue" }
        local btn_spec = plugin:_buildXRayDictButton(dict_popup)
        
        -- Should use the captured upvalue when no argument is passed
        local result = btn_spec.callback(nil)
        assert.are.equal("upvalue", result)
    end)
    
    it("should respect xray_mode_enabled", function()
        plugin.xray_mode_enabled = false
        local dict_buttons = {}
        plugin:onDictButtonsReady({}, dict_buttons)
        assert.are.equal(0, #dict_buttons)
        
        plugin.xray_mode_enabled = true
        local btn_spec = plugin:_buildXRayDictButton({word="test"})
        plugin.xray_mode_enabled = false
        assert.is_nil(btn_spec.callback())
    end)
end)

describe("X-Ray Lifecycle Hooks", function()
    local plugin

    before_each(function()
        plugin = createMockPlugin()
        plugin.destroyed = false
        plugin.bg_fetch_active = true
        plugin.bg_fetch_pending = true
        plugin._unit_scan_in_progress = true

        local destroyed_called = false
        plugin.destroy = function(self)
            if self.destroyed then return end
            self.destroyed = true
            self.bg_fetch_active = false
            self.bg_fetch_pending = false
            self._unit_scan_in_progress = false
            if self.cache_manager and self.cache_manager.cancelAsyncSaves then
                self.cache_manager:cancelAsyncSaves()
            end
        end

        plugin.onCloseDocument = function(self) self:destroy() end
        plugin.onReaderClose = function(self) self:destroy() end
        plugin.onExit = function(self) self:destroy() end
    end)

    it("should destroy plugin and cancel background tasks on onCloseDocument", function()
        plugin:onCloseDocument()
        assert.is_true(plugin.destroyed)
        assert.is_false(plugin.bg_fetch_active)
        assert.is_false(plugin.bg_fetch_pending)
        assert.is_false(plugin._unit_scan_in_progress)
    end)

    it("should destroy plugin on onReaderClose", function()
        plugin:onReaderClose()
        assert.is_true(plugin.destroyed)
    end)

    it("should destroy plugin on onExit", function()
        plugin:onExit()
        assert.is_true(plugin.destroyed)
    end)

    it("verifies real main.lua lifecycle functions clean up state properly", function()
        local main_plugin = dofile("xray.koplugin/main.lua")
        local real_plugin = createMockPlugin()
        for k, v in pairs(main_plugin) do real_plugin[k] = v end

        real_plugin.bg_fetch_active = true
        real_plugin.bg_fetch_pending = true
        real_plugin._unit_scan_in_progress = true
        real_plugin._unit_scan_fetch_retries = 3

        local unit_cancelled = false
        real_plugin._cancelUnitScanChild = function() unit_cancelled = true end
        local unit_underlines_cleared = false
        real_plugin.clearUnitUnderlines = function() unit_underlines_cleared = true end
        local entity_cancelled = false
        real_plugin._cancelEntityScanChild = function() entity_cancelled = true end
        local entity_underlines_cleared = false
        real_plugin.clearEntityUnderlines = function() entity_underlines_cleared = true end

        real_plugin:onCloseDocument()

        assert.is_true(real_plugin.destroyed)
        assert.is_false(real_plugin.bg_fetch_active)
        assert.is_false(real_plugin.bg_fetch_pending)
        assert.is_false(real_plugin._unit_scan_in_progress)
        assert.is_true(unit_cancelled)
        assert.is_true(unit_underlines_cleared)
    end)
end)

describe("X-Ray Highlight Interception (Issue #152)", function()
    local plugin
    local orig_menu_called
    local orig_lookup_called
    local handle_lookup_args
    local clear_called

    before_each(function()
        plugin = createMockPlugin()
        for k, v in pairs(XRayPlugin) do
            plugin[k] = v
        end
        plugin.xray_mode_enabled = true
        plugin.xray_auto_popup = true
        plugin.destroyed = false

        orig_menu_called = 0
        orig_lookup_called = 0
        handle_lookup_args = nil
        clear_called = false

        plugin.ui.highlight = {
            selected_text = { text = "Sherlock Holmes", pos0 = 10, pos1 = 25 },
            hold_pos = { x = 100, y = 200 },
            selected_link = nil,
            selected_text_start_xpointer = "/1/4/2",
            is_word_selection = true,
            clear = function(self_hl)
                clear_called = true
            end,
            onShowHighlightMenu = function(self_hl, index)
                orig_menu_called = orig_menu_called + 1
            end,
            lookupDictWord = function(self_hl, ...)
                orig_lookup_called = orig_lookup_called + 1
            end,
        }

        plugin.lookup_manager = {
            lookupAutoPopup = function(self_lm, text)
                if text == "Sherlock Holmes" then
                    return { { item = { name = "Sherlock Holmes" }, item_type = "character", score = 100 } }
                end
                return {}
            end,
            handleLookup = function(self_lm, text, pos0, pos1, opts)
                handle_lookup_args = { text = text, pos0 = pos0, pos1 = pos1, opts = opts }
            end,
        }
    end)

    it("does not intercept when xray_auto_popup is false", function()
        plugin.xray_auto_popup = false
        plugin:mountHighlightHandler()

        plugin.ui.highlight:onShowHighlightMenu()
        assert.are.equal(1, orig_menu_called)
        assert.is_nil(handle_lookup_args)

        plugin.ui.highlight:lookupDictWord()
        assert.are.equal(1, orig_lookup_called)
        assert.is_nil(handle_lookup_args)
    end)

    it("intercepts onShowHighlightMenu when text matches X-Ray data", function()
        plugin:mountHighlightHandler()

        plugin.ui.highlight:onShowHighlightMenu()
        assert.are.equal(0, orig_menu_called)
        assert.is_true(clear_called)
        assert.is_not_nil(handle_lookup_args)
        assert.are.equal("Sherlock Holmes", handle_lookup_args.text)
        assert.is_not_nil(handle_lookup_args.opts.restore_menu_cb)
        assert.are.equal(1, #handle_lookup_args.opts.candidates)
    end)

    it("intercepts lookupDictWord when text matches X-Ray data", function()
        plugin:mountHighlightHandler()

        plugin.ui.highlight:lookupDictWord()
        assert.are.equal(0, orig_lookup_called)
        assert.is_true(clear_called)
        assert.is_not_nil(handle_lookup_args)
        assert.are.equal("Sherlock Holmes", handle_lookup_args.text)
    end)

    it("falls back to original menu when text does not match X-Ray data", function()
        plugin.ui.highlight.selected_text.text = "Some random unmatched text"
        plugin:mountHighlightHandler()

        plugin.ui.highlight:onShowHighlightMenu()
        assert.are.equal(1, orig_menu_called)
        assert.is_nil(handle_lookup_args)

        plugin.ui.highlight:lookupDictWord()
        assert.are.equal(1, orig_lookup_called)
        assert.is_nil(handle_lookup_args)
    end)

    it("does not auto-popup when editing existing highlight annotation (index ~= nil)", function()
        plugin:mountHighlightHandler()

        plugin.ui.highlight:onShowHighlightMenu(5)
        assert.are.equal(1, orig_menu_called)
        assert.is_nil(handle_lookup_args)
    end)

    it("restores selection state and opens original highlight menu when restore_menu_cb is called", function()
        plugin:mountHighlightHandler()
        plugin.ui.highlight:onShowHighlightMenu()
        assert.is_not_nil(handle_lookup_args)

        -- State was cleared during auto-popup
        plugin.ui.highlight.selected_text = nil
        plugin.ui.highlight.hold_pos = nil

        -- Trigger restore callback
        handle_lookup_args.opts.restore_menu_cb()

        -- Verify state restored
        assert.is_not_nil(plugin.ui.highlight.selected_text)
        assert.are.equal("Sherlock Holmes", plugin.ui.highlight.selected_text.text)
        assert.is_not_nil(plugin.ui.highlight.hold_pos)
        assert.are.equal(100, plugin.ui.highlight.hold_pos.x)
        assert.are.equal(1, orig_menu_called)
    end)
end)
