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

        -- Register X-Ray button with new KOReader dict API (PR #15184+)
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
    self.chapters_fetched = {}
    self.bg_fetch_pending = false

    -- Initialize language based on logic (auto, book, or manual)
    self:applyLanguageLogic()
    
    -- Suggest switching to book language if appropriate
    UIManager:scheduleIn(5, function()
        self:checkBookLanguageMatch()
    end)
    
    -- Weekly silent update check
    UIManager:scheduleIn(10, function()
        self:checkWeeklyUpdate()
    end)

    -- Enforce X-Ray as the first item in the Tools menu for all KOReader versions
    UIManager:scheduleIn(1, function()
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

function XRayPlugin:onPageUpdate(pageno)
    self.last_pageno = pageno

    if self.pending_return_banner then
        local p = self.pending_return_banner
        self.pending_return_banner = nil
        UIManager:scheduleIn(0.3, function()
            self:showReturnBanner(p.return_page, p.entity, p.mentions, self.last_pageno)
        end)
    elseif not self.is_programmatic_navigation then
        if self.return_banner then
            self:closeAllMenus()
        end
    end
    if not self.auto_fetch_enabled then return end
    
    if not self.ui or not self.ui.document then return end

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
    self.last_pageno = pageno

    if not self.auto_fetch_enabled then return end

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
        self.bg_fetch_pending = false
        self:triggerBackgroundMergeFetch(chapter_title)
    end)
end

function XRayPlugin:triggerBackgroundMergeFetch(chapter_title)
    if self.bg_fetch_active then return end
    if not self.ui or not self.ui.document then return end

    -- SILENT NETWORK CHECK: use isOnline() instead of runWhenOnline to avoid "white box" connecting dialogs
    local NetworkMgr = require("ui/network/manager")
    if NetworkMgr:isOnline() then
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
            if not self.ui or not self.ui.document then return end
            self:log("XRayPlugin: Stage 2 - Restoring sort order")
            local function restoreOrder(list)
                table.sort(list, function(a, b)
                    return (a.sort_order or 9999) < (b.sort_order or 9999)
                end)
            end
            restoreOrder(self.characters)
            restoreOrder(self.historical_figures)
            
            -- Stage 3: Repair Page Numbers & Deduplicate (Deferred another 500ms)
            UIManager:scheduleIn(500, function()
                if not self.ui or not self.ui.document then return end
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
                text = self.loc:t("menu_auto_update_frequency") or "Auto X-Ray Settings",
                keep_menu_open = true,
                callback = function() self:showAutoUpdateSettings() end,
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
                text = self.loc:t("menu_linked_entries_settings") or "Linked Entries Settings",
                keep_menu_open = true,
                callback = function() self:showLinkedEntriesSettings() end,
            },
            {
                text = self.loc:t("mentions_setting_title") or "Mentions Settings",
                keep_menu_open = true,
                callback = function() self:showMentionsSettings() end,
            },
            {
                text = self.loc:t("spoiler_preference_title") or "Spoiler Settings",
                keep_menu_open = true,
                callback = function() self:showSpoilerSettings() end,
            },
            {
                text = self.loc:t("menu_xray_mode"),
                keep_menu_open = true,
                callback = function() self:toggleXRayMode() end,
                separator = true,
            },
            {
                text = self.loc:t("menu_language") or "Language",
                keep_menu_open = true,
                callback = function() self:showLanguageSelection() end,
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

return XRayPlugin
