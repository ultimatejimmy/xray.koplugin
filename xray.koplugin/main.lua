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
    self.auto_fetch_enabled = not (self.ai_helper.settings and
        self.ai_helper.settings.auto_fetch_on_chapter == false)

    -- Data tables initialization
    self.characters = {}
    self.locations = {}
    self.timeline = {}
    self.historical_figures = {}
    self.terms = {}
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
    
    self:log("XRayPlugin: Initialized with language: " .. self.loc:getLanguage())
    self:onDispatcherRegisterActions()
    
    if self.ui then
        self.ui:registerKeyEvents({
            ShowXRayMenu = {
                { "Alt", "X" },
                event = "ShowXRayMenu",
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
    self:log("XRayPlugin: destroy called, marking as destroyed")
    self.destroyed = true
    
    if self.ai_helper then
        self.ai_helper:cancelAsyncChild()
    end
    
    if self.active_mention_scan and self.active_mention_scan.cancel_handle then
        self.active_mention_scan.cancel_handle:cancel()
        self.active_mention_scan = nil
    end

    self:closeAllMenus()
    
    if WidgetContainer.destroy then
        WidgetContainer.destroy(self)
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
            local text = popup and (popup.word or popup.text or popup.selection_text)
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
            
            if text then
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

function XRayPlugin:onReaderReady()
    self:autoLoadCache()
    -- Reset per-session chapter fetch tracking
    self.last_auto_chapter = nil
    self.last_bg_fetch_page = nil
    self.chapters_fetched = {}
    self.bg_fetch_pending = false

    -- Initial unit scanner run
    UIManager:scheduleIn(1.5, function()
        if self.destroyed then return end
        if self.mountUnderlineOverlay then self:mountUnderlineOverlay() end
        if self.mountTapHandler then self:mountTapHandler() end
        if self.scanBookForUnits then
            self:scanBookForUnits()
        end
    end)

    -- Initialize language based on logic (auto, book, or manual)
    self:applyLanguageLogic()
    
    -- Suggest switching to book language if appropriate
    UIManager:scheduleIn(5, function()
        if self.destroyed then return end
        self:checkBookLanguageMatch()
    end)
    
    -- Weekly silent update check
    UIManager:scheduleIn(10, function()
        if self.destroyed then return end
        self:checkWeeklyUpdate()
    end)

    -- Check series context prompt after ~15 seconds
    UIManager:scheduleIn(15, function()
        if self.destroyed then return end
        self:checkSeriesContext()
    end)

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
end


function XRayPlugin:onNetworkConnected()
    self:log("XRayPlugin: onNetworkConnected fired. Scheduling series context check in 2 seconds.")
    UIManager:scheduleIn(2, function()
        if self.destroyed then return end
        self:checkSeriesContext()
    end)
end

function XRayPlugin:onPageUpdate(pageno)
    self.last_pageno = pageno

    if self.pending_return_banner then
        local p = self.pending_return_banner
        self.pending_return_banner = nil
        UIManager:scheduleIn(0.3, function()
            if self.destroyed then return end
            self:showReturnBanner(p.return_page, p.entity, p.mentions, self.last_pageno)
        end)
    elseif not self.is_programmatic_navigation then
        if self.return_banner then
            self:closeAllMenus()
        end
    end
    if not self.auto_fetch_enabled then return end
    
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
                local toc = self.ui.document:getToc()
                if toc and #toc > 0 then
                    for _, entry in ipairs(toc) do
                        if entry.page and entry.page <= pageno then
                            chapter_title = entry.title
                            break
                        end
                    end
                end
                chapter_title = chapter_title or ("Page " .. tostring(pageno))

                if not (self.bg_fetch_pending or self.bg_fetch_active) then
                    self.bg_fetch_pending = true
                    UIManager:scheduleIn(2, function()
                        if self.destroyed then return end
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
        local toc = self.ui.document:getToc()
        if toc and #toc > 0 then
            for _, entry in ipairs(toc) do
                if entry.page and entry.page <= pageno then
                    chapter_title = entry.title
                else
                    break
                end
            end
        end
        chapter_title = chapter_title or ("Page " .. tostring(pageno))

        UIManager:scheduleIn(2, function()
            if self.destroyed then return end
            self.bg_fetch_pending = false
            self:triggerBackgroundMergeFetch(chapter_title)
        end)
        return
    end

    -- 2. Standard chapter-based mode checks (requires TOC)
    -- Resolve current chapter title from TOC
    local toc = self.ui.document:getToc()
    if not toc or #toc == 0 then
        return
    end

    local chapter_title = nil
    local chapter_page = nil
    for _, entry in ipairs(toc) do
        if entry.page and entry.page <= pageno then
            chapter_title = entry.title
            chapter_page = entry.page
        else
            break
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
        if self.destroyed then return end
        self.bg_fetch_pending = false
        self:triggerBackgroundMergeFetch(chapter_title)
    end)
end

function XRayPlugin:triggerBackgroundMergeFetch(chapter_title)
    if self.bg_fetch_active then return end
    if not self.ui or not self.ui.document then return end

    -- SILENT NETWORK CHECK: use isOnline() instead of runWhenOnline to avoid "white box" connecting dialogs
    local NetworkMgr = require("ui/network/manager")
    if NetworkMgr:isConnected() and NetworkMgr:isOnline() then
        -- Safety Check: Ensure API keys are configured before background activity
        if not self.ai_helper:hasApiKey() then
            return
        end

        -- Cooldown check to prevent API spamming
        local cooldown = self.ai_helper.settings and self.ai_helper.settings.auto_fetch_cooldown or 300
        local now = os.time()
        if self.last_bg_fetch_time and (now - self.last_bg_fetch_time) < cooldown then
            return
        end
        self.last_bg_fetch_time = now

        local current_page = self.ui:getCurrentPage()
        local total_pages = self.ui.document:getPageCount()
        if not total_pages or total_pages == 0 then return end
        local reading_percent = math.floor((current_page / total_pages) * 100)
        
        local spoiler_setting = self.ai_helper.settings and self.ai_helper.settings.spoiler_setting or "spoiler_free"
        if spoiler_setting == "full_book" then
            reading_percent = 100
        end
        
        local last_fetch_page = self.book_data and self.book_data.last_fetch_page
        
        local is_update = true
        if not self.timeline or #self.timeline == 0 then
            is_update = false
            self:log("XRayPlugin: Cache is empty. Switching to normal fetch instead of merge.")
        else
            self:log("XRayPlugin: Auto-merge fetch for chapter: " .. tostring(chapter_title))
        end
        
        self.fetch_attempts = self.fetch_attempts or {}
        self.fetch_attempts[chapter_title] = (self.fetch_attempts[chapter_title] or 0) + 1
        self:continueWithFetch(reading_percent, is_update, last_fetch_page, true) -- is_silent=true
    else
        -- Silently skip if offline
    end
end

function XRayPlugin:onDispatcherRegisterActions()
    local ok, Dispatcher = pcall(require, "dispatcher")
    if not ok or not Dispatcher then return end
    
    pcall(function()
        Dispatcher:registerAction("xray_quick_menu", {
            category = "none",
            event = "ShowXRayQuickMenu",
            title = _t(self, "quick_menu_title", "X-Ray Quick Menu"),
            general = true,
            separator = true,
        })
        Dispatcher:registerAction("xray_characters", {
            category = "none",
            event = "ShowXRayCharacters",
            title = _t(self, "menu_characters", "Characters"),
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

        -- Stage 2: Restore Sort Order (Deferred 500ms)
        UIManager:scheduleIn(500, function()
            if self.destroyed then return end
            if not self.ui or not self.ui.document then return end
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
                if self.ui and self.ui.dictionary and self.ui.dictionary.dict_window then
                    -- Trigger dictionary close safely
                    pcall(function()
                        self.ui.dictionary.dict_window:onClose()
                    end)
                end
                self:log("XRayPlugin: Stage 3 - Repairing pages and deduplicating")
                local toc = self.ui.document:getToc()
                self:assignTimelinePages(self.timeline, toc, false)
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
        UIManager:scheduleIn(200, function()
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
                        callback = function() self:showDescriptionLengthSettings() end,
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
                        text = self.loc:t("unit_conv_direction") or "Conversion Direction",
                        keep_menu_open = true,
                        sub_item_table = {
                            {
                                text = self.loc:t("unit_conv_direction_auto") or "Auto (Follow Device)",
                                checked_func = function()
                                    return self.ai_helper.settings.unit_conversion_direction == "auto" or self.ai_helper.settings.unit_conversion_direction == nil
                                end,
                                callback = function()
                                    self.ai_helper:saveSettings({ unit_conversion_direction = "auto" })
                                    if self.scanBookForUnits then self:scanBookForUnits() end
                                end
                            },
                            {
                                text = self.loc:t("unit_conv_direction_metric") or "To Metric",
                                checked_func = function()
                                    return self.ai_helper.settings.unit_conversion_direction == "to_metric"
                                end,
                                callback = function()
                                    self.ai_helper:saveSettings({ unit_conversion_direction = "to_metric" })
                                    if self.scanBookForUnits then self:scanBookForUnits() end
                                end
                            },
                            {
                                text = self.loc:t("unit_conv_direction_imperial") or "To Imperial",
                                checked_func = function()
                                    return self.ai_helper.settings.unit_conversion_direction == "to_imperial"
                                end,
                                callback = function()
                                    self.ai_helper:saveSettings({ unit_conversion_direction = "to_imperial" })
                                    if self.scanBookForUnits then self:scanBookForUnits() end
                                end
                            }
                        }
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
                    },
                    {
                        text = self.loc:t("unit_conv_style_settings") or "Style & Underline Settings",
                        keep_menu_open = true,
                        callback = function()
                            self:showUnitStyleCard()
                        end
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
    local CheckButton = require("ui/widget/checkbutton")
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
    local refresh

    refresh = function()
        if overlay then
            UIManager:close(overlay, "ui")
        end

        local settings = self.ai_helper.settings or {}
        local underline_style = settings.unit_underline_style or "invisible"
        local underline_thickness = tonumber(settings.unit_underline_thickness) or 2
        local underline_intensity = settings.unit_underline_intensity or "medium"
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

        local function option_row(options, current, key)
            local row = { align = "center" }
            for i, opt in ipairs(options) do
                if i > 1 then
                    table.insert(row, WidgetContainer:new{ dimen = Geom:new{ w = sc(12), h = 1 } })
                end
                local value = opt.value
                local is_selected = (value == current)
                local dot_char = is_selected and "●" or "○"
                
                local frame = FrameContainer:new{
                    bordersize = is_selected and xray_theme.border_btn or sc(1),
                    radius = xray_theme.radius_btn,
                    padding = sc(6),
                    color = is_selected and xray_theme.color_border or xray_theme.color_section_rule,
                    background = xray_theme.color_bg,
                    HorizontalGroup:new{
                        align = "center",
                        TextWidget:new{ text = dot_char, face = Font:getFace("cfont", ui_font_size) },
                        WidgetContainer:new{ dimen = Geom:new{ w = sc(4), h = 1 } },
                        TextWidget:new{ text = opt.text, face = Font:getFace("cfont", ui_font_size) },
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
        }
        function UnderlinePreview:getSize()
            return Geom:new{ w = self.width, h = self.height }
        end
        function UnderlinePreview:paintTo(bb, x, y)
            local y_line = y + self.height - self.underline_thickness
            if self.underline_style == "wavy" then
                for offset = 0, self.width - 1, 4 do
                    local wave_y = y_line + (math.floor(offset / 4) % 2 == 0 and 0 or 1)
                    local segment_w = math.min(4, self.width - offset)
                    bb:paintRect(x + offset, wave_y, segment_w, self.underline_thickness, self.underline_color_val)
                end
            elseif self.underline_style == "invisible" then
                -- Draw nothing
            else
                bb:paintRect(x, y_line, self.width, self.underline_thickness, self.underline_color_val)
            end
        end

        local face = Font:getFace("cfont", ui_font_size + 2)
        local sample_text = TextWidget:new{
            text = "walked 2 miles today",
            face = face,
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

        local w_walked = RenderText:sizeUtf8Text(0, 9999, face, "walked ", false, false).x
        local w_miles = RenderText:sizeUtf8Text(0, 9999, face, "2 miles", false, false).x

        local underline_widget = UnderlinePreview:new{
            width = w_miles,
            height = sample_size.h,
            underline_style = underline_style,
            underline_thickness = underline_thickness,
            underline_color_val = underline_color_val,
            overlap_offset = { w_walked, 0 },
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

        local title_label = TextWidget:new{
            text = self.loc:t("unit_style_preview_title") or "STYLE PREVIEW",
            face = Font:getFace("infofont", title_font_size),
            fgcolor = Blitbuffer.COLOR_BLACK,
        }

        local style_row = option_row({
            { text = self.loc:t("unit_underline_solid") or "Solid", value = "solid" },
            { text = self.loc:t("unit_underline_wavy") or "Wavy", value = "wavy" },
            { text = self.loc:t("unit_underline_invisible") or "Invisible", value = "invisible" }
        }, underline_style, "unit_underline_style")

        local thickness_row = option_row({
            { text = "1px", value = 1 },
            { text = "2px", value = 2 },
            { text = "3px", value = 3 }
        }, underline_thickness, "unit_underline_thickness")

        local intensity_row = option_row({
            { text = self.loc:t("unit_intensity_light") or "Light", value = "light" },
            { text = self.loc:t("unit_intensity_medium") or "Medium", value = "medium" },
            { text = self.loc:t("unit_intensity_dark") or "Dark", value = "dark" }
        }, underline_intensity, "unit_underline_intensity")

        local timeout_row = option_row({
            { text = "2s", value = 2 },
            { text = "4s", value = 4 },
            { text = "8s", value = 8 },
            { text = self.loc:t("unit_timeout_never") or "Never", value = 0 }
        }, tooltip_timeout, "unit_tooltip_timeout")

        local function span()
            return VerticalSpan:new{ width = xray_theme.gap }
        end
        local function divider()
            return LineWidget:new{
                dimen = Geom:new{ w = dialog_w - sc(32), h = sc(1) },
                background = xray_theme.color_section_rule,
            }
        end

        local function label(text)
            return TextWidget:new{
                text = text:upper(),
                face = Font:getFace("cfont", label_font_size),
                fgcolor = Blitbuffer.COLOR_BLACK,
                alignment = "left",
            }
        end

        local close_btn = Button:new{
            text = "Close",
            face = Font:getFace("cfont", ui_font_size),
            width = dialog_w - sc(32),
            height = sc(42),
            bordersize = xray_theme.border_btn,
            radius = xray_theme.radius_btn,
            callback = function()
                self._styling_offset = nil
                UIManager:close(overlay, "ui")
            end
        }

        local card = FrameContainer:new{
            padding = sc(12),
            radius = xray_theme.radius_window,
            bordersize = sc(2),
            color = Blitbuffer.COLOR_BLACK,
            background = xray_theme.color_bg,
            width = dialog_w,
            VerticalGroup:new{
                align = "left",
                title_label,
                span(),
                preview_panel,
                span(),
                label(self.loc:t("unit_underline_style_label") or "Underline Style"),
                style_row,
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

        overlay = InputContainer:new{
            key_events = {
                Close = { { "Back" } }
            },
            CenterContainer:new{
                dimen = Geom:new{ w = sw, h = sh },
                movable
            }
        }
        function overlay:onClose()
            self._styling_offset = nil
            UIManager:close(overlay, "ui")
            return true
        end

        UIManager:show(overlay, "ui")
    end

    refresh()
end

-- Extracted functions are now loaded via mixins (xray_data, xray_ui, xray_fetch, xray_mentions)

return XRayPlugin
