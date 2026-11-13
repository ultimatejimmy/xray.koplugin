-- X-Ray Plugin for KOReader v2.0.0
local logger = require("logger")

local ok_ui, UIManager = pcall(require, "ui/uimanager")
local ok_wc, WidgetContainer = pcall(require, "ui/widget/container/widgetcontainer")
local ok_log, logger = pcall(require, "logger")
if not ok_log then logger = { info = function() end, warn = function() end, error = function() end } end

local plugin_path = ((...) or ""):match("(.-)[^%.]+$") or ""
local ok_xl, XRayLogger = pcall(require, plugin_path .. "xray_logger")
local ok_xc, XRayConfig = pcall(require, plugin_path .. "xray_config")
local utils = require(plugin_path .. "xray_utils")


local XRayPlugin = (ok_wc and WidgetContainer and WidgetContainer.extend) and WidgetContainer:extend{
    name = "xray",
    is_doc_only = true,
} or { name = "xray_failed" }


-- Mixin pattern helper: merges module functions into the XRayPlugin object.
-- This keeps main.lua clean while allowing modules to use self:method() calls.
local function _t(self, key, default)
    if self.loc and self.loc.t then
        local val = self.loc:t(key)
        if val and val ~= key then
            return val
        end
    end
    return default
end

local function applyMixin(target, source)
    for k, v in pairs(source) do
        target[k] = v
    end
end


local function safeRequireMixin(name)
    local ok, mod = pcall(require, plugin_path .. name)
    if ok then
        applyMixin(XRayPlugin, mod)
    else
        logger.error("XRayPlugin: Failed to load mixin " .. name .. ": " .. tostring(mod))
    end
end

safeRequireMixin("xray_data")
safeRequireMixin("xray_ui")
safeRequireMixin("xray_fetch")
safeRequireMixin("xray_mentions")
safeRequireMixin("xray_unitscanner")
safeRequireMixin("xray_entityscanner")
safeRequireMixin("xray_anthology")
safeRequireMixin("xray_booktype")
safeRequireMixin("xray_style_cards")
safeRequireMixin("xray_menu_builder")


function XRayPlugin:init()
    local ok, err = pcall(function()
        if self.ui and self.ui.menu then
            self.ui.menu:registerToMainMenu(self)
        end
        self:onDispatcherRegisterActions()
        
        -- Force plugin to be first in the tools menu order (enforced on every document load)
        pcall(function()
            local ok_order, reader_menu_order = pcall(require, "ui/elements/reader_menu_order")
            if not ok_order then
                ok_order, reader_menu_order = pcall(require, "apps/reader/modules/readermenuorder")
            end
            if ok_order and reader_menu_order and reader_menu_order.tools then
                for i, v in ipairs(reader_menu_order.tools) do
                    if v == "xray" then table.remove(reader_menu_order.tools, i); break end
                end
                table.insert(reader_menu_order.tools, 1, "xray")
            end
        end)


    -- Clean up legacy un-prefixed module files from older versions to prevent namespace collisions
    local legacy_files = { "aihelper.lua", "cachemanager.lua", "chapteranalyzer.lua", "lookupmanager.lua", "updater.lua" }
    for _, file in ipairs(legacy_files) do
        local old_path = self.path .. "/" .. file
        local f = io.open(old_path, "r")
        if f then
            f:close()
            os.remove(old_path)
            self:log("XRayPlugin: Cleaned up legacy file " .. file)
        end
    end

    -- Clean up orphaned background fetch files from previous sessions
    pcall(function()
        local DataStorage = require("datastorage")
        local settings_xray_dir = DataStorage:getSettingsDir() .. "/xray"
        local ok, lfs = pcall(require, "libs/libkoreader-lfs")
        if not ok or type(lfs) ~= "table" then
            ok, lfs = pcall(require, "lfs")
        end
        if ok and lfs and lfs.dir then
            for file in lfs.dir(settings_xray_dir) do
                if file:find("^bg_fetch_.*%.json$") then
                    os.remove(settings_xray_dir .. "/" .. file)
                    self:log("XRayPlugin: Cleaned up orphaned fetch file " .. file)
                end
            end
        end
    end)

    local Localization = require(plugin_path .. "localization_xray")
    self.loc = Localization
    self.loc:init(self.path)

    XRayLogger:init(self.path)
    
    local AIHelper = require(plugin_path .. "xray_aihelper")
    self.ai_helper = AIHelper
    self.ai_helper:init(self.path)

    local ChapterAnalyzer = require(plugin_path .. "xray_chapteranalyzer")
    self.chapter_analyzer = ChapterAnalyzer:new{ plugin = self }
    
    -- Check if xray_key.txt exists to auto-import keys if none are set
    if not self.ai_helper:hasApiKey() then
        local ok, count, path = self.ai_helper:importFromTextFile(false)
        if ok and count > 0 then
            self:log(string.format("XRayPlugin: Auto-imported %d API key(s) from %s", count, tostring(path)))
            self.ai_helper:init(self.path)
        end
    end

    self.ai_provider = self.ai_helper.default_provider or "gemini"
    
    self.xray_mode_enabled = true
    if self.ai_helper.settings and self.ai_helper.settings.xray_mode_enabled ~= nil then
        self.xray_mode_enabled = self.ai_helper.settings.xray_mode_enabled
    end
    self.xray_auto_popup = false
    if self.ai_helper.settings and self.ai_helper.settings.xray_auto_popup ~= nil then
        self.xray_auto_popup = (self.ai_helper.settings.xray_auto_popup == true)
    end

    -- Auto-fetch on chapter change (session state)
    self.last_auto_chapter = nil
    self.last_bg_fetch_page = nil
    self.chapters_fetched = {}
    self.bg_fetch_pending = false
    self.pending_background_fetch = false
    self._background_catch_up_callback = nil
    self._chapter_fetch_callback = nil
    self._reader_ready = false
    self.auto_fetch_enabled = not (self.ai_helper.settings and
        self.ai_helper.settings.auto_fetch_on_chapter == false)

    -- Data tables initialization
    self.characters = {}
    self.locations = {}
    self.timeline = {}
    self.historical_figures = {}
    self.terms = {}
    self.images = {}
    self.book_type = nil
    
    -- Mentions Feature Gating
    self.mentions_enabled = true
    if self.ai_helper.settings and self.ai_helper.settings.mentions_enabled ~= nil then
        self.mentions_enabled = self.ai_helper.settings.mentions_enabled
    end

    -- Track dismissed language suggestions for the current session
    self.suggestion_dismissed = {}

    -- Modular lookup logic for text selection
    local LookupManager = require(plugin_path .. "xray_lookupmanager")
    self.lookup_manager = LookupManager:new(self)

    -- Standalone Series Manager
    local SeriesManager = require(plugin_path .. "xray_seriesmanager")
    self.series_manager = SeriesManager:new()

    -- Standalone Image Manager
    local ImageManager = require(plugin_path .. "xray_imagemanager")
    self.image_manager = ImageManager:new(self)
    
    self:log("XRayPlugin: Initialized with language: " .. self.loc:getLanguage())
    self:onDispatcherRegisterActions()
    
    if self.ui then
        self.ui:registerKeyEvents({
            ShowXRayMenu = {
                { "Alt", "X" },
                event = "ShowXRayMenu",
            },
            ShowXRayImages = {
                { "Alt", "I" },
                event = "ShowXRayImages",
            },
        })

        -- Hook into Highlight Dialog (long-press on existing highlights)
        if self.ui.highlight then
            self.ui.highlight:addToHighlightDialog("xray_lookup", function(_reader_highlight_instance)
                if not self.xray_mode_enabled then return end
                return {
                    text = "X-Ray",
                    callback = function()
                        -- Extract selection data BEFORE closing or clearing
                        local sel = _reader_highlight_instance and _reader_highlight_instance.selected_text or {}
                        local text = sel.text
                        local pos0 = sel.pos0
                        local pos1 = sel.pos1
                        
                        -- Directly tell the UIManager to close this specific dialog instance
                        if _reader_highlight_instance then
                            pcall(function() 
                                if _reader_highlight_instance.onClose then _reader_highlight_instance:onClose() end
                            end)
                            UIManager:close(_reader_highlight_instance)
                        end
                        
                        -- Execute optimized clear
                        self:closeAllMenus()
                        
                        -- Explicitly clear selection to prevent dictionary menu re-asserting
                        if self.ui and self.ui.handleEvent then
                            local Event = require("ui/event")
                            self.ui:handleEvent(Event:new("ClearSelection"))
                        end
                        
                        if text then
                            self.lookup_manager:handleLookup(text, pos0, pos1)
                        end
                    end,
                }
            end)
        end

        -- Safe no-op on older versions where addToDictButtons doesn't exist.
        if self.ui and self.ui.dictionary
                and type(self.ui.dictionary.addToDictButtons) == "function" then
            self.ui.dictionary:addToDictButtons({
                id = "xray_lookup",
                menu_text = _t(self, "menu_xray", "X-Ray"),
                text = "X-Ray",
                show_func = function() return self.xray_mode_enabled end,
                callback = self:_buildXRayDictButton(nil).callback,
            })
        end

        if self.mountHighlightHandler then
            self:mountHighlightHandler()
        end
    end
    
        logger.info("XRayPlugin: Initialized successfully")
    end)
    if not ok then
        logger.error("XRayPlugin: CRITICAL INIT ERROR: " .. tostring(err))
        if XRayLogger and type(XRayLogger) == "table" and XRayLogger.log then
            XRayLogger:log("CRITICAL INIT ERROR: " .. tostring(err))
        end
    end
