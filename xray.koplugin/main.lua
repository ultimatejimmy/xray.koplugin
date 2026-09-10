-- X-Ray Plugin for KOReader v2.0.0
local logger = require("logger")

local ok_ui, UIManager = pcall(require, "ui/uimanager")
local ok_wc, WidgetContainer = pcall(require, "ui/widget/container/widgetcontainer")
local ok_log, logger = pcall(require, "logger")
if not ok_log then logger = { info = function() end, warn = function() end, error = function() end } end

local plugin_path = ((...) or ""):match("(.-)[^%.]+$") or ""
local ok_xl, XRayLogger = pcall(require, plugin_path .. "xray_logger")
local ok_xc, XRayConfig = pcall(require, plugin_path .. "xray_config")


local XRayPlugin = (ok_wc and WidgetContainer and WidgetContainer.extend) and WidgetContainer:extend{
    name = "xray",
    is_doc_only = true,
} or { name = "xray_failed" }


-- Mixin pattern helper: merges module functions into the XRayPlugin object.
-- This keeps main.lua clean while allowing modules to use self:method() calls.
local function _t(self, key, default)
    if self.loc and self.loc.t then
        return self.loc:t(key) or default
    end
    return default
end

local function applyMixin(target, source)
    for k, v in pairs(source) do
        target[k] = v
    end
end

local findUnitConverterMenuPath

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

    -- Auto-fetch on chapter change (session state)
    self.last_auto_chapter = nil
    self.last_bg_fetch_page = nil
    self.chapters_fetched = {}
    self.bg_fetch_pending = false
    self.pending_background_fetch = false
    self._background_catch_up_callback = nil
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

    if self.cache_manager and self.cache_manager.cancelAsyncSaves then
        self.cache_manager:cancelAsyncSaves()
    end

    if self.active_unit_scan_dialog then
        pcall(function() self.active_unit_scan_dialog:close() end)
        self.active_unit_scan_dialog = nil
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