end


function XRayPlugin:destroy()
    if self.destroyed then return end
    self:log("XRayPlugin: destroy called, marking as destroyed")
    if self.cancelActiveAIRequest then
        self:cancelActiveAIRequest("Plugin destroyed")
    elseif self.ai_helper then
        self.ai_helper:cancelAsyncChild()
    end
    self.destroyed = true
    
    if self.active_mention_scan and self.active_mention_scan.cancel_handle then
        self.active_mention_scan.cancel_handle:cancel()
        self.active_mention_scan = nil
    end

    if self.flushSeriesSync then
        pcall(function() self:flushSeriesSync() end)
    end

    if self.cache_manager then
        if self.cache_manager.flushAsyncSaves then
            self.cache_manager:flushAsyncSaves()
        elseif self.cache_manager.cancelAsyncSaves then
            self.cache_manager:cancelAsyncSaves()
        end
    end

    if self._cancelUnitScanChild then
        pcall(function() self:_cancelUnitScanChild("plugin destroyed") end)
    end
    if self._cancelEntityScanChild then
        pcall(function() self:_cancelEntityScanChild("plugin destroyed") end)
    end
    if self.clearEntityUnderlines then
        pcall(function() self:clearEntityUnderlines() end)
    end

    self.bg_fetch_active = false
    self.bg_fetch_pending = false
    self:clearPendingBackgroundFetch()
    self._unit_scan_in_progress = false

    self:closeAllMenus()
    if self.clearHighlightOverlay then
        pcall(function() self:clearHighlightOverlay() end)
    end
    if self.clearUnitUnderlines then
        pcall(function() self:clearUnitUnderlines() end)
    end
    if self.clearTileCaches then
        pcall(function() self:clearTileCaches() end)
    end
    if self.image_manager and self.image_manager.clearSpineCache then
        pcall(function() self.image_manager:clearSpineCache() end)
    end
    self._cached_toc = nil
    pcall(function()
        local ok_xl, xl = pcall(require, plugin_path .. "xray_logger")
        if ok_xl and xl and xl.flush then xl:flush() end
    end)
    
    if WidgetContainer.destroy then
        WidgetContainer.destroy(self)
    end
end

function XRayPlugin:onCloseDocument()
    self:log("XRayPlugin: onCloseDocument called")
    self:destroy()
end

function XRayPlugin:onReaderClose()
    self:log("XRayPlugin: onReaderClose called")
    self:destroy()
end

function XRayPlugin:onExit()
    self:log("XRayPlugin: onExit called")
    self:destroy()
end

function XRayPlugin:onSuspend()
    if self.flushSeriesSync then
        pcall(function() self:flushSeriesSync() end)
    end
    if self.cancelActiveAIRequest then
        self:cancelActiveAIRequest("Fetch cancelled because the device suspended")
    elseif self.ai_helper then
        self.ai_helper:cancelAsyncChild()
    end
end

-- Builds the X-Ray button spec for the dict popup.
-- Used by both the new addToDictButtons API and the legacy onDictButtonsReady hook.
function XRayPlugin:_buildXRayDictButton(dict_popup_arg)
    -- dict_popup_arg is either:
    --   new API: the DictQuickLookup widget instance (passed by KOReader as arg to callback)
    --   old API: the dict_popup captured as upvalue in onDictButtonsReady
    return {
        text = "X-Ray",
        callback = function(widget_instance)
            if not self.xray_mode_enabled then return end
            -- In new API, widget_instance is passed. In old API, use upvalue.
            local popup = widget_instance or dict_popup_arg
            local raw_text = popup and (popup.word or popup.text or popup.selection_text)
            if type(raw_text) == "table" then
                raw_text = raw_text.text or raw_text.word or raw_text.selection_text
            end
            local text = (type(raw_text) == "string" and raw_text ~= "") and raw_text or nil
            local pos0 = popup and popup.pos0
            local pos1 = popup and popup.pos1
            
            -- Close the native dictionary popup immediately so it doesn't linger
            if popup then pcall(function() UIManager:close(popup) end) end
            
            -- Execute optimized clear and clear selection
            self:closeAllMenus()
            if self.ui and self.ui.handleEvent then
                local Event = require("ui/event")
                self.ui:handleEvent(Event:new("ClearSelection"))
            end
            
            if text and self.lookup_manager then
                self.lookup_manager:handleLookup(text, pos0, pos1)
            end
        end,
    }
end

-- Hook for Dictionary/Selection Popup (single word)
function XRayPlugin:onDictButtonsReady(dict_popup, dict_buttons)
    if not self.xray_mode_enabled then return end
    -- If new KOReader API is present, we already registered at init() time.
    -- This hook won't be called on new KOReader anyway, but guard for safety.
    if self.ui and self.ui.dictionary
            and type(self.ui.dictionary.addToDictButtons) == "function" then
        return
    end

    local btn = self:_buildXRayDictButton(dict_popup)
    local xray_button = {
        text = btn.text,
        callback = function() btn.callback(nil) end, -- nil => uses dict_popup upvalue
    }

    -- KOReader expects rows of buttons. Wrap our button in a row.
    -- We insert it at index 2 (usually the second row) to ensure it's visible.
    if #dict_buttons >= 1 then
        table.insert(dict_buttons, 2, { xray_button })
    else
        table.insert(dict_buttons, { xray_button })
    end
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

function XRayPlugin:log(msg)
    XRayLogger:log(msg)
end

function XRayPlugin:_getFlatToc()
    if self._cached_toc then
        return self._cached_toc
    end
    if not self.ui or not self.ui.document or not self.ui.document.getToc then
        return nil
    end
    local ok, raw_toc = pcall(function() return self.ui.document:getToc() end)
    if ok and raw_toc then
        local utils = require(plugin_path .. "xray_utils")
        self._cached_toc = utils:flattenTOC(raw_toc)
    end
    return self._cached_toc
end

function XRayPlugin:onLowMemory()
    self:log("XRayPlugin: onLowMemory received. Releasing caches.")
    if self.clearTileCaches then
        pcall(function() self:clearTileCaches() end)
    end
    if self.clearEntityUnderlines then
        pcall(function() self:clearEntityUnderlines() end)
    end
    self._box_cache_sig = nil
    self._entity_box_cache_sig = nil
    if self.clearSpineCache then
        pcall(function() self:clearSpineCache() end)
    end
    self._cached_toc = nil
    local ChapterAnalyzer = require(plugin_path .. "xray_chapteranalyzer")
    if ChapterAnalyzer and ChapterAnalyzer.clearCache then
        pcall(function() ChapterAnalyzer:clearCache() end)
    end
    if self.is_sequential_scan_active then
        self:log("XRayPlugin: Halting background sequential prefetch due to low memory event.")
        self.active_sequential_cancelled = true
    end
    collectgarbage("collect")
end

function XRayPlugin:onReaderReady()
    self._cached_toc = nil
    self:clearPendingBackgroundFetch()
    self:autoLoadCache()
    -- Reset per-session chapter fetch tracking
    self.last_auto_chapter = nil
    self.last_bg_fetch_page = nil
    self.chapters_fetched = self.chapters_fetched or {}
    self.bg_fetch_pending = false
    self:clearPendingBackgroundFetch()
    self._reader_ready = true
    self.unit_xp_matches = nil
    self.unit_conversion_boxes = nil
    self.last_settings_state = nil
    self.last_pageno = self:getCurrentPage()

    -- Mount overlays and tap handlers immediately
    if self.mountUnderlineOverlay then pcall(function() self:mountUnderlineOverlay() end) end
    if self.mountTapHandler then pcall(function() self:mountTapHandler() end) end
    if self.mountHighlightHandler then pcall(function() self:mountHighlightHandler() end) end
    if self.mountEntityUnderlineOverlay then pcall(function() self:mountEntityUnderlineOverlay() end) end
    if self.mountEntityTapHandler then pcall(function() self:mountEntityTapHandler() end) end

    -- Re-evaluate current page now that cache is loaded
    if self.auto_fetch_enabled then
        self:onPageUpdate(self.last_pageno)
    end

    local settings = self.ai_helper and self.ai_helper.settings or {}

    -- Load unit cache immediately if available without doing a full scan
    if self.loadUnitCache and settings.unit_converter_enabled ~= false then
        pcall(function() self:loadUnitCache() end)
    end
    -- Load entity cache immediately if available without doing a full scan
    if self.loadEntityCache and settings.entity_footnotes_enabled == true then
        pcall(function() self:loadEntityCache() end)
    end

    -- Run offline scans independently of modal prompt cards
    if self.scanBookForEntities and settings.entity_footnotes_enabled == true then
        self:scanBookForEntities()
    end
    if self.scanBookForUnits and settings.unit_converter_enabled ~= false then
        local is_auto = settings.unit_auto_scan_enabled ~= false
        if is_auto then
            -- Defer whole-book unit scanning by 20s so it doesn't collide with KOReader startup
            UIManager:scheduleIn(20, function()
                if self.destroyed or not self.ui or not self.ui.document then return end
                local ok_dev, Device = pcall(require, "device")
                local is_k = ok_dev and Device and Device.isKindle and Device:isKindle()
                local mem_threshold = is_k and (65 * 1024) or (35 * 1024)
                if utils:isLowMemory(mem_threshold) then
                    self:log(string.format("XRayPlugin: Memory low (<%dMB), skipping automatic unit book scan", math.floor(mem_threshold / 1024)))
                    return
                end
                if self.triggerBookTypeDetection then
                    self:triggerBookTypeDetection()
                else
                    self:scanBookForUnits()
                end
            end)
        else
            -- Auto-scan off: only restore underlines from an existing cache
            self:scanBookForUnits()
        end
    end

    -- Initial promo and welcome prompt checks
    UIManager:scheduleIn(1.5, function()
        if self.destroyed or not self.ui or not self.ui.document then return end
        local has_key = self.ai_helper and type(self.ai_helper.hasApiKey) == "function" and self.ai_helper:hasApiKey()
        if not has_key and settings.welcome_wizard_dont_ask ~= true then
            if self.showWelcomeCard then self:showWelcomeCard() end
        elseif settings.unit_converter_enabled ~= false and settings.unit_new_feature_prompt_seen ~= true then
            if self.showUnitConverterNewFeatureCard then
                self:showUnitConverterNewFeatureCard()
            end
        elseif settings.entity_footnotes_enabled ~= true and settings.entity_new_feature_prompt_seen ~= true then
            if self.showEntityFootnotesNewFeatureCard then
                self:showEntityFootnotesNewFeatureCard()
            end
        end
    end)

    -- Initialize language based on logic (auto, book, or manual)
    self:applyLanguageLogic()
    
    -- Suggest switching to book language if appropriate (gated)
    local settings_lang = settings.language or "auto"
    if settings_lang ~= "book" then
        UIManager:scheduleIn(5, function()
            if self.destroyed or not self.ui or not self.ui.document then return end
            self:checkBookLanguageMatch()
        end)
    end
    
    -- Weekly silent update check (gated by time elapsed)
    local last_check = settings.last_update_check or 0
    local now = os.time()
    local week_seconds = 7 * 24 * 60 * 60
    if (now - last_check) > week_seconds then
        UIManager:scheduleIn(25, function()
            if self.destroyed or not self.ui or not self.ui.document then return end
            if utils:isLowMemory(25 * 1024) then
                self:log("XRayPlugin: Memory low, skipping weekly update check")
                return
            end
            self:checkWeeklyUpdate()
        end)
    end

    -- Check series context prompt after ~15 seconds (gated by feature flag)
    if settings.series_context_enabled == true then
        UIManager:scheduleIn(15, function()
            if self.destroyed or not self.ui or not self.ui.document then return end
            self:checkSeriesContext()
        end)
    end

    -- Enforce X-Ray as the first item in the Tools menu for all KOReader versions
    UIManager:scheduleIn(1, function()
        if self.destroyed then return end
        local order_module
        -- Strategy A: Check newer path (ui/elements/reader_menu_order)
        local status_new, res_new = pcall(require, "ui/elements/reader_menu_order")
        if status_new then
            order_module = res_new
        else
            -- Strategy B: Fallback to older path (apps/reader/modules/readermenuorder)
            local status_old, res_old = pcall(require, "apps/reader/modules/readermenuorder")
            if status_old then order_module = res_old end
        end
        if order_module and order_module.insertSorted then
            order_module.insertSorted("tools", "xray", 1)
        end
    end)

    if self.auto_fetch_enabled and settings.spoiler_setting == "full_book" then
        UIManager:scheduleIn(30, function()
            if self.destroyed or not self.ui or not self.ui.document then return end
            if utils:isLowMemory(30 * 1024) then
                self:log("XRayPlugin: Memory low, skipping startup catch-up fetch")
                return
            end
            if self:isCatchUpNeeded() and not self.bg_fetch_active and not self.bg_fetch_pending then
                self.pending_background_fetch = true
                self:scheduleBackgroundCatchUp(3)
            end
        end)
    end
end


function XRayPlugin:clearChapterFetchTimer()
    if self._chapter_fetch_callback then
        UIManager:unschedule(self._chapter_fetch_callback)
        self._chapter_fetch_callback = nil
    end
end

function XRayPlugin:clearPendingBackgroundFetch()
    self.pending_background_fetch = false
    self.bg_fetch_pending = false
    if self._background_catch_up_callback then
        UIManager:unschedule(self._background_catch_up_callback)
        self._background_catch_up_callback = nil
    end
    self:clearChapterFetchTimer()
end