function XRayPlugin:onReaderReady()
    self._cached_toc = nil
    self:autoLoadCache()
    -- Reset per-session chapter fetch tracking
    self.last_auto_chapter = nil
    self.last_bg_fetch_page = nil
    self.chapters_fetched = {}
    self.bg_fetch_pending = false
    self:clearPendingBackgroundFetch()

    local settings = self.ai_helper and self.ai_helper.settings or {}

    -- Initial unit scanner run
    UIManager:scheduleIn(1.5, function()
        if self.destroyed or not self.ui or not self.ui.document then return end
        if self.mountUnderlineOverlay then self:mountUnderlineOverlay() end
        if self.mountTapHandler then self:mountTapHandler() end
        

        local has_key = self.ai_helper and type(self.ai_helper.hasApiKey) == "function" and self.ai_helper:hasApiKey()
        if not has_key and settings.welcome_wizard_dont_ask ~= true then
            self:showWelcomeCard()
        elseif settings.unit_new_feature_prompt_seen ~= true then
            self:showUnitConverterNewFeatureCard()
        else
            if self.scanBookForUnits and settings.unit_converter_enabled ~= false then
                local is_auto = settings.unit_auto_scan_enabled ~= false
                if is_auto then
                    if self.triggerBookTypeDetection then
                        self:triggerBookTypeDetection()
                    else
                        self:scanBookForUnits()
                    end
                end
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
        UIManager:scheduleIn(10, function()
            if self.destroyed or not self.ui or not self.ui.document then return end
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
        UIManager:scheduleIn(5, function()
            if self.destroyed or not self.ui or not self.ui.document then return end
            if self:isCatchUpNeeded() and not self.bg_fetch_active and not self.bg_fetch_pending then
                self.pending_background_fetch = true
                self:scheduleBackgroundCatchUp(3)
            end
        end)
    end
end


function XRayPlugin:clearPendingBackgroundFetch()
    self.pending_background_fetch = false
    if self._background_catch_up_callback then
        UIManager:unschedule(self._background_catch_up_callback)
        self._background_catch_up_callback = nil
    end
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

function XRayPlugin:isCatchUpNeeded()
    if not self.auto_fetch_enabled then return false end
    if not self.ai_helper or not self.ai_helper:hasApiKey() then return false end
    local target_limit = self:getCatchUpTargetLimit()
    if target_limit <= 0 then return false end

    local last_fetch_page = self.book_data and self.book_data.last_fetch_page or 0
    return last_fetch_page < target_limit
end

function XRayPlugin:getNextCatchUpBatch(start_page, target_page)
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
        if last_fetch_page and last_fetch_page >= target_limit then
            self:clearPendingBackgroundFetch()
            return
        end
        if not self.ai_helper or not self.ai_helper:hasApiKey() then return end

        -- SILENT NETWORK CHECK: strictly passive check, NEVER show white-box popups or dialogs
        local NetworkMgr = require("ui/network/manager")
        if not NetworkMgr:isConnected() or not NetworkMgr:isOnline() then
            -- Still offline: keep pending_background_fetch = true, do NOT poll
            return
        end

        -- Busy check: defer if another AI request or unit scan is running
        if self.bg_fetch_pending or self.bg_fetch_active or self._unit_scan_in_progress
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

        self:continueWithFetch(reading_percent, is_update, last_fetch_page, true, target_page, function(success)
            if self.destroyed or not self.ui or self.ui.document ~= document then return end
            if success then
                self.last_bg_fetch_time = os.time()
                local curr_limit = self:getCatchUpTargetLimit()
                local lfp = self.book_data and self.book_data.last_fetch_page or target_page
                if lfp < curr_limit then
                    self:log("XRayPlugin: Batch completed up to page " .. tostring(lfp) .. ". Next batch queued for target page " .. tostring(curr_limit))
                    self.pending_background_fetch = true
                    self:scheduleBackgroundCatchUp(catchup_cd)
                else
                    self:log("XRayPlugin: Catch-up fully completed up to page " .. tostring(lfp))
                    self:clearPendingBackgroundFetch()
                end
            else
                -- If failed, wait for next network event or reschedule if still online
                local net = require("ui/network/manager")
                if net:isConnected() and net:isOnline() then
                    self:scheduleBackgroundCatchUp(catchup_cd)
                end
            end
        end)
    end
    self._background_catch_up_callback = callback
    UIManager:scheduleIn(delay or 3, callback)
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
end

function XRayPlugin:onResume()
    local spoiler_setting = self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.spoiler_setting
    if self.pending_background_fetch or (spoiler_setting == "full_book" and self:isCatchUpNeeded()) then
        self.pending_background_fetch = true
        self:scheduleBackgroundCatchUp(3)
    end
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

                if not (self.bg_fetch_pending or self.bg_fetch_active) then
                    self.bg_fetch_pending = true
                    UIManager:scheduleIn(2, function()
                        if self.destroyed or not self.ui or not self.ui.document then return end
                        self.bg_fetch_pending = false
                        self:triggerBackgroundMergeFetch(chapter_title)
                    end)
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

        -- Debounce: ignore if a fetch is already scheduled or active
        if self.bg_fetch_pending or self.bg_fetch_active then 
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

        UIManager:scheduleIn(2, function()
            if self.destroyed or not self.ui or not self.ui.document then return end
            self.bg_fetch_pending = false
            self:triggerBackgroundMergeFetch(chapter_title)
        end)
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
        return 
    end

    -- Same chapter as before (no change)?
    if unique_id == self.last_auto_chapter then return end
    self.last_auto_chapter = unique_id

    -- Debounce: ignore if a fetch is already scheduled
    if self.bg_fetch_pending or self.bg_fetch_active then 
        return 
    end
    self.bg_fetch_pending = true

    -- Wait 2s for the reader to settle on the new chapter before fetching
    UIManager:scheduleIn(2, function()
        if self.destroyed or not self.ui or not self.ui.document then return end
        self.bg_fetch_pending = false
        self:triggerBackgroundMergeFetch(chapter_title)
    end)
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
    if self.bg_fetch_active then return end
    if not self.ui or not self.ui.document then return end


    -- SILENT NETWORK CHECK: use isOnline() instead of runWhenOnline to avoid "white box" connecting dialogs
    local NetworkMgr = require("ui/network/manager")
    if NetworkMgr:isConnected() and NetworkMgr:isOnline() then
        -- Safety Check: Ensure API keys are configured before background activity
        if not self.ai_helper:hasApiKey() then
            return
        end

        -- Foreground requests own the single async child slot and its global
        -- cancel handler. Do not consume the background cooldown or disturb
        -- that ownership while one is active.
        if self._active_ai_cancel or (self.ai_helper and self.ai_helper._async_child_pid) then
            self:log("XRayPlugin: Skipping background fetch because another AI request is active")
            return
        end

        -- Cooldown check to prevent API spamming
        local cooldown = self.ai_helper.settings and self.ai_helper.settings.auto_fetch_cooldown or 300
        local now = os.time()
        if self.last_bg_fetch_time and (now - self.last_bg_fetch_time) < cooldown then
            return
        end
        self.last_bg_fetch_time = now

        local document = self.ui.document
        local target_limit, is_full_book = self:getCatchUpTargetLimit()
        if target_limit <= 0 then return end
        local total_pages = self.ui.document:getPageCount() or target_limit
        if total_pages == 0 then total_pages = target_limit end

        local last_fetch_page = self.book_data and self.book_data.last_fetch_page
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
                if lfp < curr_limit then
                    self:log("XRayPlugin: Batch completed up to page " .. tostring(lfp) .. ". Next batch queued for target page " .. tostring(curr_limit))
                    self.pending_background_fetch = true
                    self:scheduleBackgroundCatchUp(self.CATCHUP_COOLDOWN or CATCHUP_COOLDOWN)
                else
                    self:log("XRayPlugin: Catch-up fully completed up to page " .. tostring(lfp))
                    self:clearPendingBackgroundFetch()
                end
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
        Dispatcher:registerAction("xray_scan_units", {
            category = "none",
            event = "ShowXRayScanUnits",
            title = _t(self, "menu_unit_scan", "X-Ray: Scan Units"),
            general = true,
        })
        Dispatcher:registerAction("xray_toggle_unit_converter", {
            category = "none",
            event = "ToggleXRayUnitConverter",
            title = _t(self, "menu_unit_toggle", "X-Ray: Toggle Unit Converter"),
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

function XRayPlugin:onShowXRayScanUnits()
    if self.scanBookForUnits then
        self:scanBookForUnits()
    end
    return true
end

function XRayPlugin:onToggleXRayUnitConverter()
    if self.toggleUnitConverter then
        self:toggleUnitConverter()
    end
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
        if #self.characters > 0 then self.xray_mode_enabled = true end

        -- Synchronize loaded book data to SeriesCache if part of a series
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
                if series_info and series_info.slug and series_info.index then
                    self.series_manager:syncBookToSeriesCache(series_info.slug, series_info.index, cached_data, book_path)
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

function XRayPlugin:getMenuCounts()
    return {
        characters = self.characters and #self.characters or 0,
        locations = self.locations and #self.locations or 0,
        timeline = self.timeline and #self.timeline or 0,
        historical_figures = self.historical_figures and #self.historical_figures or 0,
        terms = self.terms and #self.terms or 0,
        images = self.images and #self.images or 0,
    }
end


function XRayPlugin:getSubMenuItems()
    local items = {
        {
            text = self.loc:t("menu_characters") or "Characters",
            keep_menu_open = true,
            callback = function() self:showCharacters() end,
        },
        {
            text = self.loc:t("menu_timeline") or "Timeline",
            keep_menu_open = true,
            callback = function() self:showTimeline() end,
        },
        {
            text = self.loc:t("menu_historical_figures") or "Historical Figures",
            keep_menu_open = true,
            callback = function() self:showHistoricalFigures() end,
        },
        {
            text = self.loc:t("menu_locations") or "Locations",
            keep_menu_open = true,
            callback = function() self:showLocations() end,
        },
    }

    table.insert(items, {
        text = self.loc:t("menu_terms") or "Glossary",
        keep_menu_open = true,
        callback = function() self:showTerms() end,
    })

    table.insert(items, {
        text = self.loc:t("menu_images") or "Images & Maps",
        keep_menu_open = true,
        callback = function() self:showImages() end,
    })

    table.insert(items, {
        text = self.loc:t("menu_author_info"),
        keep_menu_open = true,
        callback = function() self:showAuthorInfo() end,
        separator = true,
    })

    table.insert(items, {
        text = self.loc:t("menu_update_xray") or "Update X-Ray Data (Merge)",
        keep_menu_open = true,
        callback = function() self:updateFromAI() end,
        separator = true,
    })

    self.current_xray_menu_table = items
    table.insert(items, {
        text = self.loc:t("menu_settings") or "Settings",
        keep_menu_open = true,
        sub_item_table = {
            {
                text = self.loc:t("menu_display_ui_settings") or "Display & UI Settings",
                keep_menu_open = true,
                sub_item_table = {
                    {
                        text = self.loc:t("menu_ui_popup_intext") or "Use Footnote Style for In-text Lookups",
                        checked_func = function()
                            local val = self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.ui_popup_intext
                            if val == nil then return true end
                            return val
                        end,
                        callback = function()
                            if self.ai_helper and self.ai_helper.settings then
                                local current = self.ai_helper.settings.ui_popup_intext
                                if current == nil then current = true end
                                self.ai_helper:saveSettings({ ui_popup_intext = not current })
                            end
                        end,
                    },
                    {
                        text = self.loc:t("menu_ui_popup_menu") or "Use Footnote Style for Menu Lookups",
                        checked_func = function()
                            local val = self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.ui_popup_menu
                            if val == nil then return false end
                            return val
                        end,
                        callback = function()
                            if self.ai_helper and self.ai_helper.settings then
                                local current = self.ai_helper.settings.ui_popup_menu
                                if current == nil then current = false end
                                self.ai_helper:saveSettings({ ui_popup_menu = not current })
                            end
                        end,
                    },
                    {
                        text = self.loc:t("menu_linked_entries_settings") or "Linked Entries Settings",
                        keep_menu_open = true,
                        callback = function() self:showLinkedEntriesSettings() end,
                    },
                    {
                        text = self.loc:t("mentions_setting_title") or "Mentions Settings",
                        keep_menu_open = true,
                        callback = function() self:showMentionsSettings() end,
                    },
                }
            },
            {
                text = self.loc:t("menu_content_fetch_settings") or "Content & Fetch Settings",
                keep_menu_open = true,
                sub_item_table = {
                    {
                        text = self.loc:t("menu_auto_update_frequency") or "Auto X-Ray Settings",
                        keep_menu_open = true,
                        sub_item_table = {
                            {
                                text = self.loc:t("menu_frequency") or "Frequency",
                                keep_menu_open = true,
                                callback = function() self:showAutoUpdateSettings() end,
                            },
                            {
                                text = self.loc:t("auto_dupe_check_setting_title") or "Duplicate Check",
                                keep_menu_open = true,
                                callback = function() self:showAutoDupeCheckSettings() end,
                            },
                        }
                    },
                    {
                        text = self.loc:t("menu_book_mode") or "Book Type",
                        keep_menu_open = true,
                        callback = function() self:showBookTypeSettings() end,
                    },
                    {
                        text = self.loc:t("menu_desc_length_settings") or "Description Length Settings",
                        keep_menu_open = true,
                        sub_item_table = {
                            {
                                text = self.loc:t("menu_characters") or "Characters",
                                keep_menu_open = true,
                                callback = function() self:showEntityLengthPresets("char_desc_len", self.loc:t("menu_characters")) end,
                            },
                            {
                                text = self.loc:t("menu_locations") or "Locations",
                                keep_menu_open = true,
                                callback = function() self:showEntityLengthPresets("loc_desc_len", self.loc:t("menu_locations")) end,
                            },
                            {
                                text = self.loc:t("menu_timeline") or "Timeline",
                                keep_menu_open = true,
                                callback = function() self:showEntityLengthPresets("timeline_event_len", self.loc:t("menu_timeline"), true) end,
                            },
                            {
                                text = self.loc:t("menu_historical_figures") or "Historical Figures",
                                keep_menu_open = true,
                                callback = function() self:showEntityLengthPresets("hist_fig_bio_len", self.loc:t("menu_historical_figures")) end,
                            },
                            {
                                text = self.loc:t("menu_terms") or "Glossary",
                                keep_menu_open = true,
                                callback = function() self:showEntityLengthPresets("term_def_len", self.loc:t("menu_terms") or "Glossary") end,
                            },
                        }
                    },
                    {
                        text = self.loc:t("menu_series_context") or "Series Context",
                        keep_menu_open = true,
                        sub_item_table = {
                            {
                                text = self.loc:t("series_context_enabled_toggle") or "Enable Series Context",
                                checked_func = function() return self.ai_helper.settings.series_context_enabled end,
                                callback = function() self:toggleSeriesContextEnabled() end,
                            },
                            {
                                text = self.loc:t("menu_fetch_series_context") or "Fetch / Refresh Series Context",
                                keep_menu_open = true,
                                callback = function() self:manualFetchSeriesContext() end,
                            },
                            {
                                text = self.loc:t("menu_clear_series_cache") or "Clear Series Cache",
                                keep_menu_open = true,
                                callback = function() self:clearSeriesCache() end,
                            }
                        }
                    },
                    {
                        text = self.loc:t("spoiler_preference_title") or "Spoiler Settings",
                        keep_menu_open = true,
                        callback = function() self:showSpoilerSettings() end,
                    },
                }
            },
            {
                text = self.loc:t("menu_xray_mode"),
                keep_menu_open = true,
                callback = function() self:toggleXRayMode() end,
            },
            {
                is_unit_converter = true,
                text = self.loc:t("menu_unit_converter") or "Unit Converter",
                keep_menu_open = true,
                sub_item_table = {
                    {
                        text = self.loc:t("unit_conv_enabled") or "Enable Unit Converter",
                        checked_func = function()
                            return self.ai_helper.settings.unit_converter_enabled ~= false
                        end,
                        callback = function()
                            local current = self.ai_helper.settings.unit_converter_enabled ~= false
                            self.ai_helper:saveSettings({ unit_converter_enabled = not current })
                            if self.scanBookForUnits then self:scanBookForUnits() end
                        end
                    },
                    {
                        text = self.loc:t("unit_scan_written_numbers") or "Scan Written Numbers (e.g. 'five miles')",
                        keep_menu_open = true,
                        callback = function()
                            self:showUnitScanWrittenNumbersCard()
                        end
                    },
                    {
                        text = self.loc:t("unit_auto_scan_settings") or "Auto-Scan Settings",
                        keep_menu_open = true,
                        callback = function()
                            self:showUnitAutoScanCard()
                        end
                    },
                    {
                        text = self.loc:t("unit_manual_scan_button") or "Scan/Rescan",
                        keep_menu_open = true,
                        callback = function()
                            if self.scanBookForUnits then self:scanBookForUnits(true) end
                        end,
                        separator = true,
                    },
                    {
                        text = self.loc:t("unit_book_type_filter") or "Book Type Filter",
                        keep_menu_open = true,
                        sub_item_table_func = function()
                            return self:getBookTypeFilterMenu()
                        end
                    },
                    {
                        text = self.loc:t("unit_conv_direction") or "Conversion Direction",
                        keep_menu_open = true,
                        callback = function()
                            self:showUnitConversionDirectionSettings()
                        end
                    },
                    {
                        text = self.loc:t("unit_conv_style_settings") or "Style & Underline Settings",
                        keep_menu_open = true,
                        callback = function()
                            self:showUnitStyleCard()
                        end
                    },
                    {
                        text = self.loc:t("menu_unit_categories") or "Unit Categories",
                        keep_menu_open = true,
                        sub_item_table = {
                            {
                                text = "Length (mile, feet, inch, m, km...)",
                                checked_func = function()
                                    return self.ai_helper.settings.unit_cat_length ~= false
                                end,
                                callback = function()
                                    local curr = self.ai_helper.settings.unit_cat_length ~= false
                                    self.ai_helper:saveSettings({ unit_cat_length = not curr })
                                    if self.scanBookForUnits then self:scanBookForUnits() end
                                end
                            },
                            {
                                text = "Weight / Mass (pound, ounce, kg, g...)",
                                checked_func = function()
                                    return self.ai_helper.settings.unit_cat_weight ~= false
                                end,
                                callback = function()
                                    local curr = self.ai_helper.settings.unit_cat_weight ~= false
                                    self.ai_helper:saveSettings({ unit_cat_weight = not curr })
                                    if self.scanBookForUnits then self:scanBookForUnits() end
                                end
                            },
                            {
                                text = "Temperature (fahrenheit, celsius)",
                                checked_func = function()
                                    return self.ai_helper.settings.unit_cat_temp ~= false
                                end,
                                callback = function()
                                    local curr = self.ai_helper.settings.unit_cat_temp ~= false
                                    self.ai_helper:saveSettings({ unit_cat_temp = not curr })
                                    if self.scanBookForUnits then self:scanBookForUnits() end
                                end
                            },
                            {
                                text = "Volume (gallon, cup, liter, ml...)",
                                checked_func = function()
                                    return self.ai_helper.settings.unit_cat_volume ~= false
                                end,
                                callback = function()
                                    local curr = self.ai_helper.settings.unit_cat_volume ~= false
                                    self.ai_helper:saveSettings({ unit_cat_volume = not curr })
                                    if self.scanBookForUnits then self:scanBookForUnits() end
                                end
                            },
                            {
                                text = "Speed (mph, km/h)",
                                checked_func = function()
                                    return self.ai_helper.settings.unit_cat_speed ~= false
                                end,
                                callback = function()
                                    local curr = self.ai_helper.settings.unit_cat_speed ~= false
                                    self.ai_helper:saveSettings({ unit_cat_speed = not curr })
                                    if self.scanBookForUnits then self:scanBookForUnits() end
                                end
                            },
                            {
                                text = "Area (acre, hectare, m², sq ft...)",
                                checked_func = function()
                                    return self.ai_helper.settings.unit_cat_area ~= false
                                end,
                                callback = function()
                                    local curr = self.ai_helper.settings.unit_cat_area ~= false
                                    self.ai_helper:saveSettings({ unit_cat_area = not curr })
                                    if self.scanBookForUnits then self:scanBookForUnits() end
                                end
                            }
                        }
                    }
                },
                separator = true,
            },
            {
                text = self.loc:t("menu_ai_settings"),
                keep_menu_open = true,
                sub_item_table = {
                    {
                        text = self.loc:t("menu_primary_ai_model") or "Primary AI Model",
                        keep_menu_open = true,
                        sub_item_table_func = function() return self:getAIModelSelectionMenu("primary") end
                    },
                    {
                        text = self.loc:t("menu_secondary_ai_model") or "Secondary AI Model",
                        keep_menu_open = true,
                        sub_item_table_func = function() return self:getAIModelSelectionMenu("secondary") end,
                    },
                    {
                        text = self.loc:t("menu_reasoning_effort") or "AI Reasoning Effort",
                        keep_menu_open = true,
                        callback = function() self:showReasoningEffortSettings() end,
                        separator = true,
                    },
                    {
                        is_api_keys = true,
                        text = self.loc:t("menu_api_keys") or "API Keys & Providers", 
                        keep_menu_open = true,
                        sub_item_table_func = function() return self:getAPIKeysMenu() end,
                        separator = true,
                    },
                    {
                        text = self.loc:t("menu_view_config") or "View All Config Values", 
                        keep_menu_open = true,
                        callback = function() self:showConfigSummary() end,
                    },
                }
            },
            {
                text = self.loc:t("menu_language") or "Language",
                keep_menu_open = true,
                callback = function() self:showLanguageSelection() end,
            }
        }
    })

    table.insert(items, {
        text = self.loc:t("menu_maintenance") or "Maintenance",
        keep_menu_open = true,
        sub_item_table = {
            {
                text = self.loc:t("menu_clear_cache"),
                keep_menu_open = true,
                callback = function() self:clearCache() end,
            },
            {
                text = self.loc:t("menu_clear_logs") or "Clear Logs",
                keep_menu_open = true,
                callback = function() self:clearLogs() end,
            },
            {
                text = self.loc:t("menu_view_log") or "View Log",
                keep_menu_open = true,
                callback = function() self:viewLog() end,
            },
            {
                text = self.loc:t("menu_beta_channel") or "Beta Channel Settings",
                keep_menu_open = true,
                callback = function() self:showBetaChannelSettings() end,
            },
            {
                text = self.loc:t("updater_check") or "Check for Updates",
                keep_menu_open = true,
                callback = function()
                    local updater = require(plugin_path .. "xray_updater")
                    updater.checkForUpdates(self.loc, self.ai_helper.settings.beta_channel_enabled)
                end,
            },
        }
    })

    table.insert(items, {
        text = _t(self, "menu_about", "About X-Ray"),
        keep_menu_open = true,
        callback = function() self:showAbout() end,
    })

    self.current_xray_menu_table = items
    return items
end



function XRayPlugin:addToMainMenu(menu_items)
    menu_items.xray = {
        is_xray = true,
        text = _t(self, "menu_xray", "X-Ray"),

        sorting_hint = "tools",
        callback = function() self:showQuickXRayMenu() end,
        hold_callback = function() self:showFullXRayMenu() end,
        sub_item_table_func = function() return self:getSubMenuItems() end,
    }
end

-- Extracted functions are now loaded via mixins (xray_data, xray_ui, xray_fetch, xray_mentions)

function XRayPlugin:showUnitStyleCard()
    local Screen = require("device").screen
    local Font = require("ui/font")
    local Geom = require("ui/geometry")
    local Blitbuffer = require("ffi/blitbuffer")
    local UIManager = require("ui/uimanager")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local InputContainer = require("ui/widget/container/inputcontainer")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local TextWidget = require("ui/widget/textwidget")
    local Button = require("ui/widget/button")
    local MovableContainer = require("ui/widget/container/movablecontainer")
    local GestureRange = require("ui/gesturerange")
    local VerticalSpan = require("ui/widget/verticalspan")
    local WidgetContainer = require("ui/widget/container/widgetcontainer")
    local RenderText = require("ui/rendertext")
    local OverlapGroup = require("ui/widget/overlapgroup")
    local LineWidget = require("ui/widget/linewidget")
    local Widget = require("ui/widget/widget")

    local xray_theme = require(plugin_path .. "xray_theme")

    local function sc(val)
        return Screen:scaleBySize(val)
    end

    local sw = Screen:getWidth()
    local sh = Screen:getHeight()
    local dialog_w = math.min(sw - sc(20), sc(380))

    local fs = 20
    if G_reader_settings then
        fs = G_reader_settings:readSetting("cre_font_size") or 20
    end
    -- Clamp UI fonts to reasonable sizes based on reader settings
    local ui_font_size = math.max(14, math.min(fs, 24))
    local label_font_size = math.max(11, math.min(fs - 4, 18))
    local title_font_size = math.max(10, math.min(fs - 5, 15))

    local overlay
    local focused_row = 1
    local focused_col = 1
    local refresh

    local row_definitions = {}

    refresh = function()
        local settings = self.ai_helper.settings or {}
        local underline_style = settings.unit_underline_style or "wavy"
        local underline_thickness = tonumber(settings.unit_underline_thickness) or 2
        local underline_intensity = settings.unit_underline_intensity or "light"
        local tooltip_timeout = tonumber(settings.unit_tooltip_timeout) or 4

        local function saveSetting(key, val)
            self.ai_helper:saveSettings({ [key] = val })
            local is_visual = (key == "unit_underline_style" or key == "unit_underline_thickness" or key == "unit_underline_intensity" or key == "unit_tooltip_timeout")
            if not is_visual then
                if self.scanBookForUnits then self:scanBookForUnits() end
            else
                if self.ui and self.ui.view and self.ui.view.dialog then
                    UIManager:setDirty(self.ui.view.dialog, "ui")
                end
            end
            refresh()
        end

        row_definitions = {
            {
                key = "unit_underline_style",
                options = {
                    { text = self.loc:t("unit_underline_solid") or "Solid", value = "solid" },
                    { text = self.loc:t("unit_underline_wavy") or "Wavy", value = "wavy" }
                },
                current = underline_style,
            },
            {
                key = "unit_underline_style",
                options = {
                    { text = self.loc:t("unit_underline_dotted") or "Dotted", value = "dotted" },
                    { text = self.loc:t("unit_underline_dashed") or "Dashed", value = "dashed" }
                },
                current = underline_style,
            },
            {
                key = "unit_underline_style",
                options = {
                    { text = self.loc:t("unit_underline_double") or "Double", value = "double" },
                    { text = self.loc:t("unit_underline_invisible") or "Invisible", value = "invisible" }
                },
                current = underline_style,
            },
            {
                key = "unit_underline_thickness",
                options = {
                    { text = "1px", value = 1 },
                    { text = "2px", value = 2 },
                    { text = "3px", value = 3 }
                },
                current = underline_thickness,
            },
            {
                key = "unit_underline_intensity",
                options = {
                    { text = self.loc:t("unit_intensity_light") or "Light", value = "light" },
                    { text = self.loc:t("unit_intensity_medium") or "Medium", value = "medium" },
                    { text = self.loc:t("unit_intensity_dark") or "Dark", value = "dark" }
                },
                current = underline_intensity,
            },
            {
                key = "unit_tooltip_timeout",
                options = {
                    { text = "2s", value = 2 },
                    { text = "4s", value = 4 },
                    { text = "8s", value = 8 },
                    { text = self.loc:t("unit_timeout_never") or "Never", value = 0 }
                },
                current = tooltip_timeout,
            },
            {
                key = "close",
                options = {
                    { text = self.loc:t("close") or "Close", value = "close" }
                },
                current = nil,
            }
        }

        local num_rows = #row_definitions
        if focused_row > num_rows then focused_row = num_rows end
        if focused_row < 1 then focused_row = 1 end

        local cur_row_opts = row_definitions[focused_row].options
        if focused_col > #cur_row_opts then focused_col = #cur_row_opts end
        if focused_col < 1 then focused_col = 1 end

        local function option_row(row_idx)
            local rdef = row_definitions[row_idx]
            local options = rdef.options
            local current = rdef.current
            local key = rdef.key

            local row = { align = "center" }
            for col_i, opt in ipairs(options) do
                if col_i > 1 then
                    table.insert(row, WidgetContainer:new{ dimen = Geom:new{ w = sc(12), h = 1 } })
                end
                local value = opt.value
                local is_selected = (value == current)
                local is_focused = (row_idx == focused_row and col_i == focused_col)
                local dot_char = is_selected and "●" or "○"
                
                local frame = FrameContainer:new{
                    bordersize = is_focused and (xray_theme.border_focus or sc(3)) or (is_selected and (xray_theme.border_btn or sc(1)) or sc(1)),
                    radius = xray_theme.radius_btn,
                    padding = sc(6),
                    color = is_focused and (xray_theme.color_focus_border or Blitbuffer.COLOR_BLACK) or (is_selected and xray_theme.color_border or xray_theme.color_section_rule),
                    background = is_focused and (xray_theme.color_focus_bg or Blitbuffer.Color8(215)) or (is_selected and Blitbuffer.Color8(240) or xray_theme.color_bg),
                    HorizontalGroup:new{
                        align = "center",
                        TextWidget:new{ text = dot_char, face = Font:getFace("cfont", ui_font_size), bold = is_focused or is_selected },
                        WidgetContainer:new{ dimen = Geom:new{ w = sc(4), h = 1 } },
                        TextWidget:new{ text = opt.text, face = Font:getFace("cfont", ui_font_size), bold = is_focused or is_selected },
                    }
                }
                local item = InputContainer:new{ frame }
                item.ges_events = {
                    Tap = {
                        GestureRange:new{
                            ges = "tap",
                            range = function() return frame.dimen end
                        }
                    }
                }
                item.onTap = function()
                    focused_row = row_idx
                    focused_col = col_i
                    saveSetting(key, value)
                    return true
                end
                table.insert(row, item)
            end
            return HorizontalGroup:new(row)
        end

        local UnderlinePreview = Widget:extend{
            width = 0,
            height = 0,
            underline_style = underline_style,
            underline_thickness = underline_thickness,
            underline_color_val = nil,
            plugin = nil,
        }
        function UnderlinePreview:getSize()
            return Geom:new{ w = self.width, h = self.height }
        end
        function UnderlinePreview:paintTo(bb, x, y)
            local plugin = self.plugin
            if plugin and plugin._draw_underline then
                local grey = 150
                if underline_intensity == "light" then
                    grey = 200
                elseif underline_intensity == "dark" then
                    grey = 30
                end
                local Screen = require("device").screen
                local thickness = Screen:scaleBySize(self.underline_thickness)
                local box = { x = x, y = y, w = self.width, h = self.height }
                plugin._draw_underline(bb, box, self.underline_style, grey, thickness, self.underline_thickness, plugin.path)
            end
        end

        local preview_face = Font:getFace("cfont", ui_font_size + 2)
        local sample_text = TextWidget:new{
            text = "walked 2 miles today",
            face = preview_face,
            alignment = "center",
        }
        local sample_size = sample_text:getSize()
        local sample_w = (sample_size and sample_size.w or 200) + sc(20)
        local sample_h = sample_size and sample_size.h or 30

        local preview_line = UnderlinePreview:new{
            width = sample_w,
            height = sample_h + sc(12),
            underline_style = underline_style,
            underline_thickness = underline_thickness,
            plugin = self,
        }

        local popup_bubble = FrameContainer:new{
            padding = sc(4),
            padding_h = sc(12),
            bordersize = sc(1),
            color = Blitbuffer.COLOR_BLACK,
            background = Blitbuffer.COLOR_WHITE,
            radius = sc(2),
            TextWidget:new{
                text = "3.22 km",
                face = Font:getFace("cfont", ui_font_size),
                alignment = "center",
            }
        }

        local arrow_widget = self._PointerArrow and self._PointerArrow:new{
            point_down = true,
            width = sc(12),
            height = sc(6),
            color = Blitbuffer.COLOR_BLACK,
        }

        local preview_bubble_vg = VerticalGroup:new{
            align = "center",
            popup_bubble,
        }
        if arrow_widget then
            table.insert(preview_bubble_vg, arrow_widget)
        end

        local preview_content = VerticalGroup:new{
            align = "center",
            preview_bubble_vg,
            VerticalSpan:new{ width = sc(2) },
            sample_text,
            VerticalSpan:new{ width = sc(1) },
            preview_line,
        }

        local preview_panel = CenterContainer:new{
            dimen = Geom:new{ w = dialog_w - sc(28), h = sc(85) },
            FrameContainer:new{
                bordersize = xray_theme.border_preview,
                color = xray_theme.color_border,
                padding = sc(8),
                background = Blitbuffer.COLOR_WHITE,
                width = dialog_w - sc(28),
                CenterContainer:new{
                    dimen = Geom:new{ w = dialog_w - sc(44), h = sc(72) },
                    preview_content
                }
            }
        }

        local title_label = TextWidget:new{
            text = self.loc:t("unit_style_preview_title") or "STYLE PREVIEW",
            face = Font:getFace("cfont", ui_font_size - 1),
            bold = true,
            fgcolor = Blitbuffer.COLOR_BLACK,
        }

        local function label(str)
            return TextWidget:new{
                text = str,
                face = Font:getFace("cfont", ui_font_size - 2),
                bold = true,
                fgcolor = Blitbuffer.COLOR_BLACK,
            }
        end

        local function span()
            return VerticalSpan:new{ width = sc(6) }
        end

        local function divider()
            return LineWidget:new{
                dimen = Geom:new{ w = dialog_w - sc(28), h = xray_theme.border_line_h },
                background = xray_theme.color_section_rule,
            }
        end

        local style_row_1 = option_row(1)
        local style_row_2 = option_row(2)
        local style_row_3 = option_row(3)
        local thickness_row = option_row(4)
        local intensity_row = option_row(5)
        local timeout_row = option_row(6)

        local is_close_focused = (focused_row == 7)
        local close_btn = Button:new{
            text = self.loc:t("close") or "Close",
            face = Font:getFace("cfont", ui_font_size),
            bold = is_close_focused,
            width = dialog_w - sc(32),
            height = sc(42),
            bordersize = is_close_focused and (xray_theme.border_focus or sc(3)) or xray_theme.border_btn,
            color = is_close_focused and (xray_theme.color_focus_border or Blitbuffer.COLOR_BLACK) or xray_theme.color_border,
            background = is_close_focused and (xray_theme.color_focus_bg or Blitbuffer.Color8(215)) or nil,
            radius = xray_theme.radius_btn,
            callback = function()
                if overlay then overlay:onClose() end
            end
        }

        local card = FrameContainer:new{
            padding = sc(12),
            radius = xray_theme.radius_window,
            bordersize = sc(2),
            color = Blitbuffer.COLOR_BLACK,
            background = xray_theme.color_bg,
            width = dialog_w - sc(2),
            VerticalGroup:new{
                align = "left",
                title_label,
                span(),
                preview_panel,
                span(),
                label(self.loc:t("unit_underline_style_label") or "Underline Style"),
                style_row_1,
                WidgetContainer:new{ dimen = Geom:new{ w = 1, h = sc(4) } },
                style_row_2,
                WidgetContainer:new{ dimen = Geom:new{ w = 1, h = sc(4) } },
                style_row_3,
                span(),
                label(self.loc:t("unit_underline_thickness_label") or "Underline Thickness"),
                thickness_row,
                span(),
                label(self.loc:t("unit_underline_intensity_label") or "Underline Intensity"),
                intensity_row,
                span(),
                label(self.loc:t("unit_tooltip_timeout_label") or "Tooltip Timeout"),
                timeout_row,
                span(),
                divider(),
                span(),
                close_btn,
            }
        }

        local card_outer = FrameContainer:new{
            bordersize = sc(1),
            color = Blitbuffer.Color8(180),
            padding = 0,
            background = xray_theme.color_bg,
            radius = xray_theme.radius_window,
            width = dialog_w,
            card
        }

        local movable = MovableContainer:new{ card_outer }
        if self._styling_offset then
            movable:setMovedOffset(self._styling_offset)
        end

        local orig_handleEvent = movable.handleEvent
        movable.handleEvent = function(this, ev)
            local res = orig_handleEvent(this, ev)
            if ev.type == "Gesture" or ev.type == "Pan" or ev.type == "Hold" then
                self._styling_offset = this.moved_offset
            end
            return res
        end

        local main_center = CenterContainer:new{
            dimen = Geom:new{ w = sw, h = sh },
            movable
        }

        if overlay then
            overlay[1] = main_center
            UIManager:setDirty(overlay, "ui")
        else
            overlay = InputContainer:new{
                key_events = {
                    FocusUp = {
                        { "Up" },
                        { "PrevPage" },
                    },
                    FocusDown = {
                        { "Down" },
                        { "NextPage" },
                    },
                    FocusLeft = {
                        { "Left" },
                    },
                    FocusRight = {
                        { "Right" },
                    },
                    Select = {
                        { "Return" },
                        { "KP_Enter" },
                        { "Enter" },
                        { "Press" },
                        { "Select" },
                        { "Space" },
                    },
                    Close = {
                        { "Escape" },
                        { "Back" },
                        { "q" },
                        { "Q" },
                    },
                },
                main_center
            }

            if Device and Device.input and Device.input.group then
                if Device.input.group.Enter then table.insert(overlay.key_events.Select, { Device.input.group.Enter }) end
                if Device.input.group.Select then table.insert(overlay.key_events.Select, { Device.input.group.Select }) end
                if Device.input.group.Back then table.insert(overlay.key_events.Close, { Device.input.group.Back }) end
            end

            overlay.onFocusUp = function()
                if focused_row > 1 then
                    focused_row = focused_row - 1
                else
                    focused_row = num_rows
                end
                local opts = row_definitions[focused_row].options
                if focused_col > #opts then focused_col = #opts end
                refresh()
                return true
            end

            overlay.onFocusDown = function()
                if focused_row < num_rows then
                    focused_row = focused_row + 1
                else
                    focused_row = 1
                end
                local opts = row_definitions[focused_row].options
                if focused_col > #opts then focused_col = #opts end
                refresh()
                return true
            end

            overlay.onFocusLeft = function()
                local opts = row_definitions[focused_row].options
                if focused_col > 1 then
                    focused_col = focused_col - 1
                else
                    focused_col = #opts
                end
                refresh()
                return true
            end

            overlay.onFocusRight = function()
                local opts = row_definitions[focused_row].options
                if focused_col < #opts then
                    focused_col = focused_col + 1
                else
                    focused_col = 1
                end
                refresh()
                return true
            end

            overlay.onSelect = function()
                if focused_row <= 6 then
                    local rdef = row_definitions[focused_row]
                    local opt = rdef.options[focused_col]
                    if opt then
                        saveSetting(rdef.key, opt.value)
                    end
                else
                    overlay:onClose()
                end
                return true
            end

            function overlay:onClose()
                self._styling_offset = nil
                UIManager:close(overlay, "ui")
                return true
            end

            overlay.handleEvent = function(this, ev)
                if ev.type == "Key" or ev.type == "KeyPress" or ev.type == "KeyDown" then
                    local key = ev.key or ev.name or ev.sym
                    if key == "Return" or key == "KP_Enter" or key == "Enter" or key == "Select" or key == "Space" or key == "Press" then
                        return this:onSelect()
                    elseif key == "Up" or key == "PrevPage" or key == "PageUp" then
                        return this:onFocusUp()
                    elseif key == "Down" or key == "NextPage" or key == "PageDown" then
                        return this:onFocusDown()
                    elseif key == "Left" then
                        return this:onFocusLeft()
                    elseif key == "Right" then
                        return this:onFocusRight()
                    elseif key == "Escape" or key == "Back" or key == "q" or key == "Q" then
                        return this:onClose()
                    end
                end
                return InputContainer.handleEvent(this, ev)
            end

            UIManager:show(overlay, "ui")
        end
    end

    refresh()
end

function XRayPlugin:showUnitAutoScanCard()
    local XRaySettingsCard = require(plugin_path .. "xray_settings_card")
    local enabled_text = self.loc:t("unit_auto_scan_enabled") or "Enabled"
    local disabled_text = self.loc:t("unit_auto_scan_disabled") or "Disabled"
    XRaySettingsCard.show(self, {
        title = self.loc:t("unit_auto_scan_settings") or "Auto-Scan Settings",
        description = self.loc:t("unit_auto_scan_desc") or "Scan books for units automatically:",
        options = {
            { text = enabled_text, value = true },
            { text = disabled_text, value = false },
        },
        get_current_func = function()
            return self.ai_helper.settings.unit_auto_scan_enabled ~= false
        end,
        save_func = function(val)
            self.ai_helper:saveSettings({ unit_auto_scan_enabled = val })
        end,
        about_text = self.loc:t("unit_auto_scan_about") or "Scanning can take up to 15-20 seconds for large books. This only happens the first time the book is opened, and the results are saved for the future."
    })
end

function XRayPlugin:showUnitScanWrittenNumbersCard()
    local XRaySettingsCard = require(plugin_path .. "xray_settings_card")
    local enabled_text = self.loc:t("unit_scan_written_enabled") or "Enabled"
    local disabled_text = self.loc:t("unit_scan_written_disabled") or "Disabled"
    XRaySettingsCard.show(self, {
        title = self.loc:t("unit_scan_written_numbers_title") or "Scan Written Numbers",
        description = self.loc:t("unit_scan_written_numbers_desc") or "Scan for spelled-out numbers (e.g. 'five miles'):",
        options = {
            { text = enabled_text, value = true },
            { text = disabled_text, value = false },
        },
        get_current_func = function()
            local settings = self.ai_helper.settings
            if settings.unit_scan_written_numbers ~= nil then
                return settings.unit_scan_written_numbers == true
            end
            local xray_utils = require(plugin_path .. "xray_utils")
            return not xray_utils:isLowPowerForScan()
        end,
        save_func = function(val)
            self.ai_helper:saveSettings({ unit_scan_written_numbers = val })
            if self.scanBookForUnits then self:scanBookForUnits() end
        end,
        about_text = self.loc:t("unit_scan_written_numbers_about") or "Scanning written-out numbers (like 'five miles') requires a second full-text pass. Skipping this pass on lower-powered devices (Kindle, Kobo, PocketBook) provides a 4x to 5x scan speedup and prevents startup freezes. On faster platforms like Android or desktops, there is no noticeable slowdown."
    })
end

-- Resolves the exact touch menu path (e.g. "4.1.8.6") to an X-Ray submenu
local function findXRayMenuPath(self, target_key)
    if not self.ui or not self.ui.menu then return nil end
    local reader_menu = self.ui.menu
    if not reader_menu.tab_item_table then
        reader_menu:setUpdateItemTable()
    end
    local tab_item_table = reader_menu.tab_item_table
    if not tab_item_table then return nil end

    local function searchMenu(items, current_path)
        for idx, item in ipairs(items) do
            local path = current_path == "" and tostring(idx) or (current_path .. "." .. idx)
            if target_key == "unit_converter" and item.is_unit_converter then
                return path
            elseif target_key == "api_keys" and (item.is_api_keys or (item.text and item.text:find("API Keys"))) then
                return path
            end
            local submenu = item.sub_item_table
            if not submenu and type(item.sub_item_table_func) == "function" then
                submenu = item.sub_item_table_func()
            end
            if submenu then
                local found = searchMenu(submenu, path)
                if found then
                    return found
                end
            end
        end
        return nil
    end

    for tab_idx, tab_items in ipairs(tab_item_table) do
        for item_idx, item in ipairs(tab_items) do
            if item.id == "xray" then
                local submenu = item.sub_item_table
                if not submenu and type(item.sub_item_table_func) == "function" then
                    submenu = item.sub_item_table_func()
                end
                if submenu then
                    local sub_path = searchMenu(submenu, "")
                    if sub_path then
                        local path = string.format("%d.%d.%s", tab_idx, item_idx, sub_path)
                        self:log("XRayPlugin: findXRayMenuPath resolved path: " .. tostring(path))
                        return path
                    end
                end
            end
        end
    end
    self:log("XRayPlugin: findXRayMenuPath failed to resolve path for " .. tostring(target_key))
    return nil
end

function XRayPlugin:openReaderMenuToPath(target_key)
    local UIManager = require("ui/uimanager")
    UIManager:scheduleIn(0.1, function()
        if self.destroyed or not self.ui or not self.ui.document then return end
        if self.ui and self.ui.menu then
            if not self.ui.menu.menu_container then
                self.ui.menu:onShowMenu()
            end
            local touch_menu = self.ui.menu.menu_container and self.ui.menu.menu_container[1]
            if touch_menu then
                local path = findXRayMenuPath(self, target_key)
                if path then
                    touch_menu:openMenu(path, false)
                end
            end
        end
    end)
end

findUnitConverterMenuPath = function(self)
    return findXRayMenuPath(self, "unit_converter")
end

-- Shows the "New Feature" promotion card for the Unit Converter
function XRayPlugin:showUnitConverterNewFeatureCard()
    local Screen = require("device").screen
    local Font = require("ui/font")
    local Geom = require("ui/geometry")
    local Blitbuffer = require("ffi/blitbuffer")
    local UIManager = require("ui/uimanager")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local InputContainer = require("ui/widget/container/inputcontainer")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local TextWidget = require("ui/widget/textwidget")
    local Button = require("ui/widget/button")
    local GestureRange = require("ui/gesturerange")
    local VerticalSpan = require("ui/widget/verticalspan")
    local WidgetContainer = require("ui/widget/container/widgetcontainer")
    local MovableContainer = require("ui/widget/container/movablecontainer")
    local TextBoxWidget = require("ui/widget/textboxwidget")
    local LineWidget = require("ui/widget/linewidget")
    local xray_theme = require(plugin_path .. "xray_theme")

    local function sc(val)
        return Screen:scaleBySize(val)
    end

    local sw = Screen:getWidth()
    local sh = Screen:getHeight()
    local dialog_w = math.min(sw - sc(20), sc(460))

    local fs = 20
    if G_reader_settings then
        fs = G_reader_settings:readSetting("cre_font_size") or 20
    end
    local ui_font_size = math.max(14, math.min(fs, 24))
    local title_font_size = math.max(10, math.min(fs - 5, 15))

    local overlay
    local selected_action = "keep_enabled" -- Default selection

    local function span()
        return VerticalSpan:new{ width = xray_theme.gap }
    end

    -- 2. Main layout loop
    local function renderCard()
        if overlay then
            UIManager:close(overlay, "ui")
        end

        local title_label = TextWidget:new{
            text = (self.loc:t("new_feature") or "New Feature"):upper(),
            face = Font:getFace("infofont", title_font_size),
            fgcolor = xray_theme.color_label_dim or Blitbuffer.Color8(120),
        }

        local headline_label = TextWidget:new{
            text = self.loc:t("unit_conv_headline") or "Unit Converter",
            face = Font:getFace("cfont", ui_font_size + 2),
            bold = true,
            fgcolor = Blitbuffer.COLOR_BLACK,
        }

        local description_box = TextBoxWidget:new{
            text = self.loc:t("unit_conv_new_feature_desc") or "X-Ray now detects measurements (lengths, weights, temperature) in your books and highlights them with a subtle underline. Tap any highlighted unit to see its converted value in a popup tooltip.\n\nNote: A scan is required the first time a book is opened.",
            face = Font:getFace("cfont", ui_font_size),
            width = dialog_w - sc(32),
            alignment = self:isRTL() and "right" or "left",
        }

        -- Construct live preview widget elements
        local Widget = require("ui/widget/widget")
        local OverlapGroup = require("ui/widget/overlapgroup")
        local RenderText = require("ui/rendertext")

        local settings = self.ai_helper and self.ai_helper.settings or {}
        local underline_style = settings.unit_underline_style or "wavy"
        local underline_thickness = tonumber(settings.unit_underline_thickness) or 2
        local underline_intensity = settings.unit_underline_intensity or "light"

        local UnderlinePreview = Widget:extend{
            width = 0,
            height = 0,
            underline_style = underline_style,
            underline_thickness = underline_thickness,
            underline_color_val = nil,
            plugin = nil,
        }
        function UnderlinePreview:getSize()
            return Geom:new{ w = self.width, h = self.height }
        end
        function UnderlinePreview:paintTo(bb, x, y)
            local plugin = self.plugin
            if plugin and plugin._draw_underline then
                local grey = 150
                if underline_intensity == "light" then
                    grey = 200
                elseif underline_intensity == "dark" then
                    grey = 30
                end
                local thickness = Screen:scaleBySize(self.underline_thickness)
                local box = { x = x, y = y, w = self.width, h = self.height }
                plugin._draw_underline(bb, box, self.underline_style, grey, thickness, self.underline_thickness, plugin.path)
            end
        end

        local preview_face = Font:getFace("cfont", ui_font_size + 2)
        local sample_text = TextWidget:new{
            text = "walked 2 miles today",
            face = preview_face,
            alignment = "center",
        }
        local sample_size = sample_text:getSize()

        local underline_color_val
        if underline_intensity == "light" then
            underline_color_val = Blitbuffer.Color8(200)
        elseif underline_intensity == "dark" then
            underline_color_val = Blitbuffer.Color8(30)
        else
            underline_color_val = Blitbuffer.Color8(120)
        end

        local w_walked = RenderText:sizeUtf8Text(0, 9999, preview_face, "walked ", false, false).x
        local w_miles = RenderText:sizeUtf8Text(0, 9999, preview_face, "2 miles", false, false).x

        local underline_widget = UnderlinePreview:new{
            width = w_miles,
            height = sample_size.h,
            underline_style = underline_style,
            underline_thickness = underline_thickness,
            underline_color_val = underline_color_val,
            overlap_offset = { w_walked, 0 },
            plugin = self,
        }

        local preview_example = OverlapGroup:new{
            dimen = sample_size,
            sample_text,
            underline_widget,
        }

        local tooltip_text = "3.22 km"
        local tooltip_face = Font:getFace("cfont", fs)
        local pad_h = 28
        local pad_v = math.floor(fs * 0.55)
        local text_size = RenderText:sizeUtf8Text(0, 9999, tooltip_face, tooltip_text, false, false)
        local text_w = text_size.x
        local tooltip_max_w = dialog_w - sc(64)
        local popup_w = math.min(tooltip_max_w, text_w + pad_h * 2)

        local tb = TextWidget:new{
            text = tooltip_text,
            face = tooltip_face,
        }

        local border_sz = sc(2)
        local preview_tooltip = FrameContainer:new{
            background = Blitbuffer.COLOR_WHITE,
            bordersize = border_sz,
            color = Blitbuffer.COLOR_DARK_GRAY,
            radius = 0,
            padding_top = pad_v,
            padding_bottom = pad_v,
            padding_left = pad_h,
            padding_right = pad_h,
            width = popup_w,
            VerticalGroup:new{
                align = "center",
                tb
            }
        }

        local card_size = preview_tooltip:getSize()
        local card_h = card_size.h

        local arrow_w = sc(16)
        local arrow_h = sc(8)
        local _PointerArrow = self._PointerArrow
        local preview_arrow = _PointerArrow:new{
            width = arrow_w,
            height = arrow_h,
            direction = "down",
            apex_offset = arrow_w / 2,
            border_size = border_sz,
            border_color = Blitbuffer.COLOR_DARK_GRAY,
            fill_color = Blitbuffer.COLOR_WHITE,
        }
        preview_arrow.overlap_offset = { math.floor((popup_w - arrow_w) / 2), card_h - border_sz }

        local tooltip_with_arrow = OverlapGroup:new{
            dimen = Geom:new{ w = popup_w, h = card_h + arrow_h - border_sz },
            preview_tooltip,
            preview_arrow,
        }

        local preview_panel = FrameContainer:new{
            padding = sc(8),
            radius = xray_theme.radius_window,
            bordersize = xray_theme.border_preview,
            color = xray_theme.color_border,
            background = Blitbuffer.COLOR_WHITE,
            width = dialog_w - sc(32),
            VerticalGroup:new{
                align = "center",
                HorizontalGroup:new{
                    align = "center",
                    tooltip_with_arrow
                },
                VerticalSpan:new{ width = sc(2) },
                CenterContainer:new{
                    dimen = Geom:new{ w = dialog_w - sc(48), h = sample_size.h },
                    preview_example
                }
            }
        }

        local content_vg = VerticalGroup:new{
            align = "left",
            title_label,
            span(),
            headline_label,
            span(),
            description_box,
            span(),
            preview_panel,
            span(),
        }

        local choices = {
            { text = self.loc:t("unit_action_configure") or "Configure Settings...", value = "configure" },
            { text = self.loc:t("unit_action_keep") or "Keep Enabled (Default)", value = "keep_enabled" },
            { text = self.loc:t("unit_action_disable") or "Disable Feature", value = "disable" },
        }

        for idx, choice in ipairs(choices) do
            local is_selected = (choice.value == selected_action)
            local is_focused = (idx == focused_index)
            local dot_char = is_selected and "●" or "○"

            local row_content = HorizontalGroup:new{ align = "center" }
            if self:isRTL() then
                table.insert(row_content, TextBoxWidget:new{
                    text = choice.text,
                    face = Font:getFace("cfont", ui_font_size),
                    fgcolor = Blitbuffer.COLOR_BLACK,
                    width = dialog_w - sc(72),
                    alignment = "right",
                })
                table.insert(row_content, WidgetContainer:new{ dimen = Geom:new{ w = sc(6), h = 1 } })
                table.insert(row_content, TextWidget:new{
                    text = dot_char,
                    face = Font:getFace("cfont", ui_font_size),
                })
            else
                table.insert(row_content, TextWidget:new{
                    text = dot_char,
                    face = Font:getFace("cfont", ui_font_size),
                })
                table.insert(row_content, WidgetContainer:new{ dimen = Geom:new{ w = sc(6), h = 1 } })
                table.insert(row_content, TextBoxWidget:new{
                    text = choice.text,
                    face = Font:getFace("cfont", ui_font_size),
                    fgcolor = Blitbuffer.COLOR_BLACK,
                    width = dialog_w - sc(72),
                    alignment = "left",
                })
            end

            local frame = FrameContainer:new{
                bordersize = is_focused and (xray_theme.border_focus or sc(2)) or (is_selected and xray_theme.border_btn or sc(1)),
                radius = xray_theme.radius_btn,
                padding = sc(6),
                color = is_focused and (xray_theme.color_focus_border or Blitbuffer.COLOR_BLACK) or (is_selected and xray_theme.color_border or xray_theme.color_section_rule),
                background = is_focused and (xray_theme.color_focus_bg or Blitbuffer.Color8(230)) or xray_theme.color_bg,
                width = dialog_w - sc(32),
                row_content
            }

            local item = InputContainer:new{ frame }
            item.ges_events = {
                Tap = {
                    GestureRange:new{
                        ges = "tap",
                        range = function()
                            return Geom:new{
                                x = frame.dimen.x,
                                y = frame.dimen.y,
                                w = dialog_w - sc(32),
                                h = frame.dimen.h
                            }
                        end
                    }
                }
            }
            item.onTap = function()
                focused_index = idx
                selected_action = choice.value
                renderCard()
                return true
            end

            table.insert(content_vg, item)
            table.insert(content_vg, WidgetContainer:new{ dimen = Geom:new{ w = 1, h = sc(4) } })
        end

        table.insert(content_vg, span())
        table.insert(content_vg, LineWidget:new{
            dimen = Geom:new{ w = dialog_w - sc(32), h = sc(1) },
            background = xray_theme.color_section_rule,
        })
        table.insert(content_vg, span())

        local is_later_focused = (focused_index == 4)
        local is_confirm_focused = (focused_index == 5)

        -- Action Buttons (Confirm & Ask Later)
        local confirm_btn = Button:new{
            text = self.loc:t("confirm") or "Confirm",
            face = Font:getFace("cfont", ui_font_size),
            width = (dialog_w - sc(40)) / 2,
            height = sc(42),
            bordersize = is_confirm_focused and (xray_theme.border_focus or sc(2)) or xray_theme.border_btn,
            background = is_confirm_focused and (xray_theme.color_focus_bg or Blitbuffer.Color8(230)) or nil,
            radius = xray_theme.radius_btn,
            callback = function()
                -- Save prompted state
                self.ai_helper:saveSettings({ unit_new_feature_prompt_seen = true })
                if overlay then
                    UIManager:close(overlay, "ui")
                    overlay = nil
                end

                if selected_action == "configure" then
                    self.ai_helper:saveSettings({ unit_converter_enabled = true })
                    
                    UIManager:scheduleIn(0.1, function()
                        if self.destroyed or not self.ui or not self.ui.document then return end
                        if self.ui and self.ui.menu then
                            if not self.ui.menu.menu_container then
                                self.ui.menu:onShowMenu()
                            end
                            local touch_menu = self.ui.menu.menu_container and self.ui.menu.menu_container[1]
                            if touch_menu then
                                local path = findUnitConverterMenuPath(self)
                                if path then
                                    touch_menu:openMenu(path, false)
                                end
                            end
                        end
                    end)
                elseif selected_action == "keep_enabled" then
                    self.ai_helper:saveSettings({ unit_converter_enabled = true })
                    if self.scanBookForUnits then self:scanBookForUnits() end
                elseif selected_action == "disable" then
                    self.ai_helper:saveSettings({ unit_converter_enabled = false })
                    self:clearUnitUnderlines()
                end
            end
        }

        local later_btn = Button:new{
            text = self.loc:t("ask_later") or "Ask Later",
            face = Font:getFace("cfont", ui_font_size),
            width = (dialog_w - sc(40)) / 2,
            height = sc(42),
            bordersize = is_later_focused and (xray_theme.border_focus or sc(2)) or xray_theme.border_btn,
            background = is_later_focused and (xray_theme.color_focus_bg or Blitbuffer.Color8(230)) or nil,
            radius = xray_theme.radius_btn,
            callback = function()
                if overlay then
                    UIManager:close(overlay, "ui")
                    overlay = nil
                end
                if self.scanBookForUnits then self:scanBookForUnits() end
            end
        }

        local btn_row = HorizontalGroup:new{
            align = "center",
            later_btn,
            WidgetContainer:new{ dimen = Geom:new{ w = sc(8), h = 1 } },
            confirm_btn,
        }
        table.insert(content_vg, btn_row)

        local card = FrameContainer:new{
            padding = sc(12),
            radius = xray_theme.radius_window,
            bordersize = sc(2),
            color = Blitbuffer.COLOR_BLACK,
            background = xray_theme.color_bg,
            width = dialog_w - sc(2),
            content_vg
        }

        local card_outer = FrameContainer:new{
            bordersize = sc(1),
            color = Blitbuffer.Color8(180),
            padding = 0,
            background = xray_theme.color_bg,
            radius = xray_theme.radius_window,
            width = dialog_w,
            card
        }

        local main_center = CenterContainer:new{
            dimen = Geom:new{ w = sw, h = sh },
            MovableContainer:new{ card_outer }
        }

        if overlay then
            overlay[1] = main_center
            UIManager:setDirty(overlay, "ui")
        else
            overlay = InputContainer:new{
                key_events = {
                    FocusUp = {
                        { "Up" },
                        { "PrevPage" },
                    },
                    FocusDown = {
                        { "Down" },
                        { "NextPage" },
                    },
                    FocusLeft = {
                        { "Left" },
                    },
                    FocusRight = {
                        { "Right" },
                    },
                    Select = {
                        { "Return" },
                        { "KP_Enter" },
                        { "Enter" },
                        { "Press" },
                        { "Select" },
                        { "Space" },
                    },
                    Close = {
                        { "Escape" },
                        { "Back" },
                        { "q" },
                        { "Q" },
                    },
                },
                main_center
            }

            if Device and Device.input and Device.input.group then
                if Device.input.group.Enter then table.insert(overlay.key_events.Select, { Device.input.group.Enter }) end
                if Device.input.group.Select then table.insert(overlay.key_events.Select, { Device.input.group.Select }) end
                if Device.input.group.Back then table.insert(overlay.key_events.Close, { Device.input.group.Back }) end
            end

            overlay.onFocusUp = function()
                if focused_index > 1 then
                    focused_index = focused_index - 1
                else
                    focused_index = 5
                end
                renderCard()
                return true
            end

            overlay.onFocusDown = function()
                if focused_index < 5 then
                    focused_index = focused_index + 1
                else
                    focused_index = 1
                end
                renderCard()
                return true
            end

            overlay.onFocusLeft = function()
                if focused_index == 5 then
                    focused_index = 4
                    renderCard()
                end
                return true
            end

            overlay.onFocusRight = function()
                if focused_index == 4 then
                    focused_index = 5
                    renderCard()
                end
                return true
            end

            overlay.onSelect = function()
                if focused_index >= 1 and focused_index <= 3 then
                    selected_action = choices[focused_index].value
                    renderCard()
                elseif focused_index == 4 then
                    later_btn.callback()
                elseif focused_index == 5 then
                    confirm_btn.callback()
                end
                return true
            end

            overlay.onClose = function()
                if overlay then
                    UIManager:close(overlay, "ui")
                    overlay = nil
                end
                return true
            end

            overlay.handleEvent = function(this, ev)
                if ev.type == "Key" or ev.type == "KeyPress" or ev.type == "KeyDown" then
                    local key = ev.key or ev.name or ev.sym
                    if key == "Return" or key == "KP_Enter" or key == "Enter" or key == "Select" or key == "Space" or key == "Press" then
                        return this:onSelect()
                    elseif key == "Up" or key == "PrevPage" or key == "PageUp" then
                        return this:onFocusUp()
                    elseif key == "Down" or key == "NextPage" or key == "PageDown" then
                        return this:onFocusDown()
                    elseif key == "Left" then
                        return this:onFocusLeft()
                    elseif key == "Right" then
                        return this:onFocusRight()
                    elseif key == "Escape" or key == "Back" or key == "q" or key == "Q" then
                        return this:onClose()
                    end
                end
                return InputContainer.handleEvent(this, ev)
            end

            UIManager:show(overlay, "ui")
        end
    end

    renderCard()
end

-- --- Book Type Detection Engine ---

function XRayPlugin:detectBookTypeHeuristic()
    local book_path = self.ui and self.ui.document and self.ui.document.file
    if not book_path then return "unknown", false end
    
    local ext = book_path:match("%.([^%.]+)$")
    if ext then
        ext = ext:lower()
        if ext == "cbz" or ext == "cbr" or ext == "cb7" then
            return "manga", true -- archive format for comics/manga: highly confident
        end
    end

    local props = self.ui.document:getProps() or {}
    local subjects = props.subject or props.Subject or ""
    local title = (props.title or ""):lower()
    local filename = (book_path:match("([^/\\]+)$") or ""):lower()

    local manga_kw = { "manga", "graphic novel", "comic", "omnibus", "vol%.", "chapter" }
    local poetry_kw = { "poetry", "poems", "verse", "anthology" }
    local cookbook_kw = { "cookbook", "cook book", "recipe", "cooking" }
    local textbook_kw = { "textbook", "text book", "academic", "manual" }
    local travel_kw = { "travel guide", "lonely planet", "rough guide" }
    local fiction_kw = { "fiction", "novel", "fantasy", "thriller", "mystery", "romance",
                         "horror", "science fiction", "sci%-fi", "literary", "adventure",
                         "short stor", "young adult", "ya fiction" }
    local nonfiction_kw = { "nonfiction", "non%-fiction", "history", "biography", "memoir",
                            "autobiography", "science", "self%-help", "psychology", "economics",
                            "philosophy", "true crime", "politics", "essay" }

    local function match_keywords(str, kw_list)
        if not str or str == "" then return false end
        str = str:lower()
        for _, kw in ipairs(kw_list) do
            if str:find(kw) then return true end
        end
        return false
    end

    -- 1. Niche checks
    if match_keywords(subjects, manga_kw) then return "manga", true end
    if match_keywords(title, manga_kw) or match_keywords(filename, manga_kw) then return "manga", false end

    if match_keywords(subjects, poetry_kw) then return "poetry", true end
    if match_keywords(title, poetry_kw) or match_keywords(filename, poetry_kw) then return "poetry", false end

    if match_keywords(subjects, cookbook_kw) then return "cookbook", true end
    if match_keywords(title, cookbook_kw) or match_keywords(filename, cookbook_kw) then return "cookbook", false end

    if match_keywords(subjects, textbook_kw) then return "textbook", true end
    if match_keywords(title, textbook_kw) or match_keywords(filename, textbook_kw) then return "textbook", false end

    if match_keywords(subjects, travel_kw) then return "travel", true end
    if match_keywords(title, travel_kw) or match_keywords(filename, travel_kw) then return "travel", false end

    -- 2. Fiction / Non-Fiction positive checks
    if match_keywords(subjects, fiction_kw) then return "prose_fiction", true end
    if match_keywords(title, fiction_kw) or match_keywords(filename, fiction_kw) then return "prose_fiction", false end

    if match_keywords(subjects, nonfiction_kw) then return "prose_nonfiction", true end
    if match_keywords(title, nonfiction_kw) or match_keywords(filename, nonfiction_kw) then return "prose_nonfiction", false end

    -- 3. File extension fallback
    if ext then
        if ext == "epub" or ext == "mobi" or ext == "azw" or ext == "azw3" or ext == "fb2" or ext == "txt" then
            return "prose_fiction", false -- default to prose fiction (low confidence guess)
        end
    end

    return "unknown", false
end

function XRayPlugin:getEffectiveBookType()
    local cached = self.book_data or {}
    if cached.book_type_label_override and cached.book_type_label_override ~= "auto" then
        return cached.book_type_label_override
    end
    if cached.book_type_label and cached.book_type_label ~= "" then
        return cached.book_type_label
    end
    local heur = self:detectBookTypeHeuristic()
    if heur and heur ~= "unknown" then
        return heur
    end
    return "unknown"
end

function XRayPlugin:triggerBookTypeDetection()
    if self.destroyed or not self.ui or not self.ui.document then return true end
    local doc_file = self.ui.document.file
    if not doc_file then return true end

    if not self.book_data then
        self.book_data = {}
    end
    local cached = self.book_data

    local function newBookTypeResultFile()
        local DataStorage = require("datastorage")
        return string.format(
            "%s/xray/book_type_detect_res_%d_%d.json",
            DataStorage:getDataDir(),
            os.time(),
            math.random(1000, 9999)
        )
    end

    -- Check if we already have a unit cache first to avoid scans
    local has_unit_cache = false
    if self.loadUnitCache then
        has_unit_cache = self:loadUnitCache()
    end

    local function checkAndTriggerScan()
        if has_unit_cache then
            -- Just apply underlines, do not rescan
            if self.applyUnitUnderlines then self:applyUnitUnderlines() end
        else
            -- Check if current type is disabled before scanning
            local settings = self.ai_helper and self.ai_helper.settings or {}
            local disabled_types = settings.unit_disabled_book_types or { "manga", "graphic_novel", "children", "poetry" }
            local book_type = self:getEffectiveBookType()
            local is_disabled = false
            for _, t in ipairs(disabled_types) do
                if t == book_type then
                    is_disabled = true
                    break
                end
            end
            if is_disabled then
                if self.clearUnitUnderlines then self:clearUnitUnderlines() end
            else
                if self.scanBookForUnits then self:scanBookForUnits() end
            end
        end
    end

    if cached.book_type_label and cached.book_type_label ~= "" then
        checkAndTriggerScan()
        -- If the cached label was not detected by AI, check if we should refine it via AI background process
        if not cached.book_type_detected_by_ai and self.ai_helper:hasApiKey() then
            -- Trigger AI in background to refine low-confidence or format-fallback guesses
            local result_file = newBookTypeResultFile()
            local props = (self.ui and self.ui.document and self.ui.document.getProps and self.ui.document:getProps()) or {}
            local title = props.title or "Unknown"
            local author = props.authors or "Unknown"
            local series = props.series or props.Series or "None"
            local description = props.subject or props.Subject or "None"
            local pid = self.ai_helper:detectBookTypeAsync(title, author, series, description, result_file)
            if pid then
                local function pollResult()
                    if self.destroyed or not self.ui or not self.ui.document then return end
                    local res = self.ai_helper:checkAsyncResult(result_file, pid)
                    if res == nil then
                        UIManager:scheduleIn(1, pollResult)
                    elseif type(res) == "table" and res.book_type_label then
                        cached.book_type_label = res.book_type_label
                        cached.book_type_detected_by_ai = true
                        if self.cache_manager and doc_file then
                            self.cache_manager:asyncSaveCache(doc_file, cached)
                        end
                    end
                end
                UIManager:scheduleIn(1, pollResult)
            end
        end
        return true
    end

    -- Run Layer 1 & 2 heuristic
    local heur, is_confident = self:detectBookTypeHeuristic()
    if heur ~= "unknown" then
        cached.book_type_label = heur
        if is_confident then
            cached.book_type_detected_by_ai = false -- high confidence heuristic, no AI needed
            if self.cache_manager and doc_file then
                self.cache_manager:asyncSaveCache(doc_file, cached)
            end
            checkAndTriggerScan()
            return true
        else
            -- Low confidence heuristic, we save it as a starting point and scan
            cached.book_type_detected_by_ai = false
            if self.cache_manager and doc_file then
                self.cache_manager:asyncSaveCache(doc_file, cached)
            end
            checkAndTriggerScan()
            
            -- Run Layer 3 AI background refinement since confidence is low
            if not self.ai_helper:hasApiKey() then
                return true
            end
            self:log("XRayPlugin: Starting Layer 3 AI book type refinement in background...")
            local result_file = newBookTypeResultFile()
            local props = (self.ui and self.ui.document and self.ui.document.getProps and self.ui.document:getProps()) or {}
            local title = props.title or "Unknown"
            local author = props.authors or "Unknown"
            local series = props.series or props.Series or "None"
            local description = props.subject or props.Subject or "None"
            local pid = self.ai_helper:detectBookTypeAsync(title, author, series, description, result_file)
            if pid then
                local function pollResult()
                    if self.destroyed or not self.ui or not self.ui.document then return end
                    local res = self.ai_helper:checkAsyncResult(result_file, pid)
                    if res == nil then
                        UIManager:scheduleIn(1, pollResult)
                    elseif type(res) == "table" and res.book_type_label then
                        self:log("XRayPlugin: Book type AI refinement complete! Result: " .. tostring(res.book_type_label))
                        cached.book_type_label = res.book_type_label
                        cached.book_type_detected_by_ai = true
                        if self.cache_manager and doc_file then
                            self.cache_manager:asyncSaveCache(doc_file, cached)
                        end
                    end
                end
                UIManager:scheduleIn(1, pollResult)
            end
            return true
        end
    end

    -- Run Layer 3 LLM classification directly if API keys exist and heuristic was unknown
    if not self.ai_helper:hasApiKey() then
        checkAndTriggerScan()
        return true
    end

    self:log("XRayPlugin: Starting Layer 3 AI book type detection in background...")
    local result_file = newBookTypeResultFile()
    
    local props = (self.ui and self.ui.document and self.ui.document.getProps and self.ui.document:getProps()) or {}
    local title = props.title or "Unknown"
    local author = props.authors or "Unknown"
    local series = props.series or props.Series or "None"
    local description = props.subject or props.Subject or "None"

    local pid, err_c, err_m = self.ai_helper:detectBookTypeAsync(title, author, series, description, result_file)
    if not pid then
        self:log("XRayPlugin: Book type AI detection trigger failed: " .. tostring(err_m))
        checkAndTriggerScan()
        return true
    end

    local function pollResult()
        if self.destroyed or not self.ui or not self.ui.document then return end
        local res = self.ai_helper:checkAsyncResult(result_file, pid)
        if res == nil then
            UIManager:scheduleIn(1, pollResult)
        elseif type(res) == "table" and res.book_type_label then
            self:log("XRayPlugin: Book type AI detection complete! Result: " .. tostring(res.book_type_label))
            cached.book_type_label = res.book_type_label
            cached.book_type_detected_by_ai = true
            if self.cache_manager and doc_file then
                self.cache_manager:asyncSaveCache(doc_file, cached)
            end
            -- Check scan triggers again now that AI classification finished
            local has_unit_cache_now = false
            if self.loadUnitCache then
                has_unit_cache_now = self:loadUnitCache()
            end
            if not has_unit_cache_now then
                local settings = self.ai_helper and self.ai_helper.settings or {}
                local disabled_types = settings.unit_disabled_book_types or { "manga", "graphic_novel", "children", "poetry" }
                local book_type = self:getEffectiveBookType()
                local is_disabled = false
                for _, t in ipairs(disabled_types) do
                    if t == book_type then
                        is_disabled = true
                        break
                    end
                end
                if is_disabled then
                    if self.clearUnitUnderlines then self:clearUnitUnderlines() end
                else
                    if self.scanBookForUnits then self:scanBookForUnits() end
                end
            else
                if self.applyUnitUnderlines then self:applyUnitUnderlines() end
            end
        else
            self:log("XRayPlugin: Book type AI detection returned invalid or empty result: " .. tostring(res))
            checkAndTriggerScan()
        end
    end
    UIManager:scheduleIn(1, pollResult)
    return true
end

-- --- Book Type Filter Settings Card ---

-- --- Book Type Filter Dynamic Sub-Menus ---

function XRayPlugin:handleBookTypeOverride(val)
    if self.destroyed or not self.ui or not self.ui.document then return end
    local doc_file = self.ui.document.file
    if not doc_file then return end

    if not self.book_data then
        self.book_data = {}
    end
    self.book_data.book_type_label_override = val
    if self.cache_manager then
        self.cache_manager:asyncSaveCache(doc_file, self.book_data)
    end

    local cache_loaded = false
    if self.loadUnitCache then
        cache_loaded = self:loadUnitCache()
    end

    local settings = self.ai_helper and self.ai_helper.settings or {}
    local disabled_types = settings.unit_disabled_book_types or { "manga", "graphic_novel", "children", "poetry" }
    local is_disabled = false
    local book_type = self:getEffectiveBookType()
    for _, t in ipairs(disabled_types) do
        if t == book_type then
            is_disabled = true
            break
        end
    end

    if is_disabled then
        if self.clearUnitUnderlines then self:clearUnitUnderlines() end
    elseif not cache_loaded then
        self:closeAllMenus()
        if self.scanBookForUnits then self:scanBookForUnits() end
    else
        if self.applyUnitUnderlines then self:applyUnitUnderlines() end
    end
end

function XRayPlugin:showBookTypeOverrideCard(refresh_parent)
    local XRaySettingsCard = require(plugin_path .. "xray_settings_card")
    local book_types = {
        { key = "prose_fiction", text = self.loc:t("unit_book_type_prose_fiction") or "Fiction (Novels, Stories)" },
        { key = "prose_nonfiction", text = self.loc:t("unit_book_type_prose_nonfiction") or "Non-Fiction (History, Science, etc.)" },
        { key = "manga", text = self.loc:t("unit_book_type_manga") or "Manga" },
        { key = "graphic_novel", text = self.loc:t("unit_book_type_graphic_novel") or "Graphic Novels & Comics" },
        { key = "children", text = self.loc:t("unit_book_type_children") or "Children's Books" },
        { key = "poetry", text = self.loc:t("unit_book_type_poetry") or "Poetry & Verse" },
        { key = "cookbook", text = self.loc:t("unit_book_type_cookbook") or "Cookbooks & Recipes" },
        { key = "textbook", text = self.loc:t("unit_book_type_textbook") or "Textbooks & Academic" },
        { key = "travel", text = self.loc:t("unit_book_type_travel") or "Travel Guides" },
        { key = "unknown", text = self.loc:t("unit_book_type_unknown") or "Unknown/Other" },
    }

    local override_opts = {
        { text = self.loc:t("unit_book_type_auto") or "Auto-detect", value = "auto" }
    }
    for _, bt in ipairs(book_types) do
        table.insert(override_opts, { text = bt.text, value = bt.key })
    end

    XRaySettingsCard.show(self, {
        title = self.loc:t("unit_book_type_override") or "Override for this book",
        options = override_opts,
        get_current_func = function()
            local cached = self.book_data or {}
            return cached.book_type_label_override or "auto"
        end,
        save_func = function(val)
            self:handleBookTypeOverride(val)
            if refresh_parent then refresh_parent() end
        end,
    })
end

function XRayPlugin:getBookTypeFilterMenu()
    local book_types = {
        { key = "prose_fiction", text = self.loc:t("unit_book_type_prose_fiction") or "Fiction (Novels, Stories)" },
        { key = "prose_nonfiction", text = self.loc:t("unit_book_type_prose_nonfiction") or "Non-Fiction (History, Science, etc.)" },
        { key = "manga", text = self.loc:t("unit_book_type_manga") or "Manga" },
        { key = "graphic_novel", text = self.loc:t("unit_book_type_graphic_novel") or "Graphic Novels & Comics" },
        { key = "children", text = self.loc:t("unit_book_type_children") or "Children's Books" },
        { key = "poetry", text = self.loc:t("unit_book_type_poetry") or "Poetry & Verse" },
        { key = "cookbook", text = self.loc:t("unit_book_type_cookbook") or "Cookbooks & Recipes" },
        { key = "textbook", text = self.loc:t("unit_book_type_textbook") or "Textbooks & Academic" },
        { key = "travel", text = self.loc:t("unit_book_type_travel") or "Travel Guides" },
        { key = "unknown", text = self.loc:t("unit_book_type_unknown") or "Unknown/Other" },
    }

    local function getDetectedStr()
        local cached = self.book_data or {}
        local raw = cached.book_type_label
        local via = "AI"
        if not raw or raw == "" then
            raw = self:detectBookTypeHeuristic()
            via = "Heuristic"
        end
        local label = "Unknown/Other"
        for _, bt in ipairs(book_types) do
            if bt.key == raw then label = bt.text; break end
        end
        -- Strip parenthetical text to prevent truncation in native menus
        label = label:gsub("%s*%b()", "")
        return string.format("%s (%s)", label, via)
    end

    local menu = {
        {
            text = (self.loc:t("unit_book_type_detected") or "Detected Book Type") .. ": " .. getDetectedStr(),
            enabled = false,
        },
        {
            text = self.loc:t("unit_book_type_override") or "Override for this book",
            keep_menu_open = true,
            callback = function()
                self:showBookTypeOverrideCard()
            end
        },
        {
            text = self.loc:t("unit_book_type_manage") or "Manage Enabled Types",
            keep_menu_open = true,
            sub_item_table_func = function()
                local opts = {}
                for _, bt in ipairs(book_types) do
                    table.insert(opts, {
                        text = bt.text,
                        checked_func = function()
                            local disabled = self.ai_helper.settings.unit_disabled_book_types or { "manga", "graphic_novel", "children", "poetry" }
                            local disabled_map = {}
                            for _, k in ipairs(disabled) do disabled_map[k] = true end
                            return not disabled_map[bt.key]
                        end,
                        callback = function()
                            local disabled = self.ai_helper.settings.unit_disabled_book_types or { "manga", "graphic_novel", "children", "poetry" }
                            local new_disabled = {}
                            local found = false
                            for _, k in ipairs(disabled) do
                                if k == bt.key then
                                    found = true
                                else
                                    table.insert(new_disabled, k)
                                end
                            end
                            if not found then
                                table.insert(new_disabled, bt.key)
                            end
                            self.ai_helper:saveSettings({ unit_disabled_book_types = new_disabled })

                            local cache_loaded = false
                            if self.loadUnitCache then
                                cache_loaded = self:loadUnitCache()
                            end

                            local is_disabled = false
                            local book_type = self:getEffectiveBookType()
                            for _, t in ipairs(new_disabled) do
                                if t == book_type then
                                    is_disabled = true
                                    break
                                end
                            end

                            if is_disabled then
                                if self.clearUnitUnderlines then self:clearUnitUnderlines() end
                            elseif not cache_loaded then
                                self:closeAllMenus()
                                if self.scanBookForUnits then self:scanBookForUnits() end
                            else
                                if self.applyUnitUnderlines then self:applyUnitUnderlines() end
                            end
                        end
                    })
                end
                return opts
            end
        }
    }
    return menu
end

-- Extracted functions are now loaded via mixins (xray_data, xray_ui, xray_fetch, xray_mentions)

return XRayPlugin