function XRayPlugin:getCurrentPage()
    if self.ui then
        if self.ui.getCurrentPage then
            local ok, p = pcall(function() return self.ui:getCurrentPage() end)
            if ok and p then return p end
        end
        if self.ui.paging and self.ui.paging.getCurrentPage then
            local ok, p = pcall(function() return self.ui.paging:getCurrentPage() end)
            if ok and p then return p end
        end
        if self.ui.document and self.ui.document.getCurrentPage then
            local ok, p = pcall(function() return self.ui.document:getCurrentPage() end)
            if ok and p then return p end
        end
    end
    return self.last_pageno or 1
end

function XRayPlugin:getCatchUpTargetLimit()
    if not self.ui or not self.ui.document then return 0, false end
    local current_page = self.ui:getCurrentPage() or 1
    local total_pages = self.ui.document:getPageCount() or current_page
    if total_pages == 0 then total_pages = current_page end

    local spoiler_setting = self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.spoiler_setting or "spoiler_free"
    if spoiler_setting == "full_book" then
        return total_pages, true
    else
        return current_page, false
    end
end

-- Anthology mode functions extracted to xray_anthology.lua mixin

function XRayPlugin:isCatchUpNeeded()
    if not self.auto_fetch_enabled then return false end
    if not self.ai_helper or not self.ai_helper:hasApiKey() then return false end
    local target_limit = self:getCatchUpTargetLimit()
    if target_limit <= 0 then return false end

    if self:isAnthologyMode() then
        local current_story = self:getCurrentStory()
        if not current_story or not current_story.story_id then return false end
        local story_fetch_state = self.book_data and self.book_data.story_fetch_state or {}
        local st = story_fetch_state[current_story.story_id]
        local last_p = st and st.last_fetch_page or (current_story.start_page and (current_story.start_page - 1)) or 0
        local story_target = math.min(target_limit, current_story.end_page or target_limit)
        return last_p < story_target
    end

    local last_fetch_page = self.book_data and self.book_data.last_fetch_page or 0
    return last_fetch_page < target_limit
end

function XRayPlugin:getNextCatchUpBatch(start_page, target_page)
    if target_page <= start_page then
        return nil, nil, true
    end
    local toc = self:_getFlatToc() or {}
    local candidate_chapters = {}
    for i, entry in ipairs(toc) do
        local p = tonumber(entry.page)
        if p and p > start_page and p <= target_page then
            if not self:isNonNarrativeChapter(entry.title) then
                table.insert(candidate_chapters, { title = entry.title, page = p, index = i })
            end
        end
    end

    local BATCH_CHAPTER_LIMIT = 4
    if #candidate_chapters == 0 then
        -- No TOC entries between start_page and target_page (e.g. flat text or within single chapter)
        local diff = target_page - start_page
        if diff <= 50 then
            return target_page, ("Page " .. tostring(target_page)), true
        else
            local batch_end = math.min(target_page, start_page + 50)
            return batch_end, ("Page " .. tostring(batch_end)), false
        end
    elseif #candidate_chapters <= BATCH_CHAPTER_LIMIT then
        local last_ch = candidate_chapters[#candidate_chapters]
        return target_page, (last_ch.title or ("Page " .. tostring(target_page))), true
    else
        local batch_ch = candidate_chapters[BATCH_CHAPTER_LIMIT]
        local batch_end = batch_ch.page
        for idx = BATCH_CHAPTER_LIMIT + 1, #candidate_chapters do
            local next_p = candidate_chapters[idx].page
            if next_p > batch_ch.page then
                batch_end = next_p - 1
                break
            end
        end
        batch_end = math.min(target_page, batch_end)
        if batch_end <= start_page then
            batch_end = math.min(target_page, start_page + 1)
        end
        return batch_end, (batch_ch.title or ("Page " .. tostring(batch_end))), false
    end
end

local CATCHUP_COOLDOWN = 15 -- Inter-batch cooldown in seconds to avoid tight loops / API rate limits
XRayPlugin.CATCHUP_COOLDOWN = CATCHUP_COOLDOWN

function XRayPlugin:scheduleBackgroundCatchUp(delay)
    if not self.pending_background_fetch then return end
    if not self.auto_fetch_enabled then
        self:clearPendingBackgroundFetch()
        return
    end
    if self.destroyed or not self.ui or not self.ui.document then return end
    local document = self.ui.document

    if self._background_catch_up_callback then return end

    local callback
    callback = function()
        if self._background_catch_up_callback ~= callback then return end
        self._background_catch_up_callback = nil
        if self.destroyed or not self.ui or self.ui.document ~= document then return end
        if not self.pending_background_fetch then return end
        if not self.auto_fetch_enabled then
            self:clearPendingBackgroundFetch()
            return
        end

        local target_limit, is_full_book = self:getCatchUpTargetLimit()
        local last_fetch_page = self.book_data and self.book_data.last_fetch_page
        if self:isAnthologyMode() then
            local curr_page = self.ui:getCurrentPage()
            local curr_story = self:getCurrentStory(curr_page)
            if curr_story then
                local st_state = self.book_data and self.book_data.story_fetch_state and self.book_data.story_fetch_state[curr_story.story_id]
                last_fetch_page = st_state and st_state.last_fetch_page or (curr_story.start_page and curr_story.start_page > 1 and (curr_story.start_page - 1) or 0)
                target_limit = math.min(target_limit, curr_story.end_page or target_limit)
            end
        end
        if last_fetch_page and last_fetch_page >= target_limit then
            self:clearPendingBackgroundFetch()
            return
        end
        if not self.ai_helper or not self.ai_helper:hasApiKey() then return end

        -- SILENT NETWORK CHECK: strictly passive route check, NEVER block on DNS or show Wi-Fi dialogs
        if not utils:isSilentNetworkAvailable() then
            -- Still offline: keep pending_background_fetch = true, do NOT poll
            return
        end

        -- Busy check: defer if another AI request or unit scan is running
        if self.bg_fetch_pending or self.bg_fetch_active or self._unit_scan_in_progress
                or self.is_sequential_scan_active
                or self._active_ai_cancel or (self.ai_helper and self.ai_helper._async_child_pid) then
            self:scheduleBackgroundCatchUp(10)
            return
        end

        -- Cooldown check between catch-up batches (15s)
        local catchup_cd = self.CATCHUP_COOLDOWN or CATCHUP_COOLDOWN
        local now = os.time()
        local remaining = (self.last_bg_fetch_time or 0) + catchup_cd - now
        if self.last_bg_fetch_time and remaining > 0 then
            self:scheduleBackgroundCatchUp(remaining)
            return
        end

        local total_pages = self.ui.document:getPageCount() or target_limit
        if total_pages == 0 then total_pages = target_limit end
        local start_page = last_fetch_page or 0
        local batch_end_page, chapter_title, is_final = self:getNextCatchUpBatch(start_page, target_limit)
        local target_page = batch_end_page or target_limit

        local reading_percent = math.floor((target_page / total_pages) * 100)
        local spoiler_setting = self.ai_helper.settings and self.ai_helper.settings.spoiler_setting or "spoiler_free"
        if spoiler_setting == "full_book" and is_final then
            reading_percent = 100
        end

        local is_update = true
        if not self.timeline or #self.timeline == 0 then
            is_update = false
        end

        self.fetch_attempts = self.fetch_attempts or {}
        local attempt_key = chapter_title or tostring(target_page)
        self.fetch_attempts[attempt_key] = (self.fetch_attempts[attempt_key] or 0) + 1
        self.last_bg_fetch_time = now
        self.last_bg_fetch_page = target_page

        self:log("XRayPlugin: Catch-up batch started for target page: " .. tostring(target_page) .. " (chapter: " .. tostring(chapter_title) .. ", final=" .. tostring(is_final) .. ")")

        self:continueWithFetch(reading_percent, is_update, last_fetch_page, true, target_page, function(success, err_code)
            if self.destroyed or not self.ui or self.ui.document ~= document then return end
            if success then
                self.last_bg_fetch_time = os.time()
                local curr_limit = self:getCatchUpTargetLimit()
                local lfp = self.book_data and self.book_data.last_fetch_page or target_page
                if self:isAnthologyMode() then
                    local curr_page = self.ui:getCurrentPage()
                    local curr_story = self:getCurrentStory(curr_page)
                    if curr_story then
                        local st_state = self.book_data and self.book_data.story_fetch_state and self.book_data.story_fetch_state[curr_story.story_id]
                        lfp = st_state and st_state.last_fetch_page or lfp
                        curr_limit = math.min(curr_limit, curr_story.end_page or curr_limit)
                    end
                end
                if lfp < curr_limit then
                    self:log("XRayPlugin: Batch completed up to page " .. tostring(lfp) .. ". Next batch queued for target page " .. tostring(curr_limit))
                    self.pending_background_fetch = true
                    self:scheduleBackgroundCatchUp(catchup_cd)
                else
                    self:log("XRayPlugin: Catch-up fully completed up to page " .. tostring(lfp))
                    self:clearPendingBackgroundFetch()
                end
            elseif err_code == "ALREADY_COVERED" then
                self:log("XRayPlugin: Catch-up batch already covered at page " .. tostring(target_page) .. ". Clearing pending catch-up.")
                self:clearPendingBackgroundFetch()
            else
                -- If failed, wait for next network event or reschedule if still online
                if utils:isSilentNetworkAvailable() then
                    self:scheduleBackgroundCatchUp(catchup_cd)
                end
            end
        end)
    end
    self._background_catch_up_callback = callback
    UIManager:scheduleIn(delay or 3, callback)
end

function XRayPlugin:checkPrefetchHorizon()
    if self.destroyed or not self.ui or not self.ui.document then return end
    if self.is_sequential_scan_active then return end
    local horizon = self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.prefetch_horizon_chapters or 0
    if horizon <= 0 then return end
    if not self.ai_helper or not self.ai_helper.hasApiKey or not self.ai_helper:hasApiKey() then return end
    if not utils:isSilentNetworkAvailable() then return end

    local cur_page = self.getCurrentDocPage and self:getCurrentDocPage() or (self.ui.getCurrentPage and self.ui:getCurrentPage()) or 1

    local toc = self:_getFlatToc()
    if not toc or #toc == 0 then return end

    local ChapterAnalyzer = require(plugin_path .. "xray_chapteranalyzer")
    local total_pages = self.ui and self.ui.document and self.ui.document.getPageCount and self.ui.document:getPageCount() or 0
    local expanded_toc = (ChapterAnalyzer and ChapterAnalyzer.expandOversizedTocChapters) and ChapterAnalyzer:expandOversizedTocChapters(toc, total_pages, 60) or toc

    local cur_chap_idx = 1
    for i, ch in ipairs(expanded_toc) do
        if ch.page and ch.page <= cur_page then
            cur_chap_idx = i
        else
            break
        end
    end

    local is_anthology = self.isAnthologyMode and self:isAnthologyMode()
    local cur_story = is_anthology and self.getCurrentStory and self:getCurrentStory(cur_page)

    local target_chapters = {}
    local end_idx = math.min(#expanded_toc, cur_chap_idx + horizon)
    for i = cur_chap_idx + 1, end_idx do
        local ch = expanded_toc[i]
        if ch and not (self.isNonNarrativeChapter and self:isNonNarrativeChapter(ch.title or ch.parent_title or "")) then
            -- In anthology mode, do not prefetch across stories into unrelated narratives
            if is_anthology and cur_story then
                if ch.page and cur_story.end_page and ch.page > cur_story.end_page then
                    break
                end
                ch.story_id = ch.story_id or cur_story.story_id
                ch.story_title = ch.story_title or cur_story.story_title
            end
            ch.toc_index = ch.toc_index or i
            local unique_id = (ch.title or ("Chapter " .. tostring(i))) .. "_" .. tostring(ch.page)
            self.chapters_fetched = self.chapters_fetched or {}
            if not self.chapters_fetched[unique_id] then
                table.insert(target_chapters, ch)
            end
        end
    end

    local cur_chap_name = expanded_toc[cur_chap_idx] and (expanded_toc[cur_chap_idx].parent_title or expanded_toc[cur_chap_idx].title) or "Unknown"
    self:log(string.format("XRayPlugin: Horizon check - Current page: %d (Chap %d: '%s'), Horizon: +%d chapters, Queued: %d upcoming chapters.",
        cur_page, cur_chap_idx, tostring(cur_chap_name), horizon, #target_chapters))

    if #target_chapters > 0 then
        self:queueSequentialChapterScan(target_chapters, false)
    end
end

function XRayPlugin:onNetworkConnected()
    local document = self.ui and self.ui.document
    if not document then return end
    self:log("XRayPlugin: onNetworkConnected fired. Scheduling series context check in 2 seconds.")
    UIManager:scheduleIn(2, function()
        if self.destroyed or not self.ui or self.ui.document ~= document then return end
        self:checkSeriesContext()
    end)

    local spoiler_setting = self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.spoiler_setting
    if self.pending_background_fetch or (spoiler_setting == "full_book" and self:isCatchUpNeeded()) then
        self.pending_background_fetch = true
        self:scheduleBackgroundCatchUp(3)
    end

    if self.checkPrefetchHorizon then
        self:checkPrefetchHorizon()
    end
end

function XRayPlugin:onResume()
    local spoiler_setting = self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.spoiler_setting
    if self.pending_background_fetch or (spoiler_setting == "full_book" and self:isCatchUpNeeded()) then
        self.pending_background_fetch = true
        self:scheduleBackgroundCatchUp(3)
    end
end

function XRayPlugin:onPosUpdate(pos, pageno)
    if self.destroyed then return end
    local pg = pageno or (self.getCurrentPage and self:getCurrentPage())
    if pg and pg ~= self.last_pageno then
        self.last_pageno = pg
        self._box_cache_sig = nil
        self._entity_box_cache_sig = nil
        if self.onPageUpdate then
            self:onPageUpdate(pg)
        end
    end
end

function XRayPlugin:onDocumentRerendered()
    if self.destroyed then return end
    self._box_cache_sig = nil
    self._entity_box_cache_sig = nil
    self.last_pageno = self.getCurrentPage and self:getCurrentPage() or self.last_pageno
    if self._rebuildEntityPageBuckets then
        self:_rebuildEntityPageBuckets()
    end
    if self.ui and self.ui.view then
        if self.ui.view.dialog then
            UIManager:setDirty(self.ui.view.dialog, "ui")
        end
        UIManager:setDirty(nil, "ui")
    end
end

function XRayPlugin:onDocumentPartiallyRerendered()
    self:onDocumentRerendered()
end

function XRayPlugin:onPageUpdate(pageno)
    if self.destroyed or not self.ui or not self.ui.document then return end
    self.last_pageno = pageno

    if self.pending_return_banner then
        local p = self.pending_return_banner
        self.pending_return_banner = nil
        UIManager:scheduleIn(0.3, function()
            if self.destroyed or not self.ui or not self.ui.document then return end
            if p.is_image and self.showImageReturnBanner then
                self:showImageReturnBanner(p.return_page, p.image_entry, self.last_pageno)
            elseif self.showReturnBanner then
                self:showReturnBanner(p.return_page, p.entity, p.mentions, self.last_pageno)
            end
        end)
    elseif not self.is_programmatic_navigation then
        if self.return_banner then
            self:closeAllMenus()
        end
    end
    if not self.auto_fetch_enabled then
        self:clearPendingBackgroundFetch()
        return
    end
    
    if not self.ui or not self.ui.document then return end
    if not self._reader_ready then return end

    -- 1. Ultra mode: bypass chapter-boundary and is_populated guards; fire on page interval alone
    local page_interval = self.ai_helper.settings and self.ai_helper.settings.auto_fetch_page_interval
    if page_interval and page_interval > 0 then
        local last = self.last_bg_fetch_page
        if not last then
            self.last_bg_fetch_page = pageno
            self:log("XRayPlugin: Ultra mode initialized last_bg_fetch_page to " .. tostring(pageno))
            -- If cache is completely empty, trigger initial silent fetch immediately
            if not self.timeline or #self.timeline == 0 then
                self:log("XRayPlugin: Cache is empty. Triggering immediate initial fetch in Ultra mode.")
                local chapter_title = nil
                local toc = self:_getFlatToc()
                if toc and #toc > 0 then
                    local max_p = -1
                    for _, entry in ipairs(toc) do
                        if entry.page then
                            local p = tonumber(entry.page)
                            if p and p <= pageno and p >= max_p then
                                max_p = p
                                chapter_title = entry.title
                            end
                        end
                    end
                end
                chapter_title = chapter_title or ("Page " .. tostring(pageno))

                if not (self.bg_fetch_pending or self.bg_fetch_active or self.is_sequential_scan_active) then
                    self.bg_fetch_pending = true
                    self:clearChapterFetchTimer()
                    local cb
                    cb = function()
                        if self._chapter_fetch_callback ~= cb then return end
                        self._chapter_fetch_callback = nil
                        if self.destroyed or not self.ui or not self.ui.document then return end
                        self.bg_fetch_pending = false
                        self:triggerBackgroundMergeFetch(chapter_title)
                    end
                    self._chapter_fetch_callback = cb
                    UIManager:scheduleIn(2, cb)
                end
            end
            return
        end

        -- Use absolute difference to handle backward navigation, page jumps, etc.
        local diff = math.abs(pageno - last)
        if diff < page_interval then
            return
        end
        self:log("XRayPlugin: Ultra mode page interval crossed. Page: " .. tostring(pageno) .. ", Last: " .. tostring(last) .. ", Diff: " .. tostring(diff) .. ", Interval: " .. tostring(page_interval))
        self.last_bg_fetch_page = pageno

        -- Check if catch-up is actually needed before scheduling an Ultra mode fetch
        if not self:isCatchUpNeeded() then
            self:log("XRayPlugin: Ultra mode page interval crossed, but catch-up is not needed.")
            return
        end

        -- Debounce: ignore if a fetch is already scheduled or active
        if self.bg_fetch_pending or self.bg_fetch_active or self.is_sequential_scan_active then 
            self:log("XRayPlugin: Fetch already pending or active. Debouncing Ultra mode trigger.")
            return 
        end
        self.bg_fetch_pending = true

        -- Resolve current chapter title from TOC if available
        local chapter_title = nil
        local toc = self:_getFlatToc()
        if toc and #toc > 0 then
            local max_p = -1
            for _, entry in ipairs(toc) do
                if entry.page then
                    local p = tonumber(entry.page)
                    if p and p <= pageno and p >= max_p then
                        max_p = p
                        chapter_title = entry.title
                    end
                end
            end
        end
        chapter_title = chapter_title or ("Page " .. tostring(pageno))

        self:clearChapterFetchTimer()
        local cb
        cb = function()
            if self._chapter_fetch_callback ~= cb then return end
            self._chapter_fetch_callback = nil
            if self.destroyed or not self.ui or not self.ui.document then return end
            self.bg_fetch_pending = false
            self:triggerBackgroundMergeFetch(chapter_title)
        end
        self._chapter_fetch_callback = cb
        UIManager:scheduleIn(2, cb)
        return
    end

    -- 2. Standard chapter-based mode checks (requires TOC)
    -- Resolve current chapter title from TOC
    local toc = self:_getFlatToc()
    if not toc or #toc == 0 then
        return
    end

    local chapter_title = nil
    local chapter_page = nil
    local max_p = -1
    for _, entry in ipairs(toc) do
        if entry.page then
            local p = tonumber(entry.page)
            if p and p <= pageno and p >= max_p then
                max_p = p
                chapter_title = entry.title
                chapter_page = entry.page
            end
        end
    end

    if not chapter_title then
        return
    end

    local unique_id = chapter_title .. "_" .. tostring(chapter_page)

    -- Skip non-narrative chapters (Frontmatter/Backmatter)
    if self:isNonNarrativeChapter(chapter_title) then 
        if not self.chapters_fetched[unique_id] then
            self:log("XRayPlugin: Skipping non-narrative chapter: " .. tostring(chapter_title) .. " (page " .. tostring(chapter_page) .. ")")
            self.chapters_fetched[unique_id] = true
        end
        return 
    end

    -- Check if it's already populated in the timeline data
    local is_populated = false
    local norm_title = self:normalizeChapterName(chapter_title)
    for _, ev in ipairs(self.timeline or {}) do
        -- Duplicate = same chapter name AND same page number.
        -- If either page is nil, treat as distinct (prevents omnibus chapter collapse).
        if self:normalizeChapterName(ev.chapter or "") == norm_title then
            if ev.page and chapter_page and ev.page == chapter_page then
                is_populated = true
                break
            end
        end
    end

    if is_populated then
        if not self.chapters_fetched[unique_id] then
            self:log("XRayPlugin: Chapter already populated in data: " .. tostring(chapter_title) .. " (page " .. tostring(chapter_page) .. ")")
        end
        self.chapters_fetched[unique_id] = true
        local spoiler_setting = self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.spoiler_setting
        if spoiler_setting == "full_book" and self:isCatchUpNeeded() then
            if not self.pending_background_fetch and not self.bg_fetch_active and not self.bg_fetch_pending then
                self.pending_background_fetch = true
                self:scheduleBackgroundCatchUp(5)
            end
        end
        if self.checkPrefetchHorizon then
            self:checkPrefetchHorizon()
        end
        return
    end

    -- It is NOT populated. Limit retries to prevent API spamming.
    self.fetch_attempts = self.fetch_attempts or {}
    if (self.fetch_attempts[unique_id] or 0) >= 3 then
        self:log("XRayPlugin: Max fetch attempts reached for: " .. tostring(unique_id))
        self.chapters_fetched[unique_id] = true
        return
    end

    -- Already fetched this chapter this session?
    if self.chapters_fetched[unique_id] then 
        if self.checkPrefetchHorizon then
            self:checkPrefetchHorizon()
        end
        return 
    end

    -- Same chapter as before (no change)?
    if unique_id == self.last_auto_chapter then return end
    self.last_auto_chapter = unique_id

    -- Debounce: ignore if a fetch is already scheduled
    if self.bg_fetch_pending or self.bg_fetch_active or self.is_sequential_scan_active then 
        return 
    end
    self.bg_fetch_pending = true

    -- Wait 2s for the reader to settle on the new chapter before fetching
    self:clearChapterFetchTimer()
    local cb
    cb = function()
        if self._chapter_fetch_callback ~= cb then return end
        self._chapter_fetch_callback = nil
        if self.destroyed or not self.ui or not self.ui.document then return end
        self.bg_fetch_pending = false
        self:triggerBackgroundMergeFetch(chapter_title)
    end
    self._chapter_fetch_callback = cb
    UIManager:scheduleIn(2, cb)
end

function XRayPlugin:triggerBackgroundMergeFetch(chapter_title)
    if self.destroyed or not self.ui or not self.ui.document then return end
    if self._unit_scan_in_progress then
        self:log("XRayPlugin: Deferring background AI fetch because unit scan is in progress")
        UIManager:scheduleIn(5, function()
            if self.destroyed or not self.ui or not self.ui.document then return end
            self:triggerBackgroundMergeFetch(chapter_title)
        end)
        return
    end
    if self.bg_fetch_active or self.is_sequential_scan_active then return end
    if not self.ui or not self.ui.document then return end


    -- SILENT NETWORK CHECK: use hasDefaultRoute() via helper to avoid DNS freezes and Wi-Fi dialogs
    if utils:isSilentNetworkAvailable() then
        -- Safety Check: Ensure API keys are configured before background activity
        if not self.ai_helper:hasApiKey() then
            return
        end

        -- Foreground requests own the single async child slot and its global
        -- cancel handler. Do not consume the background cooldown or disturb
        -- that ownership while one is active.
        if self._active_ai_cancel or (self.ai_helper and self.ai_helper._async_child_pid) or self.is_sequential_scan_active then
            self:log("XRayPlugin: Skipping background fetch because another AI request is active")
            return
        end

        local document = self.ui.document
        local target_limit, is_full_book = self:getCatchUpTargetLimit()
        if target_limit <= 0 then return end

        if utils:isLowMemory(30 * 1024) then
            self:log("XRayPlugin: Memory low (<30MB), skipping background catch-up batch")
            return
        end

        local last_fetch_page = self.book_data and self.book_data.last_fetch_page
        if self:isAnthologyMode() then
            local curr_page = self.ui:getCurrentPage()
            local curr_story = self:getCurrentStory(curr_page)
            if curr_story then
                local st_state = self.book_data and self.book_data.story_fetch_state and self.book_data.story_fetch_state[curr_story.story_id]
                last_fetch_page = st_state and st_state.last_fetch_page or (curr_story.start_page and curr_story.start_page > 1 and (curr_story.start_page - 1) or 0)
                target_limit = math.min(target_limit, curr_story.end_page or target_limit)
            end
        end
        if last_fetch_page and last_fetch_page >= target_limit then
            self:clearPendingBackgroundFetch()
            return
        end

        -- Cooldown check to prevent API spamming
        local cooldown = self.ai_helper.settings and self.ai_helper.settings.auto_fetch_cooldown or 300
        local now = os.time()
        if self.last_bg_fetch_time and (now - self.last_bg_fetch_time) < cooldown then
            return
        end
        self.last_bg_fetch_time = now

        local total_pages = self.ui.document:getPageCount() or target_limit
        if total_pages == 0 then total_pages = target_limit end

        local start_page = last_fetch_page or 0
        local batch_end_page, batch_chapter_title, is_final = self:getNextCatchUpBatch(start_page, target_limit)
        local target_page = batch_end_page or target_limit

        local reading_percent = math.floor((target_page / total_pages) * 100)
        local spoiler_setting = self.ai_helper.settings and self.ai_helper.settings.spoiler_setting or "spoiler_free"
        if spoiler_setting == "full_book" and is_final then
            reading_percent = 100
        end

        local is_update = true
        if not self.timeline or #self.timeline == 0 then
            is_update = false
            self:log("XRayPlugin: Cache is empty. Switching to normal fetch instead of merge.")
        else
            self:log("XRayPlugin: Auto-merge fetch for target page: " .. tostring(target_page) .. " (chapter: " .. tostring(batch_chapter_title or chapter_title) .. ", final=" .. tostring(is_final) .. ")")
        end

        self.fetch_attempts = self.fetch_attempts or {}
        local attempt_key = batch_chapter_title or chapter_title or tostring(target_page)
        self.fetch_attempts[attempt_key] = (self.fetch_attempts[attempt_key] or 0) + 1
        self:clearPendingBackgroundFetch()

        local on_complete_cb = function(success, err_code, err_msg)
            if self.destroyed or not self.ui or self.ui.document ~= document then return end
            if success then
                self.last_bg_fetch_time = os.time()
                local curr_limit = self:getCatchUpTargetLimit()
                local lfp = self.book_data and self.book_data.last_fetch_page or target_page
                if self:isAnthologyMode() then
                    local curr_page = self.ui:getCurrentPage()
                    local curr_story = self:getCurrentStory(curr_page)
                    if curr_story then
                        local st_state = self.book_data and self.book_data.story_fetch_state and self.book_data.story_fetch_state[curr_story.story_id]
                        lfp = st_state and st_state.last_fetch_page or lfp
                        curr_limit = math.min(curr_limit, curr_story.end_page or curr_limit)
                    end
                end
                if lfp < curr_limit then
                    self:log("XRayPlugin: Batch completed up to page " .. tostring(lfp) .. ". Next batch queued for target page " .. tostring(curr_limit))
                    self.pending_background_fetch = true
                    self:scheduleBackgroundCatchUp(self.CATCHUP_COOLDOWN or CATCHUP_COOLDOWN)
                else
                    self:log("XRayPlugin: Catch-up fully completed up to page " .. tostring(lfp))
                    self:clearPendingBackgroundFetch()
                end
            elseif err_code == "ALREADY_COVERED" then
                self:log("XRayPlugin: Auto-merge batch already covered at page " .. tostring(target_page) .. ". Clearing pending catch-up.")
                self:clearPendingBackgroundFetch()
            end
        end

        self:continueWithFetch(reading_percent, is_update, last_fetch_page, true, target_page, on_complete_cb) -- is_silent=true
    else
        -- Silently skip if offline
        self.pending_background_fetch = true
    end
end

function XRayPlugin:onDispatcherRegisterActions()
    local ok, Dispatcher = pcall(require, "dispatcher")
    if not ok or not Dispatcher then return end
    
    pcall(function()
        Dispatcher:registerAction("xray_quick_menu", {
            category = "none",
            event = "ShowXRayQuickMenu",
            title = _t(self, "quick_menu_title", "X-Ray: Quick Menu"),
            general = true,
            separator = true,
        })
        Dispatcher:registerAction("xray_full_menu", {
            category = "none",
            event = "ShowXRayFullMenu",
            title = _t(self, "menu_xray", "X-Ray: Full Menu"),
            general = true,
        })
        Dispatcher:registerAction("xray_characters", {
            category = "none",
            event = "ShowXRayCharacters",
            title = _t(self, "menu_characters", "X-Ray: Characters"),
            general = true,
        })
        Dispatcher:registerAction("xray_locations", {
            category = "none",
            event = "ShowXRayLocations",
            title = _t(self, "menu_locations", "X-Ray: Locations"),
            general = true,
        })
        Dispatcher:registerAction("xray_terms", {
            category = "none",
            event = "ShowXRayTerms",
            title = _t(self, "menu_terms", "X-Ray: Glossary & Terms"),
            general = true,
        })
        Dispatcher:registerAction("xray_timeline", {
            category = "none",
            event = "ShowXRayTimeline",
            title = _t(self, "menu_timeline", "X-Ray: Plot Timeline"),
            general = true,
        })
        Dispatcher:registerAction("xray_historical_figures", {
            category = "none",
            event = "ShowXRayHistoricalFigures",
            title = _t(self, "menu_historical_figures", "X-Ray: Historical Figures"),
            general = true,
        })
        Dispatcher:registerAction("xray_open_image_gallery", {
            category = "none",
            event = "ShowXRayImageGallery",
            title = _t(self, "menu_images", "X-Ray: Images & Maps"),
            general = true,
        })
        Dispatcher:registerAction("xray_images", {
            category = "none",
            event = "ShowXRayImages",
            title = _t(self, "menu_images", "X-Ray: Images"),
            general = true,
        })
    end)
end

function XRayPlugin:onShowXRayQuickMenu()
    self:showQuickXRayMenu()
    return true
end

function XRayPlugin:onShowXRayMenu()
    self:showQuickXRayMenu()
    return true
end

function XRayPlugin:onShowXRayFullMenu()
    self:showFullXRayMenu()
    return true
end

function XRayPlugin:onShowXRayCharacters()
    self:showCharacters()
    return true
end

function XRayPlugin:onShowXRayLocations()
    self:showLocations()
    return true
end

function XRayPlugin:onShowXRayTerms()
    self:showTerms()
    return true
end

function XRayPlugin:onShowXRayTimeline()
    self:showTimeline()
    return true
end

function XRayPlugin:onShowXRayHistoricalFigures()
    self:showHistoricalFigures()
    return true
end

function XRayPlugin:onShowXRayImageGallery()
    local UIManager = require("ui/uimanager")
    UIManager:nextTick(function()
        self:showImages()
    end)
    return true
end

function XRayPlugin:onShowXRayImages()
    local UIManager = require("ui/uimanager")
    UIManager:nextTick(function()
        self:showImages()
    end)
    return true
end

function XRayPlugin:autoLoadCache()
    if not self.cache_manager then
        local CacheManager = require(plugin_path .. "xray_cachemanager")
        self.cache_manager = CacheManager:new()
    end
    
    local book_path = self.ui.document.file
    self:log("XRayPlugin: Auto-loading cache for: " .. tostring(book_path))
    local cached_data = self.cache_manager:loadCache(book_path)
    
    if cached_data then
        self:log("XRayPlugin: Cache loaded successfully")
        -- Stage 1: Fast data restore (immediate)
        self.book_data = cached_data
        self.characters = cached_data.characters or {}
        self.locations = cached_data.locations or {}
        self.timeline = cached_data.timeline or {}
        self.historical_figures = cached_data.historical_figures or {}
        self.terms = cached_data.terms or {}
        self.images = cached_data.images or {}
        self.chapters_fetched = cached_data.chapters_fetched or {}
        if cached_data.timeline then
            for _, ev in ipairs(cached_data.timeline) do
                if ev.chapter and ev.page then
                    local uid = ev.chapter .. "_" .. tostring(ev.page)
                    self.chapters_fetched[uid] = true
                end
            end
        end
        
        -- Explicitly mark terms as fetched if they exist in cache
        if #self.terms > 0 then
            self.terms_fetched = true
        end

        -- Set book_type: priority is user override (if not "auto"), then detected book_type
        local mode_override = cached_data.book_mode_override or "auto"
        if mode_override ~= "auto" then
            self.book_type = mode_override
        else
            self.book_type = cached_data.book_type or nil
        end
        if cached_data.author_info then
            self.author_info = cached_data.author_info
        else
            self.author_info = {
                name = cached_data.author,
                description = cached_data.author_bio,
                birthDate = cached_data.author_birth,
                deathDate = cached_data.author_death
            }
        end
        if #self.characters > 0 and (not self.ai_helper or not self.ai_helper.settings or self.ai_helper.settings.xray_mode_enabled ~= false) then
            self.xray_mode_enabled = true
        end
        self.series_context_loaded = (cached_data.series_context_loaded == true)

        -- Synchronize loaded book data to SeriesCache if part of a series and series file is missing/older
        if self.series_manager and (cached_data.series_slug or cached_data.series or cached_data.series_name or (self.ui and self.ui.document)) then
            pcall(function()
                local props = self.ui and self.ui.document and self.ui.document.getProps and self.ui.document:getProps() or {}
                local function sanitizeMetadata(val)
                    if type(val) == "string" then return val
                    elseif type(val) == "table" then return table.concat(val, ", ")
                    else return "Unknown" end
                end
                local title = sanitizeMetadata(props.title or cached_data.title or cached_data.book_title)
                local author = sanitizeMetadata(props.authors or cached_data.author or cached_data.book_author)
                local series_info = self.series_manager:getSeriesInfo(cached_data, props, title, author)
                if series_info and series_info.slug and series_info.index and series_info.has_explicit_index ~= false then
                    local s_path = self.series_manager:getSeriesCachePath(series_info.slug)
                    local needs_sync = false
                    if s_path then
                        local lfs = require("libs/libkoreader-lfs")
                        local s_attr = lfs and lfs.attributes(s_path)
                        if not s_attr then
                            needs_sync = true
                        else
                            local book_cached_at = tonumber(cached_data.cached_at) or 0
                            if s_attr.modification < book_cached_at then
                                needs_sync = true
                            end
                        end
                    end
                    if not needs_sync and s_path then
                        local s_cache = self.series_manager:loadSeriesCache(series_info.slug)
                        if s_cache then
                            local entry = s_cache.books and s_cache.books[series_info.index]
                            local tracked_path = s_cache.book_paths and s_cache.book_paths[series_info.index]
                            local has_entities_fn = self.series_manager.hasBookEntities
                            local book_has_ent = has_entities_fn and has_entities_fn(cached_data)
                            local entry_has_ent = entry and has_entities_fn and has_entities_fn(entry)
                            if not entry or not entry.title or tracked_path ~= book_path or (book_has_ent and not entry_has_ent) then
                                needs_sync = true
                            end
                        end
                    end
                    if needs_sync and self.markSeriesSyncDirty then
                        self:markSeriesSyncDirty(series_info.slug, series_info.index, title, author, book_path, true)
                    end
                end
            end)
        end

        -- Stage 2: Restore Sort Order (Deferred 500ms)
        UIManager:scheduleIn(0.5, function()
            if self.destroyed or not self.ui or not self.ui.document then return end
            self:log("XRayPlugin: Stage 2 - Restoring sort order")
            local function restoreOrder(list)
                table.sort(list, function(a, b)
                    return (a.sort_order or 9999) < (b.sort_order or 9999)
                end)
            end
            restoreOrder(self.characters)
            restoreOrder(self.historical_figures)
            
            -- Wait a tick for the dictionary popup to close gracefully, then trigger X-Ray
            UIManager:scheduleIn(0.1, function()
                if self.destroyed or not self.ui or not self.ui.document then return end
                if self.ui and self.ui.dictionary and self.ui.dictionary.dict_window then
                    -- Trigger dictionary close safely
                    pcall(function()
                        self.ui.dictionary.dict_window:onClose()
                    end)
                end
                self:log("XRayPlugin: Stage 3 - Repairing pages and deduplicating")
                local utils = require(plugin_path .. "xray_utils")
                local toc = utils:flattenTOC(self.ui.document:getToc())
                self:assignTimelinePages(self.timeline, toc, false)
                if self.filterOrphanTimelineEvents then
                    self.timeline = self:filterOrphanTimelineEvents(self.timeline, toc)
                end
                self:sortTimelineByTOC(self.timeline)

                -- Stage 3: Only deduplicate — do NOT re-extract document text here.
                -- getTextFromXPointers is a blocking synchronous call that can freeze
                -- the UI for many minutes on large books. The sort_order is already
                -- persisted in the cache and restored by Stage 2.
                self.characters = self:deduplicateByName(self.characters, "name")
                self.historical_figures = self:deduplicateByName(self.historical_figures, "name")
                self.locations = self:deduplicateByName(self.locations, "name")
                self.terms = self:deduplicateByName(self.terms, "name")

                if self:isAnthologyMode() and self.retagEntitiesByStory then
                    self:retagEntitiesByStory()
                end

                self:log("XRayPlugin: Chunked post-load complete")
            end)
            UIManager:scheduleIn(0.2, function()
                if self.destroyed then return end
                pcall(function()
                    local ok_order, reader_menu_order = pcall(require, "ui/elements/reader_menu_order")
                    if not ok_order then
                        ok_order, reader_menu_order = pcall(require, "apps/reader/modules/readermenuorder")
                    end
                    if ok_order and reader_menu_order and reader_menu_order.tools then
                        for i, v in ipairs(reader_menu_order.tools) do
                            if v == "xray" then table.remove(reader_menu_order.tools, i); break end
                        end
                        table.insert(reader_menu_order.tools, 1, "xray")
                    end
                end)
            end)
        end)
    end
end

-- Extracted functions are now loaded via mixins (xray_data, xray_ui, xray_fetch, xray_mentions, xray_anthology, xray_booktype, xray_style_cards, xray_menu_builder)

return XRayPlugin
