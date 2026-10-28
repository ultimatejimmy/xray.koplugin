-- X-Ray AI Fetching and Network Functions

local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local ButtonDialog = require("ui/widget/buttondialog")
local logger = require("logger")
local plugin_path = ((...) or ""):match("(.-)[^%.]+$") or ""
local utils = require(plugin_path .. "xray_utils")
local SeriesManager = require(plugin_path .. "xray_seriesmanager")

local function bookHasEntities(b, sm)
    if not b or type(b) ~= "table" then return false end
    if sm and sm.hasBookEntities then return sm.hasBookEntities(b) end
    if SeriesManager and SeriesManager.hasBookEntities then return SeriesManager.hasBookEntities(b) end
    return ((b.characters and #b.characters > 0) or
            (b.locations and #b.locations > 0) or
            (b.terms and #b.terms > 0) or
            (b.timeline and #b.timeline > 0)) and true or false
end

local function _truncateSafe(text, limit)
    return (utils:getTruncatedText(text, limit))
end

local function _getCurrentPage(plugin)
    if not plugin or not plugin.ui then return 1 end
    if plugin.ui.getCurrentPage then
        local ok, p = pcall(function() return plugin.ui:getCurrentPage() end)
        if ok and type(p) == "number" then return p end
    end
    if plugin.ui.paging and plugin.ui.paging.getCurrentPage then
        local ok, p = pcall(function() return plugin.ui.paging:getCurrentPage() end)
        if ok and type(p) == "number" then return p end
    end
    if plugin.ui.document and plugin.ui.document.getCurrentPage then
        local ok, p = pcall(function() return plugin.ui.document:getCurrentPage() end)
        if ok and type(p) == "number" then return p end
    end
    return 1
end

local M = {}

function M:isRequestTimedOut(started_at, timeout_seconds)
    return os.difftime(os.time(), started_at or os.time()) >= timeout_seconds
end

function M:cancelActiveAIRequest(reason)
    if self._active_ai_cancel then
        local ok, err = pcall(self._active_ai_cancel, reason or "AI request cancelled")
        if not ok then
            self:log("XRayPlugin: Active AI cancellation callback failed: " .. tostring(err))
        end
    end
    -- The registered callback may be stale or may have failed before reaching
    -- its owned child. A global lifecycle cancellation must not leave whatever
    -- child the helper currently owns running.
    if self.ai_helper and self.ai_helper._async_child_pid then
        self.ai_helper:cancelAsyncChild()
    end
    self._active_ai_cancel = nil
    if self._active_ai_dialog then
        UIManager:close(self._active_ai_dialog)
        self._active_ai_dialog = nil
    end
    self._active_fetch_generation = nil
    self.bg_fetch_active = false
    self.bg_fetch_pending = false
end

local function sanitizeMetadata(val)
    if type(val) == "string" then return val
    elseif type(val) == "table" then return table.concat(val, ", ")
    else return "Unknown" end
end

function M:fetchFromAI()
    require("ui/network/manager"):runWhenOnline(function() 
        if self.destroyed or not self.ui or not self.ui.document then return end
        local current_page = self.ui:getCurrentPage()
        local total_pages = (type(self.ui.document.getPageCount) == "function" and self.ui.document:getPageCount()) or 1
        local reading_percent = math.floor((current_page / total_pages) * 100)
        local spoiler_setting = self.ai_helper.settings and self.ai_helper.settings.spoiler_setting or "spoiler_free"
        
        if spoiler_setting == "full_book" then
            self:continueWithFetch(100)
        else
            self:continueWithFetch(reading_percent)
        end
    end)
end

function M:updateFromAI()
    require("ui/network/manager"):runWhenOnline(function() 
        if self.destroyed or not self.ui or not self.ui.document then return end
        local current_page = self.ui:getCurrentPage()
        local total_pages = (type(self.ui.document.getPageCount) == "function" and self.ui.document:getPageCount()) or 1
        local reading_percent = math.floor((current_page / total_pages) * 100)
        local spoiler_setting = self.ai_helper.settings and self.ai_helper.settings.spoiler_setting or "spoiler_free"
        
        local last_fetch_page = nil
        if self.book_data and self.book_data.last_fetch_page then
            last_fetch_page = self.book_data.last_fetch_page
        end
        self:log("XRayPlugin: updateFromAI - last_fetch_page=" .. tostring(last_fetch_page))
        
        if spoiler_setting == "full_book" then
            self:continueWithFetch(100, true)
        else
            self:continueWithFetch(reading_percent, true, last_fetch_page)
        end
    end)
end

function M:fetchSingleWord(text, pos0, pos1)
    if type(text) == "table" then
        text = text.text or text.word or text.selection_text or ""
    end
    text = tostring(text or "")

    require("ui/network/manager"):runWhenOnline(function()
        if self.destroyed or not self.ui or not self.ui.document then return end

        if self._active_ai_cancel or (self.ai_helper and self.ai_helper._async_child_pid) then
            self:cancelActiveAIRequest("Previous AI request replaced by single word lookup")
        end
        
        local current_page = _getCurrentPage(self)
        local total_pages = (type(self.ui.document.getPageCount) == "function" and self.ui.document:getPageCount()) or 1
        local reading_percent = math.floor((current_page / math.max(1, total_pages)) * 100)
        local spoiler_setting = self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.spoiler_setting or "spoiler_free"
        
        local limit_percent = reading_percent
        if spoiler_setting == "full_book" then limit_percent = 100 end

        if self.ai_helper and type(self.ai_helper.hasApiKey) == "function" and not self.ai_helper:hasApiKey() then
            if self.showWelcomeCard then
                self:showWelcomeCard()
            else
                local ButtonDialog = require("ui/widget/buttondialog")
                local title, text_msg = utils:getFriendlyError("error_api", "invalid api key", self.loc)
                local err_dlg
                err_dlg = ButtonDialog:new{
                    modal = true,
                    title = title .. "\n\n" .. text_msg,
                    text = text_msg,
                    buttons = {{{ text = self.loc:t("ok") or "OK", callback = function() if err_dlg then UIManager:close(err_dlg) end end }}}
                }
                UIManager:show(err_dlg)
            end
            return
        end

        local ButtonDialog = require("ui/widget/buttondialog")
        local request_pid
        local result_file
        local is_cancelled = false
        local progress_msg
        local function cancelLookup(reason, notify_user)
            if is_cancelled then return end
            is_cancelled = true
            if request_pid and self.ai_helper and self.ai_helper.cancelAsyncChild then
                self.ai_helper:cancelAsyncChild(request_pid)
            end
            if result_file then pcall(function() os.remove(result_file) end) end
            if progress_msg then UIManager:close(progress_msg) end
            if self._active_ai_dialog == progress_msg then self._active_ai_dialog = nil end
            if self._active_ai_cancel == cancelLookup then self._active_ai_cancel = nil end
            self:log("XRayPlugin: " .. (reason or "Single word lookup cancelled"))
            if notify_user then
                UIManager:show(InfoMessage:new{ text = notify_user, timeout = 5 })
            end
        end
        local lookup_sub = text .. "\n\n" .. (self.loc:t("fetching_wait") or "This may take a moment.\nTap Cancel to stop.")
        progress_msg = ButtonDialog:new{
            modal = true,
            title = self.loc:t("looking_up_msg", _truncateSafe(text, 30)) .. "\n\n" .. lookup_sub,
            text = lookup_sub,
            tap_close_callback = function() cancelLookup("Single word lookup cancelled by user") end,
            buttons = {{{
                text = self.loc:t("cancel") or "Cancel",
                is_enter_default = true,
                callback = function() cancelLookup("Single word lookup cancelled by user") end,
            }}},
        }
        self._active_ai_dialog = progress_msg
        self._active_ai_cancel = cancelLookup
        UIManager:show(progress_msg)
        UIManager:forceRePaint()

        -- First tick: just let the dialog fully render, then yield back to event loop.
        -- Second tick: start the actual work. This two-step approach ensures the progress
        -- bar borders are fully committed to screen before the CPU starts blocking.
        UIManager:scheduleIn(0.3, function()
            if is_cancelled then return end
            if self.destroyed or not self.ui or not self.ui.document then
                cancelLookup("Single word lookup cancelled because the document or plugin is unavailable", self.loc and self.loc:t("document_unavailable") or "Document unavailable")
                return
            end
            UIManager:scheduleIn(0.3, function()
            if is_cancelled then return end
            if self.destroyed or not self.ui or not self.ui.document then
                cancelLookup("Single word lookup cancelled because the document or plugin is unavailable", self.loc and self.loc:t("document_unavailable") or "Document unavailable")
                return
            end
            if not self.chapter_analyzer then self.chapter_analyzer = require(plugin_path .. "xray_chapteranalyzer"):new() end
            
            local is_anthology = self.isAnthologyMode and self:isAnthologyMode()
            local current_story = is_anthology and self:getCurrentStory(current_page) or nil

            -- 1. Distributed chapter samples (Start/Mid/End of each chapter up to current)
            local samples, chapter_titles = self.chapter_analyzer:getDetailedChapterSamples(
                self.ui, 100, 60000, limit_percent == 100, nil, nil, current_page, current_story)
            
            -- 2. Immediate book text (Previous and Current page for maximum context relevance)
            local end_page = self.chapter_analyzer:getEndPageForCurrentPage(self.ui, current_page)
            local start_page = math.max(1, current_page - 1)
            if current_story then
                start_page = math.max(start_page, current_story.start_page)
                end_page = math.min(end_page, current_story.end_page)
            end
            local raw_book_text = self.chapter_analyzer:getTextFromPageRange(self.ui, start_page, end_page, 25000) or ""
            local book_text = raw_book_text
            -- #150: Clamp single-word lookup text so it doesn't leak remainder of the page beyond the target
            if text and text ~= "" and #raw_book_text > 0 then
                local s_pos = raw_book_text:lower():find(text:lower(), 1, true)
                if s_pos then
                    local cut_pos = math.min(#raw_book_text, s_pos + #text + 200)
                    book_text = raw_book_text:sub(1, cut_pos)
                end
            end
            
            local context_prefix = "SEARCH TARGET: \"" .. text .. "\"\n"
                .. "IMPORTANT: The reader highlighted exactly this text. It IS a meaningful term from this book.\n"
                .. "Even if the exact phrase does not appear in the page samples below, it was highlighted on the reader's current page. Treat it as a valid term and provide its definition.\n\n"
            book_text = context_prefix .. (book_text or "")
            
            -- Always inject a direct reference to ensure the AI validates the term
            if book_text and text ~= "" then
                book_text = book_text .. "\n\n[TERM HIGHLIGHTED BY READER — MUST DEFINE]: \"" .. text .. "\""
            end
            
            self:log("fetchSingleWord: extracted book_text length: " .. tostring(book_text and #book_text or 0))
            
            local context = {
                reading_percent = limit_percent,
                chapter_samples = samples,
                book_text = book_text,
                story_title = current_story and current_story.story_title or nil,
                story_id = current_story and current_story.story_id or nil,
            }

            local DataStorage = require("datastorage")
            local settings_xray_dir = DataStorage:getSettingsDir() .. "/xray"
            
            -- Clean up orphaned fetch files
            pcall(function()
                local ok, lfs = pcall(require, "libs/libkoreader-lfs")
                if not ok or type(lfs) ~= "table" then
                    ok, lfs = pcall(require, "lfs")
                end
                if ok and lfs and lfs.dir then
                    for file in lfs.dir(settings_xray_dir) do
                        if file:find("^sw_fetch_.*%.json$") then
                            os.remove(settings_xray_dir .. "/" .. file)
                        end
                    end
                end
            end)

            if is_cancelled then return end
            if self.destroyed or not self.ui or not self.ui.document then
                cancelLookup("Single word lookup cancelled because the document or plugin is unavailable", self.loc and self.loc:t("document_unavailable") or "Document unavailable")
                return
            end

            -- Cancel any existing background fetch child before starting targeted inline fetch
            if self.ai_helper and self.ai_helper._async_child_pid then
                self.ai_helper:cancelAsyncChild()
            end

            result_file = settings_xray_dir .. "/sw_fetch_" .. tostring(os.time()) .. ".json"
            local pid, err_code, err_msg = self.ai_helper:lookupSingleWordAsync(text, context, result_file)
            request_pid = pid
            if not request_pid then
                if progress_msg then UIManager:close(progress_msg) end
                if self._active_ai_dialog == progress_msg then self._active_ai_dialog = nil end
                if self._active_ai_cancel == cancelLookup then self._active_ai_cancel = nil end
                self:log("XRayPlugin: Failed to start async lookup: " .. tostring(err_msg or err_code))
                local ButtonDialog = require("ui/widget/buttondialog")
                local title, text_msg = utils:getFriendlyError(err_code or "error_api", err_msg or "Failed to start background process", self.loc)
                local err_dlg
                err_dlg = ButtonDialog:new{
                    modal = true,
                    title = title .. "\n\n" .. text_msg,
                    text = text_msg,
                    buttons = {{{ text = self.loc:t("ok") or "OK", callback = function() if err_dlg then UIManager:close(err_dlg) end end }}}
                }
                UIManager:show(err_dlg)
                return
            end

            local request_started_at = os.time()
            local request_timeout = 300
            local function poll()
                if is_cancelled then return end
                if self.destroyed or not self.ui or not self.ui.document then
                    cancelLookup("Single word lookup cancelled because the document or plugin is unavailable", self.loc and self.loc:t("document_unavailable") or "Document unavailable")
                    return
                end

                if not self.ai_helper or not self.ai_helper.checkAsyncResult then
                    cancelLookup("Single word lookup stopped because the AI helper is unavailable", self.loc and self.loc:t("error_api") or "AI service unavailable")
                    return
                end
                local data, p_err_code, p_err_msg = self.ai_helper:checkAsyncResult(result_file, request_pid)
                if data == nil then
                    if not self:isRequestTimedOut(request_started_at, request_timeout) then
                        UIManager:scheduleIn(2, poll)
                    else
                        cancelLookup("Single word lookup timed out")
                        local ButtonDialog = require("ui/widget/buttondialog")
                        local title, text_msg = utils:getFriendlyError("error_timeout", nil, self.loc)
                        local err_dlg
                        err_dlg = ButtonDialog:new{
                            modal = true,
                            title = title .. "\n\n" .. text_msg,
                            text = text_msg,
                            buttons = {{{ text = self.loc:t("ok") or "OK", callback = function() if err_dlg then UIManager:close(err_dlg) end end }}}
                        }
                        UIManager:show(err_dlg)
                    end
                elseif data == false then
                    if progress_msg then UIManager:close(progress_msg) end
                    if self._active_ai_dialog == progress_msg then self._active_ai_dialog = nil end
                    if self._active_ai_cancel == cancelLookup then self._active_ai_cancel = nil end
                    self:log("XRayPlugin: Single word lookup failed: " .. tostring(p_err_msg))
                    local ButtonDialog = require("ui/widget/buttondialog")
                    local title, text_msg = utils:getFriendlyError(p_err_code, p_err_msg, self.loc)
                    local err_dlg
                    err_dlg = ButtonDialog:new{
                        modal = true,
                        title = title .. "\n\n" .. text_msg,
                        text = text_msg,
                        buttons = {{{ text = self.loc:t("ok") or "OK", callback = function() if err_dlg then UIManager:close(err_dlg) end end }}}
                    }
                    UIManager:show(err_dlg)
                else
                    if progress_msg then
                        UIManager:scheduleIn(0.1, function()
                            UIManager:close(progress_msg)
                            if self._active_ai_dialog == progress_msg then self._active_ai_dialog = nil end
                            if self._active_ai_cancel == cancelLookup then self._active_ai_cancel = nil end
                            if not is_cancelled then
                                self:_processSingleWordResult(data, text, book_text, current_page)
                            end
                        end)
                    elseif not is_cancelled then
                        self:_processSingleWordResult(data, text, book_text, current_page)
                    end
                end
            end
            UIManager:scheduleIn(2, poll)
            end) -- end inner scheduleIn(0.3)
        end) -- end outer scheduleIn(0.3)
    end)
end

function M:_processSingleWordResult(result, text, book_text, current_page)
    if self.destroyed or not self.ui or not self.ui.document then return end
    local safe_text = type(text) == "string" and text or tostring(text or "")
    if type(result) ~= "table" then
        local err = self.loc:t("entity_not_found", safe_text:sub(1, 20))
        UIManager:show(InfoMessage:new{ text = err, timeout = 5 })
        return
    end

    if result.is_valid == true or result.is_valid == "true" then
        local item = result.item
        local raw_type = tostring(result.type or ""):lower():gsub("%s+", "_")
        local item_type = raw_type
        if item_type == "historical" or item_type == "historicalfigure" then
            item_type = "historical_figure"
        end
        if type(item) ~= "table" or not item.name then
            local err = result.error_message or self.loc:t("entity_not_found", safe_text:sub(1, 20))
            UIManager:show(InfoMessage:new{ text = err, timeout = 5 })
            return
        end
        
        -- Ensure tables exist before trying to merge
        self.characters = self.characters or {}
        self.locations = self.locations or {}
        self.historical_figures = self.historical_figures or {}
        self.terms = self.terms or {}

        -- Merge into our tables
        local target_list
        if item_type == "character" then
            target_list = self.characters
        elseif item_type == "location" then
            target_list = self.locations
        elseif item_type == "historical_figure" then
            target_list = self.historical_figures
        elseif item_type == "term" then
            target_list = self.terms
        end

        if target_list then
            local is_anthology = self.isAnthologyMode and self:isAnthologyMode()
            local current_story = is_anthology and self:getCurrentStory(current_page) or nil
            if is_anthology and current_story then
                item.story_id = item.story_id or current_story.story_id
                item.story_title = item.story_title or current_story.story_title
            end

            -- Resolve current chapter title for history tracking
            local chapter_title = nil
            if self.ui and self.ui.document and current_page then
                local toc = utils:flattenTOC(self.ui.document:getToc())
                if toc then
                    local max_p = -1
                    for _, entry in ipairs(toc) do
                        if entry.page then
                            local p = tonumber(entry.page)
                            if p and p <= current_page and p >= max_p then
                                max_p = p
                                chapter_title = entry.title
                            end
                        end
                    end
                end
            end

            -- Check if already exists (case-insensitive)
            local found = false
            for _, existing in ipairs(target_list) do
                local name_match = (existing.name or ""):lower() == (item.name or ""):lower()
                local story_match = true
                if is_anthology and current_story then
                    local ex_st = existing.story_id or (self.resolveEntityStory and self:resolveEntityStory(existing))
                    story_match = (ex_st == (item.story_id or current_story.story_id))
                end
                if name_match and story_match then
                    -- Update description/role
                    for k, v in pairs(item) do existing[k] = v end
                    
                    -- Record history for single word lookup
                    local desc_key = item_type == "historical_figure" and "biography" or "description"
                    if existing[desc_key] and existing[desc_key] ~= "" then
                        existing.history = existing.history or {}
                        local dup = false
                        for _, entry in ipairs(existing.history) do
                            if entry.page == current_page then
                                entry[desc_key] = existing[desc_key]
                                entry.chapter = chapter_title or entry.chapter
                                dup = true; break
                            end
                        end
                        if not dup then
                            local hist_entry = { page = current_page, chapter = chapter_title or "" }
                            hist_entry[desc_key] = existing[desc_key]
                            table.insert(existing.history, hist_entry)
                        end
                    end
                    found = true
                    break
                end
            end
            if not found then
                local desc_key = item_type == "historical_figure" and "biography" or "description"
                if item[desc_key] and item[desc_key] ~= "" then
                    local hist_entry = { page = current_page, chapter = chapter_title or "" }
                    hist_entry[desc_key] = item[desc_key]
                    item.history = { hist_entry }
                end
                table.insert(target_list, item)
            end
            
            target_list = self:deduplicateByName(target_list, "name")
            if item_type == "character" then
                self.characters = target_list
            elseif item_type == "location" then
                self.locations = target_list
            elseif item_type == "historical_figure" then
                self.historical_figures = target_list
            elseif item_type == "term" then
                self.terms = target_list
            end

            -- Sort and save cache
            self:sortDataByFrequency(target_list, book_text, "name")
            if not self.cache_manager then self.cache_manager = require(plugin_path .. "xray_cachemanager"):new() end
            
            local doc_file = self.ui and self.ui.document and self.ui.document.file
            if not self.book_data then
                self.book_data = (doc_file and self.cache_manager:loadCache(doc_file)) or {}
            end
            local updated = self.book_data
            updated.characters = self.characters
            updated.locations = self.locations
            updated.historical_figures = self.historical_figures
            updated.terms = self.terms
            updated.timeline = self.timeline
            updated.book_type = self.book_type or updated.book_type
            updated.author_info = self.author_info or updated.author_info
            updated.images = (self.images and #self.images > 0 and self.images) or updated.images or (self.book_data and self.book_data.images)
            updated.last_fetch_page = updated.last_fetch_page
            
            if doc_file then
                self.cache_manager:asyncSaveCache(doc_file, updated)
            end
        end
        
        -- Always show result if it's valid, even if it didn't merge into a target_list
        self.lookup_manager:showResult(item, item_type)
    else
        local err = result.error_message or self.loc:t("entity_not_found", safe_text:sub(1, 20))
        UIManager:show(InfoMessage:new{ text = err, timeout = 5 })
    end
end

function M:continueWithFetch(reading_percent, is_update, last_fetch_page, is_silent, batch_end_page, on_complete_cb)
    local completed = false
    local function notifyComplete(success, err_code, err_msg)
        if completed then return end
        completed = true
        if on_complete_cb then
            pcall(on_complete_cb, success, err_code, err_msg)
        end
    end

    if self.destroyed or not self.ui or not self.ui.document then
        notifyComplete(false, "cancelled")
        return
    end
    local doc_file = self.ui.document.file
    if not doc_file then
        notifyComplete(false, "cancelled")
        return
    end

    if is_silent then
        local is_low, avail_kb = utils:isLowMemory(30 * 1024)
        if is_low then
            self.bg_fetch_pending = false
            local msg = string.format("XRayPlugin: Available memory is critically low (%d KB < 30 MB), skipping background fetch to prevent OOM", avail_kb or 0)
            self:log(msg)
            logger.warn(msg)
            notifyComplete(false, "low_memory", msg)
            return
        end
    end

    local has_active_request = self._active_ai_cancel
        or (self.ai_helper and self.ai_helper._async_child_pid)
    if is_silent and has_active_request then
        self.bg_fetch_pending = false
        self:log("XRayPlugin: Skipping background fetch because another AI request is active")
        notifyComplete(false, "busy")
        return
    elseif not is_silent and has_active_request then
        self:cancelActiveAIRequest("Previous AI request replaced by manual fetch")
    end
    self._fetch_generation = (self._fetch_generation or 0) + 1
    local fetch_generation = self._fetch_generation
    self._active_fetch_generation = fetch_generation
    self.bg_fetch_active = true

    local function clearFetchState()
        if self._active_fetch_generation == fetch_generation then
            self._active_fetch_generation = nil
            self.bg_fetch_active = false
        end
    end

    if not self.ai_helper then
        local AIHelper = require(plugin_path .. "xray_aihelper")
        self.ai_helper = AIHelper
        self.ai_helper:init(self.path)
    end

    -- Invalidate timeline if the current timeline length setting is greater than what was cached
    if not self.cache_manager then self.cache_manager = require(plugin_path .. "xray_cachemanager"):new() end
    local cached = self.book_data or self.cache_manager:loadCache(doc_file)
    if cached and cached.timeline and #cached.timeline > 0 then
        local s = self.ai_helper and self.ai_helper.settings or {}
        local current_len = s.timeline_event_len or 80
        local cached_len = cached.timeline_event_len or 80
        if current_len > cached_len then
            self:log("XRayPlugin: timeline_event_len increased from " .. tostring(cached_len) .. " to " .. tostring(current_len) .. ". Regenerating timeline.")
            self.timeline = {}
            cached.timeline = {}
            if self.book_data then
                self.book_data.timeline = {}
            end
        end
    end

    local props = self.ui.document:getProps() or {}
    local title = sanitizeMetadata(props.title)
    local author = sanitizeMetadata(props.authors)

    -- For manual (non-silent) fetches, show a ButtonDialog with a Cancel button.
    -- We use the async path for ALL fetches so we never need Trapper:dismissableRunInSubprocess
    -- (which requires an InfoMessage widget and breaks with ButtonDialog).
    local wait_msg
    local is_cancelled = false
    local result_file
    local request_pid
    local cancelActiveRequest

    local function finishActiveRequest()
        request_pid = nil
        result_file = nil
        clearFetchState()
        if self._active_ai_dialog == wait_msg then self._active_ai_dialog = nil end
        if self._active_ai_cancel == cancelActiveRequest then self._active_ai_cancel = nil end
    end

    cancelActiveRequest = function(reason)
        if is_cancelled then return end
        is_cancelled = true
        if request_pid and self.ai_helper and self.ai_helper.cancelAsyncChild then
            self.ai_helper:cancelAsyncChild(request_pid)
        end
        if result_file then
            pcall(function() os.remove(result_file) end)
        end
        if wait_msg then
            UIManager:close(wait_msg)
        end
        finishActiveRequest()
        self:log("XRayPlugin: " .. reason)
        notifyComplete(false, "cancelled", reason)
    end

    self._active_ai_cancel = cancelActiveRequest

    if not is_silent then
        local ButtonDialog = require("ui/widget/buttondialog")
        local fetch_text = is_update
            and (self.loc:t("updating_ai", self.ai_provider or "AI") or "Updating X-Ray...")
            or  (self.loc:t("fetching_ai",  self.ai_provider or "AI") or "Fetching X-Ray...")
        local wait_sub = title .. "\n\n" .. (self.loc:t("fetching_wait") or "This may take a moment.\nTap Cancel to stop.")
        wait_msg = ButtonDialog:new{
            modal = true,
            title = fetch_text .. "\n\n" .. wait_sub,
            text  = wait_sub,
            tap_close_callback = function()
                cancelActiveRequest("Fetch cancelled by user")
            end,
            buttons = {{{
                text = self.loc:t("cancel") or "Cancel",
                is_enter_default = true,
                callback = function()
                    cancelActiveRequest("Fetch cancelled by user")
                end
            }}}
        }
        self._active_ai_dialog = wait_msg
        UIManager:show(wait_msg)
    end

    UIManager:scheduleIn(0.5, function()
        if is_cancelled or self.destroyed or not self.ui or not self.ui.document then
            clearFetchState()
            cancelActiveRequest(self.destroyed
                and "Fetch stopped because plugin was destroyed"
                or "Fetch stopped because the document was closed")
            return
        end
        if not self.chapter_analyzer then self.chapter_analyzer = require(plugin_path .. "xray_chapteranalyzer"):new() end

        local current_page = batch_end_page or self.ui:getCurrentPage()
        local is_anthology = self.isAnthologyMode and self:isAnthologyMode()
        local current_story = nil
        if is_anthology then
            current_story = self:getCurrentStory(current_page)
        end

        local first_missing_page = last_fetch_page
        if is_anthology and current_story then
            local story_state = self.book_data and self.book_data.story_fetch_state and self.book_data.story_fetch_state[current_story.story_id]
            if is_update then
                first_missing_page = story_state and story_state.last_fetch_page and (story_state.last_fetch_page + 1) or current_story.start_page
            else
                first_missing_page = current_story.start_page
            end
        end

        if is_update then
            local toc = utils:flattenTOC(self.ui.document:getToc())
            local candidate_chapters = {}
            for i = #toc, 1, -1 do
                local entry = toc[i]
                if entry.page and entry.page <= current_page then
                    if not is_anthology or not current_story or (entry.page >= current_story.start_page and entry.page <= (current_story.end_page or current_page)) then
                        if not self:isNonNarrativeChapter(entry.title) then
                            table.insert(candidate_chapters, entry)
                            if #candidate_chapters >= 3 then break end
                        end
                    end
                end
            end
            for _, entry in ipairs(candidate_chapters) do
                local norm = self:normalizeChapterName(entry.title)
                local found = false
                for _, ev in ipairs(self.timeline or {}) do
                    if self:normalizeChapterName(ev.chapter or "") == norm then
                        if not ev.page or ev.page == entry.page then found = true; break end
                    end
                end
                if not found then
                    if not first_missing_page or entry.page < first_missing_page then
                        first_missing_page = entry.page
                        self:log("XRayPlugin: Repair mode active: recovering missing chapter '" .. tostring(entry.title) .. "' starting at page " .. tostring(entry.page))
                    end
                end
            end
        end

        local end_page_analysis = current_page
        local spoiler_setting = self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.spoiler_setting or "spoiler_free"
        if is_anthology and current_story then
            if spoiler_setting == "full_book" then
                end_page_analysis = current_story.end_page
            elseif batch_end_page then
                end_page_analysis = math.min(batch_end_page, current_story.end_page)
            else
                end_page_analysis = math.min(self.chapter_analyzer:getEndPageForCurrentPage(self.ui, current_page), current_story.end_page)
            end
        elseif spoiler_setting ~= "full_book" or batch_end_page then
            end_page_analysis = self.chapter_analyzer:getEndPageForCurrentPage(self.ui, current_page)
        end

        -- A cached page can outlive pagination changes or be ahead of the
        -- reader's current position. In that case an incremental XPointer
        -- range would be empty/reversed; use the current chapter context.
        local stale_cached_position = false
        if first_missing_page and first_missing_page >= end_page_analysis then
            if is_silent then
                self:log("XRayPlugin: Silent fetch aborted - current page already covered (last_fetch_page="
                    .. tostring(first_missing_page) .. ", end_page=" .. tostring(end_page_analysis) .. ")")
                if wait_msg then UIManager:close(wait_msg) end
                finishActiveRequest()
                notifyComplete(false, "ALREADY_COVERED")
                return
            end
            -- #150: When reader has navigated backward, aborting avoids rewriting earlier descriptions with future knowledge
            self:log("XRayPlugin: Position already covered (last_fetch_page=" .. tostring(first_missing_page)
                .. " >= end_page=" .. tostring(end_page_analysis) .. "). Aborting update to avoid rewriting descriptions with future knowledge.")
            if wait_msg then UIManager:close(wait_msg) end
            local translated = self.loc:t("no_new_text")
            local message = (translated and translated ~= "no_new_text") and translated
                or "No new text was available at your current position; X-Ray is already up to date here."
            UIManager:show(InfoMessage:new{ text = message, timeout = 4 })
            finishActiveRequest()
            notifyComplete(false, "ALREADY_COVERED")
            return
        end

        local book_text = self.chapter_analyzer:getTextForAnalysis(self.ui, 20000, nil, end_page_analysis, first_missing_page, nil, current_story)
        local known_chapters = {}
        if is_update and self.timeline then
            for _, ev in ipairs(self.timeline) do
                if ev.chapter then known_chapters[self:normalizeChapterName(ev.chapter)] = true end
            end
        end

        UIManager:scheduleIn(0, function()
            if is_cancelled or self.destroyed or not self.ui or not self.ui.document then
                clearFetchState()
                cancelActiveRequest(self.destroyed
                    and "Fetch stopped because plugin was destroyed"
                    or "Fetch stopped because the document was closed")
                return
            end

            local is_full_book = (reading_percent == 100 and not batch_end_page)
            local samples, chapter_titles = self.chapter_analyzer:getDetailedChapterSamples(
                self.ui, 200, 150000, is_full_book, first_missing_page, known_chapters, current_page, current_story)
            local annots = self.chapter_analyzer:getAnnotationsForAnalysis(self.ui, current_page)

            if (not book_text or #book_text < 10) and not samples then
                if wait_msg then UIManager:close(wait_msg) end
                local message = self.loc:t("error_extract_text") or "Error: Could not extract book text."
                if is_update and stale_cached_position then
                    local translated = self.loc:t("no_new_text")
                    message = (translated and translated ~= "no_new_text") and translated
                        or "No new text was available at your current position; X-Ray is already up to date here."
                end
                if not is_silent then UIManager:show(InfoMessage:new{ text = message, timeout = 5 }) end
                self:log("XRayPlugin: Text extraction failed" .. (is_silent and " (silent)" or ""))
                finishActiveRequest()
                notifyComplete(false, "error_extract")
                return
            end

            local existing_chars = is_update and self.characters or nil
            local existing_locs = is_update and self.locations or nil
            local existing_hist = is_update and self.historical_figures or nil
            if is_anthology and current_story then
                if existing_chars then
                    local f = {}
                    for _, c in ipairs(existing_chars) do
                        if self:isEntityInCurrentStory(c, current_story) then table.insert(f, c) end
                    end
                    existing_chars = f
                end
                if existing_locs then
                    local f = {}
                    for _, l in ipairs(existing_locs) do
                        if self:isEntityInCurrentStory(l, current_story) then table.insert(f, l) end
                    end
                    existing_locs = f
                end
                if existing_hist then
                    local f = {}
                    for _, h in ipairs(existing_hist) do
                        if self:isEntityInCurrentStory(h, current_story) then table.insert(f, h) end
                    end
                    existing_hist = f
                end
            end

            local context = {
                reading_percent = reading_percent,
                spoiler_free = reading_percent < 100,
                filename = self.ui.document.file:match("([^/\\]+)$"),
                series = props.series or props.Series,
                chapter_samples = samples,
                chapter_titles = chapter_titles,
                annotations = annots,
                book_text = book_text,
                existing_characters = existing_chars,
                existing_locations = existing_locs,
                existing_historical_figures = existing_hist,
                book_type = is_anthology and "anthology" or self.book_type,
                story_title = current_story and current_story.story_title or nil,
                story_id = current_story and current_story.story_id or nil,
            }

            local req_params, err_code, err_msg = self.ai_helper:buildComprehensiveRequest(title, author, context)
            if not req_params then
                if wait_msg then UIManager:close(wait_msg) end
                self:log("XRayPlugin: Failed to build request: " .. tostring(err_msg))
                finishActiveRequest()
                notifyComplete(false, err_code, err_msg)
                if not is_silent then
                    if not self.ai_helper:hasApiKey() and self.showWelcomeCard then
                        self:showWelcomeCard()
                    else
                        local ButtonDialog = require("ui/widget/buttondialog")
                        local title, text = utils:getFriendlyError(err_code, err_msg, self.loc)
                        local err_box
                        err_box = ButtonDialog:new{
                            title = title .. "\n\n" .. text,
                            text = text,
                            buttons = {{{ text = self.loc:t("ok") or "OK", callback = function() if err_box then UIManager:close(err_box) end end }}}
                        }
                        UIManager:show(err_box)
                    end
                end
                return
            end

            local DataStorage = require("datastorage")
            local settings_xray_dir = DataStorage:getSettingsDir() .. "/xray"

            -- Clean up any orphaned fetch files from previous cancelled/timed-out fetches in this session
            pcall(function()
                local ok, lfs = pcall(require, "libs/libkoreader-lfs")
                if not ok or type(lfs) ~= "table" then
                    ok, lfs = pcall(require, "lfs")
                end
                if ok and lfs and lfs.dir then
                    for file in lfs.dir(settings_xray_dir) do
                        if file:find("^bg_fetch_.*%.json$") then
                            os.remove(settings_xray_dir .. "/" .. file)
                        end
                    end
                end
            end)

            result_file = settings_xray_dir .. "/bg_fetch_" .. tostring(os.time()) .. "_" .. tostring(fetch_generation) .. ".json"
            local started = self.ai_helper:makeRequestAsync(req_params, result_file)
            if not started then
                if wait_msg then UIManager:close(wait_msg) end
                self:log("XRayPlugin: Failed to start async fetch")
                pcall(function() os.remove(result_file) end)
                result_file = nil
                finishActiveRequest()
                notifyComplete(false, "error_start")
                return
            end
            request_pid = started

            local request_started_at = os.time()
            local request_timeout = 600
            local function poll()
                if is_cancelled then return end
                if self.destroyed then
                    cancelActiveRequest("Fetch stopped because plugin was destroyed")
                    return
                end
                if not self.ui or not self.ui.document then
                    cancelActiveRequest("Fetch stopped because the document was closed")
                    return
                end
                local data, p_err_code, p_err_msg = self.ai_helper:checkAsyncResult(result_file, request_pid)
                if data == nil then
                    if not self:isRequestTimedOut(request_started_at, request_timeout) then
                        UIManager:scheduleIn(2, poll)
                    else
                        cancelActiveRequest("Fetch timed out")
                        if not is_silent then
                            local ButtonDialog = require("ui/widget/buttondialog")
                            local title, text = utils:getFriendlyError("error_timeout", nil, self.loc)
                            local err_box
                            err_box = ButtonDialog:new{
                                modal = true,
                                title = title .. "\n\n" .. text,
                                text = text,
                                buttons = {{{ text = self.loc:t("ok") or "OK", callback = function() if err_box then UIManager:close(err_box) end end }}}
                            }
                            UIManager:show(err_box)
                        end
                    end
                elseif data == false then
                    if wait_msg then UIManager:close(wait_msg) end
                    finishActiveRequest()
                    self:log("XRayPlugin: Fetch failed: " .. tostring(p_err_msg))
                    notifyComplete(false, p_err_code, p_err_msg)
                    if not is_silent then
                        local ButtonDialog = require("ui/widget/buttondialog")
                        local title, text = utils:getFriendlyError(p_err_code, p_err_msg, self.loc)
                        local err_box
                        err_box = ButtonDialog:new{
                            modal = true,
                            title = title .. "\n\n" .. text,
                            text = text,
                            buttons = {{{ text = self.loc:t("ok") or "OK", callback = function() if err_box then UIManager:close(err_box) end end }}}
                        }
                        UIManager:show(err_box)
                    end
                else
                    if wait_msg then UIManager:close(wait_msg) end
                    finishActiveRequest()
                    self:finalizeXRayData(data, title, author, book_text, is_update, is_silent, current_page)
                    notifyComplete(true)
                end
            end
            UIManager:scheduleIn(2, poll)
        end)
    end)
end

function M:updateEntityDescPreservingPrior(existing, new_desc, key)
    if not existing then return nil end
    if not new_desc or new_desc == "" then return nil end
    local field = key or "description"
    local exist_desc = existing[field] or existing.description or ""
    if type(exist_desc) == "string" and exist_desc:find("%[From Book [%d%.]+%]") then
        local prior_parts = {}
        for sec in (exist_desc .. "\n\n"):gmatch("(.-)\n%s*\n+") do
            local trimmed = sec:match("^%s*(.-)%s*$")
            if trimmed and trimmed:find("^%[From Book [%d%.]+%]") then
                table.insert(prior_parts, trimmed)
            end
        end
        if #prior_parts > 0 then
            local combined = SeriesManager.reorderSeriesDescription(new_desc .. "\n\n" .. table.concat(prior_parts, "\n\n"))
            existing[field] = combined
            if field ~= "description" then existing.description = combined end
            return new_desc
        end
    end
    existing[field] = new_desc
    if field ~= "description" then existing.description = new_desc end
    return new_desc
end

function M:markSeriesSyncDirty(slug, index, title, author, doc_file, has_explicit_index)
    if not slug or not index then return end
    self._pending_series_sync = {
        slug = slug,
        index = index,
        title = title,
        author = author,
        doc_file = doc_file,
        has_explicit_index = has_explicit_index
    }
end

function M:flushSeriesSync()
    local pending = self._pending_series_sync
    if not pending or not self.series_manager then return end
    self._pending_series_sync = nil

    local book_data = self.book_data
    if not book_data and pending.doc_file and self.cache_manager then
        book_data = self.cache_manager:loadCache(pending.doc_file)
    end
    if not book_data then return end

    pcall(function()
        self.series_manager:syncBookToSeriesCache(
            pending.slug,
            pending.index,
            pending.title,
            pending.author,
            book_data,
            pending.doc_file,
            pending.has_explicit_index
        )
        self:log("XRayPlugin: Flushed deferred series sync for " .. tostring(pending.slug))
    end)
end

function M:finalizeXRayData(final_book_data, title, author, book_text, is_update, is_silent, current_page)
    if self.destroyed or not self.ui or not self.ui.document then return end
    final_book_data.book_title = title
    final_book_data.author = author

    local is_anthology = self.isAnthologyMode and self:isAnthologyMode()
    local current_story = nil
    if is_anthology then
        current_story = self:getCurrentStory(current_page)
        if current_story then
            local function tagList(list)
                if not list then return end
                for _, item in ipairs(list) do
                    if not item.story_id then item.story_id = current_story.story_id end
                    if not item.story_title then item.story_title = current_story.story_title end
                end
            end
            tagList(final_book_data.characters)
            tagList(final_book_data.historical_figures)
            tagList(final_book_data.locations)
            tagList(final_book_data.terms)
            tagList(final_book_data.timeline)
        end
    end

    -- Frequency Sorting
    final_book_data.characters = self:sortDataByFrequency(final_book_data.characters, book_text, "name")
    final_book_data.historical_figures = self:sortDataByFrequency(final_book_data.historical_figures, book_text, "name")
    final_book_data.locations = self:sortDataByFrequency(final_book_data.locations, book_text, "name")
    final_book_data.terms = self:deduplicateByName(final_book_data.terms or {}, "name")
    final_book_data.terms = self:sortDataByFrequency(final_book_data.terms, book_text, "name")

    -- Filter non-narrative timeline entries the AI may have hallucinated
    if final_book_data.timeline then
        local filtered_timeline = {}
        for _, ev in ipairs(final_book_data.timeline) do
            if not self:isNonNarrativeChapter(ev.chapter) then
                table.insert(filtered_timeline, ev)
            else
                self:log("XRayPlugin: Filtered non-narrative timeline entry: " .. tostring(ev.chapter))
            end
        end
        final_book_data.timeline = filtered_timeline
    end

    -- Guard: never overwrite existing data with an all-empty result
    local char_count = #(final_book_data.characters or {})
    local loc_count  = #(final_book_data.locations or {})
    local tl_count   = #(final_book_data.timeline or {})
    local hist_count = #(final_book_data.historical_figures or {})
    local term_count = #(final_book_data.terms or {})

    if char_count == 0 and loc_count == 0 and tl_count == 0 and hist_count == 0 and term_count == 0 then
        self:log("XRayPlugin: AI returned all-empty data — aborting cache write to protect existing data")
        if not is_silent then
            local msg = "The AI returned no data.\n\nThis usually means the book sample was too short. Try reading further into the book, then fetch again."
            UIManager:show(InfoMessage:new{ text = msg, timeout = 8 })
        end
        self.bg_fetch_active = false
        return  -- do NOT touch self.characters / self.locations / cache
    end

    -- Resolve current chapter title for history tracking
    local chapter_title = nil
    if self.ui and self.ui.document and current_page then
        local toc = utils:flattenTOC(self.ui.document:getToc())
        if toc then
            local max_p = -1
            for _, entry in ipairs(toc) do
                if entry.page then
                    local p = tonumber(entry.page)
                    if p and p <= current_page and p >= max_p then
                        max_p = p
                        chapter_title = entry.title
                    end
                end
            end
        end
    end

    if is_update then
        -- Ensure tables exist before attempting to merge/insert
        self.characters = self.characters or {}
        self.historical_figures = self.historical_figures or {}
        self.locations = self.locations or {}
        self.timeline = self.timeline or {}

        local match_story = function(existing_item, new_item)
            if not is_anthology or not current_story then return true end
            local ex_st = existing_item.story_id or (self.resolveEntityStory and self:resolveEntityStory(existing_item))
            local new_st = new_item.story_id or current_story.story_id
            return ex_st == new_st
        end

        -- Merge characters
        local match_char = function(existing_char, new_char)
            if not match_story(existing_char, new_char) then return false end
            local ex_name = existing_char.name and existing_char.name:lower() or ""
            local new_name = new_char.name and new_char.name:lower() or ""
            if ex_name ~= "" and ex_name == new_name then return true end
            if existing_char.aliases and type(existing_char.aliases) == "table" then
                for _, a in ipairs(existing_char.aliases) do
                    if type(a) == "string" and a:lower() == new_name then return true end
                end
            end
            if new_char.aliases and type(new_char.aliases) == "table" then
                for _, a in ipairs(new_char.aliases) do
                    if type(a) == "string" and a:lower() == ex_name then return true end
                end
            end
            return false
        end

        for _, new_char in ipairs(final_book_data.characters or {}) do
            local found = false
            for _, existing_char in ipairs(self.characters) do
                if match_char(existing_char, new_char) then
                    existing_char.role = new_char.role or existing_char.role
                    if new_char.aliases and type(new_char.aliases) == "table" then
                        existing_char.aliases = existing_char.aliases or {}
                        local seen_a = {}
                        for _, a in ipairs(existing_char.aliases) do seen_a[a:lower()] = true end
                        for _, a in ipairs(new_char.aliases) do
                            if a and a ~= "" and not seen_a[a:lower()] then
                                table.insert(existing_char.aliases, a)
                                seen_a[a:lower()] = true
                            end
                        end
                    end
                    -- Update existing description while preserving prior series context
                    if new_char.description and new_char.description ~= "" then
                        local clean_desc = self:updateEntityDescPreservingPrior(existing_char, new_char.description, "description")
                        
                        -- Record history with clean current-book description
                        existing_char.history = existing_char.history or {}
                        local dup = false
                        for _, entry in ipairs(existing_char.history) do
                            if entry.page == current_page then
                                entry.description = clean_desc or new_char.description
                                entry.chapter = chapter_title or entry.chapter
                                dup = true
                                break
                            end
                        end
                        if not dup then
                            table.insert(existing_char.history, {
                                page = current_page,
                                chapter = chapter_title or "",
                                description = clean_desc or new_char.description
                            })
                        end
                    end
                    if existing_char.source == "series_prior" then
                        existing_char.is_series = true
                        existing_char.from_series = true
                        existing_char.source = nil
                    end
                    found = true
                    break
                end
            end
            if not found then
                if new_char.description and new_char.description ~= "" then
                    new_char.history = {
                        {
                            page = current_page,
                            chapter = chapter_title or "",
                            description = new_char.description
                        }
                    }
                end
                table.insert(self.characters, new_char)
            end
        end
        -- Dedup then re-sort the entire character list by frequency in the current context
        self.characters = self:deduplicateByName(self.characters, "name")
        if book_text and #book_text > 0 then
            self:sortDataByFrequency(self.characters, book_text, "name")
        end
        -- Merge historical figures
        for _, new_fig in ipairs(final_book_data.historical_figures or {}) do
            local found = false
            for _, existing_fig in ipairs(self.historical_figures or {}) do
                if existing_fig.name:lower() == new_fig.name:lower() and match_story(existing_fig, new_fig) then
                    if new_fig.biography and new_fig.biography ~= "" then
                        existing_fig.biography = new_fig.biography
                        
                        -- Record history
                        existing_fig.history = existing_fig.history or {}
                        local dup = false
                        for _, entry in ipairs(existing_fig.history) do
                            if entry.page == current_page then
                                entry.biography = new_fig.biography
                                entry.chapter = chapter_title or entry.chapter
                                dup = true
                                break
                            end
                        end
                        if not dup then
                            table.insert(existing_fig.history, {
                                page = current_page,
                                chapter = chapter_title or "",
                                biography = new_fig.biography
                            })
                        end
                    end
                    existing_fig.role = new_fig.role
                    if existing_fig.source == "series_prior" then
                        existing_fig.is_series = true
                        existing_fig.from_series = true
                        existing_fig.source = nil
                    end
                    found = true
                    break
                end
            end
            if not found then
                if new_fig.biography and new_fig.biography ~= "" then
                    new_fig.history = {
                        {
                            page = current_page,
                            chapter = chapter_title or "",
                            biography = new_fig.biography
                        }
                    }
                end
                table.insert(self.historical_figures, new_fig)
            end
        end
        self.historical_figures = self:deduplicateByName(self.historical_figures, "name")
        -- Merge locations
        for _, new_loc in ipairs(final_book_data.locations or {}) do
            local found = false
            for _, existing_loc in ipairs(self.locations or {}) do
                if existing_loc.name:lower() == new_loc.name:lower() and match_story(existing_loc, new_loc) then
                    if new_loc.description and new_loc.description ~= "" then
                        local clean_desc = self:updateEntityDescPreservingPrior(existing_loc, new_loc.description, "description")
                        
                        -- Record history
                        existing_loc.history = existing_loc.history or {}
                        local dup = false
                        for _, entry in ipairs(existing_loc.history) do
                            if entry.page == current_page then
                                entry.description = clean_desc or new_loc.description
                                entry.chapter = chapter_title or entry.chapter
                                dup = true
                                break
                            end
                        end
                        if not dup then
                            table.insert(existing_loc.history, {
                                page = current_page,
                                chapter = chapter_title or "",
                                description = clean_desc or new_loc.description
                            })
                        end
                    end
                    if existing_loc.source == "series_prior" then
                        existing_loc.is_series = true
                        existing_loc.from_series = true
                        existing_loc.source = nil
                    end
                    found = true
                    break
                end
            end
            if not found then
                if new_loc.description and new_loc.description ~= "" then
                    new_loc.history = {
                        {
                            page = current_page,
                            chapter = chapter_title or "",
                            description = new_loc.description
                        }
                    }
                end
                table.insert(self.locations, new_loc)
            end
        end
        self.locations = self:deduplicateByName(self.locations, "name")
        -- Merge terms
        self.terms = self.terms or {}
        for _, new_term in ipairs(final_book_data.terms or {}) do
            local found = false
            for _, existing in ipairs(self.terms) do
                if existing.name:lower() == new_term.name:lower() and match_story(existing, new_term) then
                    if new_term.definition and new_term.definition ~= "" then
                        self:updateEntityDescPreservingPrior(existing, new_term.definition, "definition")
                    end
                    existing.expanded = new_term.expanded or existing.expanded
                    existing.aliases = new_term.aliases or existing.aliases
                    existing._norm_aliases = nil
                    if existing.source == "series_prior" then
                        existing.is_series = true
                        existing.from_series = true
                        existing.source = nil
                    end
                    found = true; break
                end
            end
            if not found then table.insert(self.terms, new_term) end
        end
        self.terms = self:deduplicateByName(self.terms, "name")
        if book_text and #book_text > 0 then
            self:sortDataByFrequency(self.terms, book_text, "name")
        end
        -- Merge book_type
        if final_book_data.book_type then
            self.book_type = final_book_data.book_type
        end

        -- Segregate series_prior timeline items from current book timeline items
        local prior_timeline = {}
        local current_timeline = {}
        for _, ev in ipairs(self.timeline or {}) do
            if ev.source == "series_prior" then
                table.insert(prior_timeline, ev)
            else
                table.insert(current_timeline, ev)
            end
        end

        local toc = self.ui and self.ui.document and self.ui.document.getToc and self.ui.document:getToc() or {}
        local incoming_timeline = final_book_data.timeline or {}
        self:assignTimelinePages(incoming_timeline, toc, true)
        if self.filterOrphanTimelineEvents then
            incoming_timeline = self:filterOrphanTimelineEvents(incoming_timeline, toc)
        end

        for _, new_event in ipairs(incoming_timeline) do
            local found = false
            local new_norm = self:normalizeChapterName(new_event.chapter or "")
            for _, existing_event in ipairs(current_timeline) do
                local exist_norm = self:normalizeChapterName(existing_event.chapter or "")
                if new_norm == exist_norm and match_story(existing_event, new_event) then
                    if new_event.page and existing_event.page and
                       tonumber(new_event.page) == tonumber(existing_event.page) then
                        existing_event.event = new_event.event or existing_event.event
                        existing_event.chapter = new_event.chapter or existing_event.chapter
                        found = true
                        break
                    end
                end
            end
            if not found then table.insert(current_timeline, new_event) end
        end

        if self.filterOrphanTimelineEvents then
            current_timeline = self:filterOrphanTimelineEvents(current_timeline, toc)
        end

        self.timeline = {}
        for _, ev in ipairs(current_timeline) do table.insert(self.timeline, ev) end
        for _, ev in ipairs(prior_timeline) do table.insert(self.timeline, ev) end
        self:sortTimelineByTOC(self.timeline)
    else
        if is_anthology and current_story then
            local function mergeNonUpdateList(existing_list, new_list, desc_field)
                local kept = {}
                for _, item in ipairs(existing_list or {}) do
                    if not self:isEntityInCurrentStory(item, current_story) then
                        table.insert(kept, item)
                    end
                end
                for _, item in ipairs(new_list or {}) do
                    if desc_field and item[desc_field] and item[desc_field] ~= "" then
                        item.history = item.history or {
                            {
                                page = current_page,
                                chapter = chapter_title or "",
                                [desc_field] = item[desc_field],
                            }
                        }
                    end
                    table.insert(kept, item)
                end
                return kept
            end

            self.characters = mergeNonUpdateList(self.characters, final_book_data.characters, "description")
            self.historical_figures = mergeNonUpdateList(self.historical_figures, final_book_data.historical_figures, "biography")
            self.locations = mergeNonUpdateList(self.locations, final_book_data.locations, "description")
            self.terms = mergeNonUpdateList(self.terms, final_book_data.terms or {}, nil)

            local prior_timeline = {}
            local kept_timeline = {}
            for _, ev in ipairs(self.timeline or {}) do
                if ev.source == "series_prior" then
                    table.insert(prior_timeline, ev)
                elseif not self:isEntityInCurrentStory(ev, current_story) then
                    table.insert(kept_timeline, ev)
                end
            end

            local current_timeline = final_book_data.timeline or {}
            local toc = self.ui and self.ui.document and self.ui.document.getToc and self.ui.document:getToc() or {}
            self:assignTimelinePages(current_timeline, toc, true)
            if self.filterOrphanTimelineEvents then
                current_timeline = self:filterOrphanTimelineEvents(current_timeline, toc)
            end

            self.timeline = {}
            for _, ev in ipairs(kept_timeline) do table.insert(self.timeline, ev) end
            for _, ev in ipairs(current_timeline) do table.insert(self.timeline, ev) end
            for _, ev in ipairs(prior_timeline) do table.insert(self.timeline, ev) end
            self:sortTimelineByTOC(self.timeline)
            self.book_type = "anthology"
        else
            self.characters = final_book_data.characters
            for _, char in ipairs(self.characters or {}) do
                if char.description and char.description ~= "" then
                    char.history = char.history or {
                        {
                            page = current_page,
                            chapter = chapter_title or "",
                            description = char.description
                        }
                    }
                end
            end
            self.historical_figures = final_book_data.historical_figures
            for _, fig in ipairs(self.historical_figures or {}) do
                if fig.biography and fig.biography ~= "" then
                    fig.history = fig.history or {
                        {
                            page = current_page,
                            chapter = chapter_title or "",
                            biography = fig.biography
                        }
                    }
                end
            end
            self.locations = final_book_data.locations
            for _, loc in ipairs(self.locations or {}) do
                if loc.description and loc.description ~= "" then
                    loc.history = loc.history or {
                        {
                            page = current_page,
                            chapter = chapter_title or "",
                            description = loc.description
                        }
                    }
                end
            end
            self.terms = final_book_data.terms or {}
            self.book_type = final_book_data.book_type

            -- Preserve series_prior items when non-merge update/fetch overwrites current timeline
            local prior_timeline = {}
            for _, ev in ipairs(self.timeline or {}) do
                if ev.source == "series_prior" then
                    table.insert(prior_timeline, ev)
                end
            end

            local current_timeline = final_book_data.timeline or {}
            local toc = self.ui and self.ui.document and self.ui.document.getToc and self.ui.document:getToc() or {}
            self:assignTimelinePages(current_timeline, toc, true)
            if self.filterOrphanTimelineEvents then
                current_timeline = self:filterOrphanTimelineEvents(current_timeline, toc)
            end

            self.timeline = {}
            for _, ev in ipairs(current_timeline) do table.insert(self.timeline, ev) end
            for _, ev in ipairs(prior_timeline) do table.insert(self.timeline, ev) end
            self:sortTimelineByTOC(self.timeline)
        end
    end

    -- If we don't have author info in memory, check if the cache already has it
    if not self.author_info then
        if not self.cache_manager then self.cache_manager = require(plugin_path .. "xray_cachemanager"):new() end
        local doc_file = (self.ui and self.ui.document) and self.ui.document.file
        local existing = (doc_file and self.cache_manager:loadCache(doc_file)) or self.book_data
        if existing and existing.author_info then
            self.author_info = existing.author_info
        end
    end

    if not self.book_data then
        local doc_file = (self.ui and self.ui.document) and self.ui.document.file
        self.book_data = (doc_file and self.cache_manager:loadCache(doc_file)) or {}
    end
    local updated_data = self.book_data
    updated_data.book_title = title
    updated_data.author = author
    updated_data.characters = self.characters
    updated_data.historical_figures = self.historical_figures
    updated_data.locations = self.locations
    updated_data.terms = self.terms
    updated_data.book_type = self.book_type or updated_data.book_type
    updated_data.timeline = self.timeline
    updated_data.chapters_fetched = self.chapters_fetched or updated_data.chapters_fetched
    updated_data.author_info = self.author_info or updated_data.author_info
    updated_data.images = (self.images and #self.images > 0 and self.images) or updated_data.images or (self.book_data and self.book_data.images)
    updated_data.last_fetch_page = current_page
    if self.ui and self.ui.document and self.ui.document.getCurrentPos then
        local ok_pos, pos = pcall(function() return self.ui.document:getCurrentPos() end)
        if ok_pos and pos then updated_data.last_fetch_xpointer = pos end
    elseif self.ui and self.ui.rolling and self.ui.rolling.getCurrentPos then
        local ok_pos, pos = pcall(function() return self.ui.rolling:getCurrentPos() end)
        if ok_pos and pos then updated_data.last_fetch_xpointer = pos end
    end
    
    local s = self.ai_helper and self.ai_helper.settings or {}
    updated_data.timeline_event_len = s.timeline_event_len or 80

    if is_anthology and current_story then
        updated_data.story_fetch_state = updated_data.story_fetch_state or {}
        local s_state = updated_data.story_fetch_state[current_story.story_id] or {
            story_id = current_story.story_id,
            story_title = current_story.story_title,
        }
        s_state.story_id = current_story.story_id
        s_state.story_title = current_story.story_title
        s_state.last_fetch_page = current_page
        s_state.terms_fetched = true
        updated_data.story_fetch_state[current_story.story_id] = s_state
    end

    self.book_data = updated_data
    local doc_file = (self.ui and self.ui.document) and self.ui.document.file

    -- If book is part of a series, update series metadata and handle initial series context merge if needed
    if self.series_manager and (updated_data.series_slug or (self.ui and self.ui.document)) then
        pcall(function()
            local props = self.ui and self.ui.document and self.ui.document:getProps() or {}
            local series_info = self.series_manager:getSeriesInfo(updated_data, props, title, author)
            local slug = (series_info and series_info.slug) or updated_data.series_slug
            local index = series_info and series_info.index
            if slug and index then
                if series_info.has_explicit_index ~= false then
                    updated_data.series_index = index
                end
                if series_info.name and not updated_data.series then
                    updated_data.series = series_info.name
                end
                if slug and not updated_data.series_slug then
                    updated_data.series_slug = slug
                end

                -- Defer writing current book into the series file until close/suspend
                self:markSeriesSyncDirty(slug, index, title, author, doc_file, series_info.has_explicit_index)

                -- Check if series context needs to be loaded/merged
                local s_setting = self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.series_context_enabled
                local already_loaded = (self.series_context_loaded or updated_data.series_context_loaded)
                if is_update and already_loaded then
                    -- Normal background update: series context is already merged into this book's cache.
                    -- Skip reading the series file, scanning folders, and re-merging.
                    self.series_context_loaded = true
                    updated_data.series_context_loaded = true
                elseif s_setting ~= false and index > 1 then
                    -- Initial fetch or full non-update overwrite: check if all prior books are cached in SeriesCache
                    local cache_data = self.series_manager:loadSeriesCache(slug)
                    if cache_data and cache_data.books then
                        local all_priors_cached = true
                        local whole_priors = SeriesManager.wholeIndicesBefore(index)
                        for _, p_idx in ipairs(whole_priors) do
                            local b = cache_data.books[p_idx]
                            if not bookHasEntities(b, self.series_manager) then
                                all_priors_cached = false
                                break
                            end
                        end
                        if all_priors_cached then
                            local prior_indices = self.series_manager.getExpectedPriorIndices
                                and self.series_manager:getExpectedPriorIndices(series_info, cache_data.books, doc_file)
                                or whole_priors
                            for _, p_idx in ipairs(prior_indices) do
                                local b = cache_data.books[p_idx]
                                if not bookHasEntities(b, self.series_manager) then
                                    all_priors_cached = false
                                    break
                                end
                            end
                            if all_priors_cached then
                                self:log("XRayPlugin: Series: Post-fetch auto-restoring cached series context for " .. tostring(slug))
                                self:mergeSeriesContext(cache_data, series_info, book_text, true)
                            end
                        end
                    end
                end
            end
        end)
    end

    if not self.cache_manager then self.cache_manager = require(plugin_path .. "xray_cachemanager"):new() end
    local cache_saved = doc_file and self.cache_manager:asyncSaveCache(doc_file, updated_data)

    UIManager:scheduleIn(1, function()
        if self.destroyed or not self.ui or not self.ui.document then return end
        local reading_percent = 100
        if self.ui and self.ui.document and self.ui.document.getPageCount and current_page then
            local page_count = self.ui.document:getPageCount()
            if page_count and page_count > 0 then
                reading_percent = math.floor((current_page / page_count) * 100)
            end
        end
        local spoiler_setting = self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.spoiler_setting or "spoiler_free"
        if spoiler_setting == "full_book" then reading_percent = 100 end
        self:runPostFetchDuplicateCheck(title, author, reading_percent, is_silent, book_text)
    end)

    if is_silent then
        self:log(string.format("XRayPlugin: Silent merge complete - Chars: %d, Locs: %d, Events: %d, Cache: %s",
            #self.characters, #self.locations, #self.timeline,
            cache_saved and "saved" or "failed"))
    else
        local fetch_complete = self.loc:t("ai_fetch_complete_msg") or "AI Fetch Complete!"
        local cache_success = self.loc:t("cache_save_success") or "✓ Cache updated."
        local cache_fail = self.loc:t("cache_save_failed") or "✗ Cache failed."
        local label_chars = self.loc:t("entity_label_characters") or "Characters"
        local label_locs = self.loc:t("entity_label_locations") or "Locations"
        local label_timeline = self.loc:t("menu_timeline") or "Timeline"
        local summary = string.format("%s\n\n%s: %d\n%s: %d\n%s: %d\n\n%s", 
            fetch_complete,
            label_chars, #self.characters,
            label_locs, #self.locations,
            label_timeline, #self.timeline,
            cache_saved and cache_success or cache_fail)

        local success_dialog
        local ButtonDialog = require("ui/widget/buttondialog")
        success_dialog = ButtonDialog:new{ modal = true, title = (self.loc:t("fetch_successful") or "Fetch successful") .. "\n\n" .. summary, buttons = {{{ text = self.loc:t("ok"), callback = function() 
            UIManager:close(success_dialog) 
        end }}} }
        UIManager:show(success_dialog)
    end

end

function M:runPostFetchDuplicateCheck(title, author, reading_percent, is_silent, book_text)
    if self.destroyed then return end
    if not self.ui or not self.ui.document or not self.ui.getCurrentPage then
        self:log("XRayPlugin: Skipping duplicate check because the reader document is unavailable")
        return
    end
    if self._unit_scan_in_progress then
        self:log("XRayPlugin: Deferring duplicate check because unit scan is in progress")
        UIManager:scheduleIn(5, function()
            if self.destroyed or not self.ui or not self.ui.document then return end
            self:runPostFetchDuplicateCheck(title, author, reading_percent, is_silent, book_text)
        end)
        return
    end
    if not self.ai_helper or not self.ai_helper.hasApiKey or not self.ai_helper:hasApiKey() then return end
    if self.ai_helper.settings and self.ai_helper.settings.auto_dupe_check_enabled == false then return end

    local DataStorage = require("datastorage")
    local settings_xray_dir = DataStorage:getSettingsDir() .. "/xray"

    local is_anthology = self.isAnthologyMode and self:isAnthologyMode()
    local current_story = nil
    if is_anthology then
        current_story = self:getCurrentStory(self.ui:getCurrentPage())
    end

    -- Gather a small book text anchor for the spoiler guard.
    -- This is done once here and shared across both list checks.
    local dup_book_text
    if book_text and #book_text > 0 then
        dup_book_text = book_text:sub(-15000)
    else
        if not self.chapter_analyzer then
            self.chapter_analyzer = require(plugin_path .. "xray_chapteranalyzer"):new()
        end
        dup_book_text = self.chapter_analyzer:getTextForAnalysis(
            self.ui, 15000, nil, self.ui:getCurrentPage(), nil, nil, current_story)
    end

    local target_characters = self.characters or {}
    local target_locations = self.locations or {}
    if is_anthology then
        if self.buildDuplicateCandidates then
            target_characters = self:buildDuplicateCandidates(target_characters, current_story)
            target_locations = self:buildDuplicateCandidates(target_locations, current_story)
        elseif current_story then
            local c_filt = {}
            for _, c in ipairs(target_characters) do
                if self:isEntityInCurrentStory(c, current_story) then table.insert(c_filt, c) end
            end
            target_characters = c_filt

            local l_filt = {}
            for _, l in ipairs(target_locations) do
                if self:isEntityInCurrentStory(l, current_story) then table.insert(l_filt, l) end
            end
            target_locations = l_filt
        end
    end

    local scope_story_id = current_story and current_story.story_id or nil

    -- Run checks for characters and locations in sequence using async subprocesses
    local function checkListAsync(list, list_name, entity_label, on_done)
        if not list or #list < 2 then on_done(nil); return end
        
        local unique_id = tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))
        local result_file = settings_xray_dir .. "/dupe_res_" .. list_name .. "_" .. unique_id .. ".json"
        
        self:log("XRayPlugin: Starting async duplicate check for " .. list_name)
        local pid = self.ai_helper:findDuplicatesAsync(title, author, list, entity_label, reading_percent, result_file, dup_book_text, scope_story_id)
        if not pid then
            self:log("XRayPlugin: Failed to start async duplicate check for " .. list_name)
            on_done(nil)
            return
        end
        
        local poll_count = 0
        local max_polls = 150 -- 5 minutes at 2s intervals
        local function poll()
            if self.destroyed or not self.ui or not self.ui.document then
                pcall(function() os.remove(result_file) end)
                return
            end
            poll_count = poll_count + 1
            local data, p_err_code, p_err_msg = self.ai_helper:checkAsyncResult(result_file, pid)
            if data == nil then
                if poll_count < max_polls then
                    UIManager:scheduleIn(2, poll)
                else
                    self:log("XRayPlugin: Async duplicate check for " .. list_name .. " timed out")
                    pcall(function() os.remove(result_file) end)
                    on_done(nil)
                end
            elseif data == false then
                self:log("XRayPlugin: Async duplicate check for " .. list_name .. " failed: " .. tostring(p_err_msg))
                on_done(nil)
            else
                self:log("XRayPlugin: Async duplicate check for " .. list_name .. " succeeded")
                local pairs_found = data.duplicate_pairs or data.DuplicatePairs
                on_done(pairs_found)
            end
        end
        UIManager:scheduleIn(2, poll)
    end

    checkListAsync(target_characters, "characters",
        self.loc:t("entity_label_characters") or "characters",
        function(char_pairs)
            checkListAsync(target_locations, "locations",
                self.loc:t("entity_label_locations") or "locations",
                function(loc_pairs)
                    local has_chars = char_pairs and #char_pairs > 0
                    local has_locs  = loc_pairs  and #loc_pairs  > 0

                    if not has_chars and not has_locs then return end

                    self.pending_duplicate_review = {
                        story_id   = scope_story_id,
                        characters = has_chars and char_pairs or nil,
                        locations  = has_locs and loc_pairs or nil,
                    }
                    self:log("XRayPlugin: Stored " .. tostring(has_chars and #char_pairs or 0) .. " char and " .. tostring(has_locs and #loc_pairs or 0) .. " loc duplicate pairs for review (scope: " .. tostring(scope_story_id) .. ")")

                    if not is_silent then
                        UIManager:scheduleIn(0.5, function()
                            if self.destroyed or not self.ui or not self.ui.document then return end
                            if has_chars then
                                self.pending_duplicate_review.characters = nil
                                self:walkDuplicatePairs(self.characters, "characters", char_pairs)
                            elseif has_locs then
                                self.pending_duplicate_review.locations = nil
                                self:walkDuplicatePairs(self.locations, "locations", loc_pairs)
                            end
                        end)
                    end
                end
            )
        end
    )
end

function M:fetchMoreEntities(entity_type)
    require("ui/network/manager"):runWhenOnline(function() 
        if self.destroyed or not self.ui or not self.ui.document then return end
        local doc_file = self.ui.document.file
        if not doc_file then return end

        if self._active_ai_cancel or (self.ai_helper and self.ai_helper._async_child_pid) then
            self:cancelActiveAIRequest("Previous AI request replaced by user fetch")
        end

        if not self.ai_helper then
            local AIHelper = require(plugin_path .. "xray_aihelper")
            self.ai_helper = AIHelper
            self.ai_helper:init(self.path)
        end
        if not self.ai_helper:hasApiKey() then
            local ButtonDialog = require("ui/widget/buttondialog")
            local key_dlg
            key_dlg = ButtonDialog:new{
                modal = true,
                title = self.loc:t("error_no_api_key") or "API Key Required",
                buttons = {{{ text = self.loc:t("ok") or "OK", callback = function() if key_dlg then UIManager:close(key_dlg) end end }}}
            }
            UIManager:show(key_dlg)
            return
        end

        local props = self.ui.document:getProps() or {}
        local title = sanitizeMetadata(props.title)
        local author = sanitizeMetadata(props.authors)
        local current_page = self.ui:getCurrentPage()
        local reading_percent = math.floor((current_page / self.ui.document:getPageCount()) * 100)
        local spoiler_setting = self.ai_helper.settings and self.ai_helper.settings.spoiler_setting or "spoiler_free"
        
        if spoiler_setting == "full_book" then
            reading_percent = 100
        end
        
        local is_terms = (entity_type == "terms")
        local section_name = is_terms and "more_terms" or "more_characters"
        local dialog_title_text = is_terms
            and (self.loc:t("extracting_more_terms") or "Extracting additional terms...")
            or  (self.loc:t("extracting_more_characters") or "Extracting additional characters...")

        local menu_to_close = is_terms and self.terms_menu or self.char_menu

        local wait_msg
        local request_pid
        local result_file
        local is_cancelled = false
        local ButtonDialog = require("ui/widget/buttondialog")

        local function cancelActiveRequest(reason)
            if is_cancelled then return end
            is_cancelled = true
            if request_pid and self.ai_helper and self.ai_helper.cancelAsyncChild then
                self.ai_helper:cancelAsyncChild(request_pid)
            end
            if result_file then
                pcall(function() os.remove(result_file) end)
            end
            if wait_msg then
                local dlg = wait_msg
                wait_msg = nil
                dlg.tap_close_callback = nil
                UIManager:close(dlg)
            end
            if self._active_ai_dialog == wait_msg then self._active_ai_dialog = nil end
            if self._active_ai_cancel == cancelActiveRequest then self._active_ai_cancel = nil end
            self:log("XRayPlugin: " .. (reason or "Fetch more cancelled"))
        end

        wait_msg = ButtonDialog:new{
            modal = true,
            title = dialog_title_text .. "\n\n" .. title,
            tap_close_callback = function()
                cancelActiveRequest("Fetch cancelled by user")
            end,
            buttons = {{{
                text = self.loc:t("cancel") or "Cancel",
                is_enter_default = true,
                callback = function()
                    cancelActiveRequest("Fetch cancelled by user")
                end
            }}}
        }
        self._active_ai_dialog = wait_msg
        self._active_ai_cancel = cancelActiveRequest
        UIManager:show(wait_msg)
        
        UIManager:scheduleIn(0.5, function()
            if is_cancelled or self.destroyed or not self.ui or not self.ui.document then
                cancelActiveRequest("Fetch stopped because plugin was destroyed or document closed")
                return
            end
            if not self.chapter_analyzer then self.chapter_analyzer = require(plugin_path .. "xray_chapteranalyzer"):new() end
            
            -- EVEN SAMPLING: Divide the readable range into equal segments
            local current_page = self.ui:getCurrentPage()
            local is_anthology = self.isAnthologyMode and self:isAnthologyMode()
            local current_story = is_anthology and self:getCurrentStory(current_page) or nil

            local pages_per_sample = 20
            local chars_per_sample = 10000
            local num_samples = 6
            
            -- Track call count to shift windows on each invocation
            self.more_fetch_call_count = self.more_fetch_call_count or {}
            self.more_fetch_call_count[entity_type] = (self.more_fetch_call_count[entity_type] or 0) + 1
            local call_num = self.more_fetch_call_count[entity_type]
            local offset = (call_num - 1) * pages_per_sample
            self:log("XRayPlugin: More " .. entity_type .. " call #" .. call_num .. " (offset: " .. offset .. " pages)")
            
            -- Divide readable range into equal segments
            local readable_start = 1
            local readable_end = math.max(1, current_page)
            if current_story then
                readable_start = current_story.start_page or 1
                readable_end = math.min(current_page, current_story.end_page or current_page)
            end
            local readable_pages = math.max(1, readable_end - readable_start + 1)
            local segment_size = math.floor(readable_pages / num_samples)
            if segment_size < pages_per_sample then segment_size = pages_per_sample end
            
            local text_parts = {}
            for i = 0, num_samples - 1 do
                local segment_start = readable_start + (i * segment_size)
                local sample_start = math.min(segment_start + offset, readable_end - pages_per_sample)
                sample_start = math.max(readable_start, sample_start)
                
                -- Wrap around within the segment if the offset pushes past the segment boundary
                local segment_end = segment_start + segment_size
                if sample_start >= segment_end and i < num_samples - 1 then
                    sample_start = segment_start + ((offset) % segment_size)
                    sample_start = math.max(readable_start, math.min(sample_start, readable_end - pages_per_sample))
                end
                
                if sample_start <= readable_end then
                    local end_page = math.min(sample_start + pages_per_sample, readable_end)
                    local sample = self.chapter_analyzer:getTextFromPageRange(self.ui, sample_start, end_page, chars_per_sample)
                    if sample and #sample > 100 then
                        table.insert(text_parts, "[SECTION " .. (i + 1) .. "]\n" .. sample)
                        self:log("XRayPlugin: More " .. entity_type .. " sample " .. (i + 1) .. " pages " .. sample_start .. "-" .. end_page .. ": " .. #sample .. " chars")
                    end
                end
            end
            local book_text = table.concat(text_parts, "\n\n---\n\n")
            
            local exclude_list = {}
            local source_list = is_terms and (self.terms or {}) or (self.characters or {})
            for _, item in ipairs(source_list) do
                if item.name then
                    if not is_anthology or not current_story or self:isEntityInCurrentStory(item, current_story) then
                        table.insert(exclude_list, item.name)
                    end
                end
            end
            
            local context = { 
                reading_percent = reading_percent, 
                spoiler_free = reading_percent < 100,
                filename = doc_file:match("([^/\\]+)$"), 
                series = props.series or props.Series, 
                book_text = book_text,
                exclude_characters = not is_terms and table.concat(exclude_list, ", ") or nil,
                exclude_terms = is_terms and table.concat(exclude_list, ", ") or nil,
                story_title = current_story and current_story.story_title or nil,
                story_id = current_story and current_story.story_id or nil,
            }
            
            local pid, res_file_or_err, err_msg = self.ai_helper:startAIRequest(title, author, context, section_name)
            if not pid then
                local err_code = res_file_or_err
                if wait_msg then
                    local dlg = wait_msg
                    wait_msg = nil
                    dlg.tap_close_callback = nil
                    UIManager:close(dlg)
                end
                if self._active_ai_dialog == wait_msg then self._active_ai_dialog = nil end
                if self._active_ai_cancel == cancelActiveRequest then self._active_ai_cancel = nil end

                local friendly_title, friendly_text = utils:getFriendlyError(err_code, err_msg, self.loc)
                local display_msg = friendly_title or (self.loc:t("error") or "Error")
                if friendly_text and friendly_text ~= "" then
                    display_msg = display_msg .. "\n\n" .. friendly_text
                end
                local err_dlg
                err_dlg = ButtonDialog:new{
                    modal = true,
                    title = display_msg,
                    buttons = {{{ text = self.loc:t("ok") or "OK", callback = function() if err_dlg then UIManager:close(err_dlg) end end }}}
                }
                UIManager:show(err_dlg)
                return
            end
            request_pid = pid
            result_file = res_file_or_err

            local request_started_at = os.time()
            local request_timeout = 600
            local function poll()
                if is_cancelled then return end
                if self.destroyed or not self.ui or not self.ui.document then
                    cancelActiveRequest("Fetch stopped because plugin was destroyed or document closed")
                    return
                end
                if os.time() - request_started_at > request_timeout then
                    cancelActiveRequest("Fetch timed out")
                    local to_dlg
                    local to_title = self.loc:t("error") or "Error"
                    local to_text = self.loc:t("error_timeout") or "Request timed out"
                    to_dlg = ButtonDialog:new{
                        modal = true,
                        title = to_title .. "\n\n" .. to_text,
                        text = to_text,
                        buttons = {{{ text = self.loc:t("ok") or "OK", callback = function() if to_dlg then UIManager:close(to_dlg) end end }}}
                    }
                    UIManager:show(to_dlg)
                    return
                end
                local res, err_code, err_msg = self.ai_helper:checkAsyncResult(result_file, request_pid)
                if is_cancelled then return end
                if res == nil then
                    UIManager:scheduleIn(1, poll)
                else
                    if is_cancelled then return end
                    if self._active_ai_dialog == wait_msg then self._active_ai_dialog = nil end
                    if self._active_ai_cancel == cancelActiveRequest then self._active_ai_cancel = nil end
                    if wait_msg then
                        local dlg = wait_msg
                        wait_msg = nil
                        dlg.tap_close_callback = nil
                        UIManager:close(dlg)
                    end
                    pcall(function() os.remove(result_file) end)

                    if is_cancelled then return end

                    if not res or type(res) ~= "table" then
                        if is_cancelled then return end
                        local utils = require(plugin_path .. "xray_utils")
                        local err_title, text = utils:getFriendlyError(err_code, err_msg, self.loc)
                        local display_msg = err_title or "Error"
                        if text and text ~= "" then
                            display_msg = display_msg .. "\n\n" .. text
                        end
                        local err_box
                        err_box = ButtonDialog:new{
                            modal = true,
                            title = display_msg,
                            buttons = {{{ text = self.loc:t("ok") or "OK", callback = function() if err_box then UIManager:close(err_box) end end }}}
                        }
                        UIManager:show(err_box)
                        return
                    end

                    local items = is_terms and (res.terms or (not res.terms and res[1] and res)) or (res.characters or (not res.characters and res[1] and res))
                    if not items then
                        if is_cancelled then return end
                        local utils = require(plugin_path .. "xray_utils")
                        local err_title, text = utils:getFriendlyError(err_code, err_msg, self.loc)
                        local display_msg = err_title or "Error"
                        if text and text ~= "" then
                            display_msg = display_msg .. "\n\n" .. text
                        end
                        local err_box
                        err_box = ButtonDialog:new{
                            modal = true,
                            title = display_msg,
                            buttons = {{{ text = self.loc:t("ok") or "OK", callback = function() if err_box then UIManager:close(err_box) end end }}}
                        }
                        UIManager:show(err_box)
                        return
                    end

                    local new_count = 0
                    local target_list = is_terms and (self.terms or {}) or (self.characters or {})
                    for _, new_item in ipairs(items) do
                        if new_item.name then
                            if is_anthology and current_story then
                                new_item.story_id = new_item.story_id or current_story.story_id
                                new_item.story_title = new_item.story_title or current_story.story_title
                            end
                            local found = false
                            for _, existing_item in ipairs(target_list) do
                                local name_match = (existing_item.name or ""):lower() == (new_item.name or ""):lower()
                                local story_match = true
                                if is_anthology and current_story then
                                    local ex_st = existing_item.story_id or (self.resolveEntityStory and self:resolveEntityStory(existing_item))
                                    story_match = (ex_st == (new_item.story_id or current_story.story_id))
                                end
                                if name_match and story_match then
                                    found = true
                                    break
                                end
                            end
                            if not found then
                                table.insert(target_list, new_item)
                                new_count = new_count + 1
                            end
                        end
                    end
                    target_list = self:deduplicateByName(target_list, "name")
                    if is_terms then self.terms = target_list else self.characters = target_list end

                    -- Re-sort by frequency based on the newly extracted samples
                    if book_text and #book_text > 0 then
                        if is_terms then
                            self:sortDataByFrequency(self.terms, book_text, "name")
                        else
                            self:sortDataByFrequency(self.characters, book_text, "name")
                        end
                    end

                    -- Save to cache
                    if not self.cache_manager then self.cache_manager = require(plugin_path .. "xray_cachemanager"):new() end
                    if not self.book_data then
                        self.book_data = self.cache_manager:loadCache(doc_file) or {}
                    end
                    local updated_data = self.book_data
                    updated_data.book_title = title
                    updated_data.author = author
                    updated_data.characters = self.characters
                    updated_data.historical_figures = self.historical_figures
                    updated_data.locations = self.locations
                    updated_data.terms = self.terms or updated_data.terms
                    updated_data.book_type = self.book_type or updated_data.book_type
                    updated_data.timeline = self.timeline or updated_data.timeline
                    updated_data.author_info = self.author_info or updated_data.author_info
                    updated_data.images = (self.images and #self.images > 0 and self.images) or updated_data.images or (self.book_data and self.book_data.images)

                    self.cache_manager:asyncSaveCache(doc_file, updated_data)

                    if not is_terms then
                        local cur_p = self.ui and self.ui.getCurrentPage and self.ui:getCurrentPage() or 1
                        local tot_p = self.ui and self.ui.document and self.ui.document.getPageCount and self.ui.document:getPageCount() or 1
                        local r_pct = tot_p and tot_p > 0 and math.floor((cur_p / tot_p) * 100) or 100
                        local sp_set = self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.spoiler_setting or "spoiler_free"
                        if sp_set == "full_book" then r_pct = 100 end

                        UIManager:scheduleIn(0.5, function()
                            if self.destroyed or not self.ui or not self.ui.document then return end
                            self:runPostFetchDuplicateCheck(title, author, r_pct, false)
                        end)
                    end

                    local added_msg = is_terms
                        and self.loc:t("msg_added_terms", new_count)
                        or  self.loc:t("msg_added_characters", new_count)
                    UIManager:show(InfoMessage:new{ text = added_msg, timeout = 3 })

                    if menu_to_close then
                        UIManager:close(menu_to_close)
                    end
                    if is_terms then
                        self.terms_menu = nil
                        self:showTerms()
                    else
                        self.char_menu = nil
                        self:showCharacters()
                    end
                end
            end
            UIManager:scheduleIn(1, poll)
        end)
    end)
end

function M:fetchMoreCharacters()
    return self:fetchMoreEntities("characters")
end

function M:fetchMoreTerms()
    return self:fetchMoreEntities("terms")
end

function M:fetchAuthorInfo()
    if self.destroyed or not self.ui or not self.ui.document then return end
    local doc_file = self.ui.document.file
    if not doc_file then return end

    if self._active_ai_cancel or (self.ai_helper and self.ai_helper._async_child_pid) then
        self:cancelActiveAIRequest("Previous AI request replaced by author info fetch")
    end

    if not self.ai_helper then
        local AIHelper = require(plugin_path .. "xray_aihelper")
        self.ai_helper = AIHelper
        self.ai_helper:init(self.path)
    end
    if not self.ai_helper:hasApiKey() then
        local ButtonDialog = require("ui/widget/buttondialog")
        local key_dlg
        key_dlg = ButtonDialog:new{
            modal = true,
            title = self.loc:t("error_no_api_key") or "API Key Required",
            buttons = {{{ text = self.loc:t("ok") or "OK", callback = function() if key_dlg then UIManager:close(key_dlg) end end }}}
        }
        UIManager:show(key_dlg)
        return
    end

    local props = self.ui.document:getProps() or {}
    local title = sanitizeMetadata(props.title)
    local author = sanitizeMetadata(props.authors)
    local wait_msg
    local request_pid
    local result_file
    local is_cancelled = false
    local ButtonDialog = require("ui/widget/buttondialog")

    local function cancelActiveRequest(reason)
        if is_cancelled then return end
        is_cancelled = true
        if request_pid and self.ai_helper and self.ai_helper.cancelAsyncChild then
            self.ai_helper:cancelAsyncChild(request_pid)
        end
        if result_file then
            pcall(function() os.remove(result_file) end)
        end
        if wait_msg then
            local dlg = wait_msg
            wait_msg = nil
            dlg.tap_close_callback = nil
            UIManager:close(dlg)
        end
        if self._active_ai_dialog == wait_msg then self._active_ai_dialog = nil end
        if self._active_ai_cancel == cancelActiveRequest then self._active_ai_cancel = nil end
        self:log("XRayPlugin: " .. (reason or "Author fetch cancelled"))
    end

    wait_msg = ButtonDialog:new{
        modal = true,
        title = (self.loc:t("fetching_author", "AI") or "Fetching Author...") .. "\n\n" .. title .. " - " .. author,
        tap_close_callback = function()
            cancelActiveRequest("Author fetch cancelled by user")
        end,
        buttons = {{{
            text = self.loc:t("cancel") or "Cancel",
            is_enter_default = true,
            callback = function()
                cancelActiveRequest("Author fetch cancelled by user")
            end
        }}}
    }
    self._active_ai_dialog = wait_msg
    self._active_ai_cancel = cancelActiveRequest
    UIManager:show(wait_msg)

    UIManager:scheduleIn(0.5, function()
        if is_cancelled or self.destroyed or not self.ui or not self.ui.document then
            cancelActiveRequest("Author fetch stopped because plugin was destroyed or document closed")
            return
        end
        
        if not self.chapter_analyzer then
            local ChapterAnalyzer = require(plugin_path .. "xray_chapteranalyzer")
            self.chapter_analyzer = ChapterAnalyzer:new()
        end
        local book_text = self.chapter_analyzer:getTextForAnalysis(self.ui, 1000, nil, self.ui:getCurrentPage())
        local context = { book_text = book_text }
        
        local pid, res_file_or_err, err_msg = self.ai_helper:startAIRequest(title, author, context, "author_only")
        if not pid then
            local err_code = res_file_or_err
            if wait_msg then
                local dlg = wait_msg
                wait_msg = nil
                dlg.tap_close_callback = nil
                UIManager:close(dlg)
            end
            if self._active_ai_dialog == wait_msg then self._active_ai_dialog = nil end
            if self._active_ai_cancel == cancelActiveRequest then self._active_ai_cancel = nil end

            local friendly_title, friendly_text = utils:getFriendlyError(err_code, err_msg, self.loc)
            local display_msg = friendly_title or (self.loc:t("error") or "Error")
            if friendly_text and friendly_text ~= "" then
                display_msg = display_msg .. "\n\n" .. friendly_text
            end
            local err_dlg
            err_dlg = ButtonDialog:new{
                modal = true,
                title = display_msg,
                buttons = {{{ text = self.loc:t("ok") or "OK", callback = function() if err_dlg then UIManager:close(err_dlg) end end }}}
            }
            UIManager:show(err_dlg)
            return
        end
        request_pid = pid
        result_file = res_file_or_err

        local request_started_at = os.time()
        local request_timeout = 600
        local function poll()
            if is_cancelled then return end
            if self.destroyed or not self.ui or not self.ui.document then
                cancelActiveRequest("Author fetch stopped because plugin was destroyed or document closed")
                return
            end
            if os.time() - request_started_at > request_timeout then
                cancelActiveRequest("Author fetch timed out")
                local to_dlg
                local to_title = self.loc:t("error") or "Error"
                local to_text = self.loc:t("error_timeout") or "Request timed out"
                to_dlg = ButtonDialog:new{
                    modal = true,
                    title = to_title .. "\n\n" .. to_text,
                    text = to_text,
                    buttons = {{{ text = self.loc:t("ok") or "OK", callback = function() if to_dlg then UIManager:close(to_dlg) end end }}}
                }
                UIManager:show(to_dlg)
                return
            end
            local res, err_code, err_msg = self.ai_helper:checkAsyncResult(result_file, request_pid)
            if is_cancelled then return end
            if res == nil then
                UIManager:scheduleIn(1, poll)
            else
                if is_cancelled then return end
                if self._active_ai_dialog == wait_msg then self._active_ai_dialog = nil end
                if self._active_ai_cancel == cancelActiveRequest then self._active_ai_cancel = nil end
                if wait_msg then
                    local dlg = wait_msg
                    wait_msg = nil
                    dlg.tap_close_callback = nil
                    UIManager:close(dlg)
                end
                pcall(function() os.remove(result_file) end)

                if is_cancelled then return end

                local author_data = (type(res) == "table" and (res.author_info or res)) or nil
                if not author_data or not (author_data.author or author_data.name or author_data.author_bio or author_data.description) then
                    if is_cancelled then return end
                    local utils = require(plugin_path .. "xray_utils")
                    local err_title, text = utils:getFriendlyError(err_code, err_msg, self.loc)
                    local display_msg = err_title or "Error"
                    if text and text ~= "" then
                        display_msg = display_msg .. "\n\n" .. text
                    end
                    local err_box
                    err_box = ButtonDialog:new{
                        modal = true,
                        title = display_msg,
                        buttons = {{{ text = self.loc:t("ok") or "OK", callback = function() if err_box then UIManager:close(err_box) end end }}}
                    }
                    UIManager:show(err_box)
                    return
                end

                self.author_info = { 
                    name = sanitizeMetadata(author_data.author or author_data.name or author), 
                    description = sanitizeMetadata(author_data.author_bio or author_data.description or self.loc:t("msg_no_bio") or "No biography available."), 
                    birthDate = sanitizeMetadata(author_data.author_birth or author_data.birthDate or "---"), 
                    deathDate = sanitizeMetadata(author_data.author_death or author_data.deathDate or "---") 
                }
                if not self.cache_manager then self.cache_manager = require(plugin_path .. "xray_cachemanager"):new() end
                if not self.book_data then
                    self.book_data = self.cache_manager:loadCache(doc_file) or {}
                end
                local cache = self.book_data
                cache.author_info = self.author_info
                cache.author = self.author_info.name
                cache.author_bio = self.author_info.description
                cache.author_birth = self.author_info.birthDate
                cache.author_death = self.author_info.deathDate
                
                -- Store book_type if AI detected it during author fetch
                if author_data.book_type then
                    cache.book_type = author_data.book_type
                    self.book_type = author_data.book_type
                end
                cache.images = (self.images and #self.images > 0 and self.images) or cache.images or (self.book_data and self.book_data.images)
                
                self.cache_manager:asyncSaveCache(doc_file, cache)
                self:showAuthorInfo()
            end
        end
        UIManager:scheduleIn(1, poll)
    end)
end

function M:checkWeeklyUpdate()
    if not self.ai_helper or not self.ai_helper.settings then return end
    
    local last_check = self.ai_helper.settings.last_update_check or 0
    local now = os.time()
    local week_seconds = 7 * 24 * 60 * 60
    
    if (now - last_check) > week_seconds then
        local NetworkMgr = require("ui/network/manager")
        if NetworkMgr:isConnected() and NetworkMgr:isOnline() then
            self:log("XRayPlugin: Triggering weekly silent update check")
            self.ai_helper:saveSettings({ last_update_check = now })
            local updater = require(plugin_path .. "xray_updater")
            updater.checkSilentForUpdates(self.loc, self.ai_helper.settings.beta_channel_enabled)
        else
            self:log("XRayPlugin: Skipping weekly update check (offline)")
        end
    end
end

function M:mergeSeriesContext(cache_data, series_info, book_text, skip_save)
    if not cache_data or not series_info then return end

    self.characters = self.characters or {}
    self.locations = self.locations or {}
    self.terms = self.terms or {}
    self.timeline = self.timeline or {}

    local function filterPrior(tbl)
        local filtered = {}
        for _, item in ipairs(tbl or {}) do
            if item and item.source ~= "series_prior" then
                table.insert(filtered, item)
            end
        end
        return filtered
    end

    self.characters = filterPrior(self.characters)
    self.locations = filterPrior(self.locations)
    self.terms = filterPrior(self.terms)
    self.timeline = filterPrior(self.timeline)

    local doc_file = self.ui and self.ui.document and self.ui.document.file
    local props = self.ui and self.ui.document and self.ui.document.getProps and self.ui.document:getProps() or {}
    local cur_title = props.title or (self.book_data and (self.book_data.book_title or self.book_data.title))

    for _, idx in ipairs(SeriesManager.priorIndicesIn(cache_data.books, series_info.index or 1)) do
        local book_path_for_idx = cache_data.book_paths and cache_data.book_paths[idx]
        local is_self = (doc_file and book_path_for_idx and doc_file == book_path_for_idx)
        local book_data = cache_data.books and cache_data.books[idx]
        if book_data and not is_self and (not cur_title or not book_data.title or book_data.title:lower() ~= cur_title:lower()) then
            for _, new_char in ipairs(book_data.characters or {}) do
                if new_char and new_char.name and new_char.name ~= "" then
                    local found = false
                    local lower_name = new_char.name:lower()
                    for _, existing_char in ipairs(self.characters) do
                        if existing_char and existing_char.name then
                            local matches = false
                            if existing_char.name:lower() == lower_name then
                                matches = true
                            else
                                for _, alias in ipairs(existing_char.aliases or {}) do
                                    if type(alias) == "string" and alias:lower() == lower_name then
                                        matches = true
                                        break
                                    end
                                end
                            end
                            
                            if matches then
                                found = true
                                existing_char.is_series = true
                                existing_char.from_series = true
                                local prefix = string.format("[From Book %s] ", SeriesManager.formatIndex(idx))
                                local clean_desc = (new_char.description or ""):gsub("^%[From Book [%d%.]+%]%s*", "")
                                if clean_desc ~= "" then
                                    local exist_desc = existing_char.description or ""
                                    if not exist_desc:find(prefix, 1, true) then
                                        if exist_desc ~= "" then
                                            existing_char.description = exist_desc .. "\n\n" .. prefix .. clean_desc
                                        else
                                            existing_char.description = prefix .. clean_desc
                                        end
                                    end
                                    existing_char.description = SeriesManager.reorderSeriesDescription(existing_char.description)
                                end
                                break
                            end
                        end
                    end
                    
                    if not found then
                        local char_copy = {}
                        for k, v in pairs(new_char) do char_copy[k] = v end
                        char_copy.source = "series_prior"
                        char_copy.is_series = true
                        char_copy.from_series = true
                        char_copy.source_book = idx
                        char_copy.sort_order = 10000 + idx * 1000 + (tonumber(char_copy.sort_order) or #self.characters)
                        table.insert(self.characters, char_copy)
                    end
                end
            end

            for _, new_loc in ipairs(book_data.locations or {}) do
                if new_loc and new_loc.name and new_loc.name ~= "" then
                    local found = false
                    local lower_name = new_loc.name:lower()
                    for _, existing_loc in ipairs(self.locations) do
                        if existing_loc and existing_loc.name then
                            if existing_loc.name:lower() == lower_name then
                                found = true
                                existing_loc.is_series = true
                                existing_loc.from_series = true
                                local prefix = string.format("[From Book %s] ", SeriesManager.formatIndex(idx))
                                local clean_desc = (new_loc.description or ""):gsub("^%[From Book [%d%.]+%]%s*", "")
                                if clean_desc ~= "" then
                                    local exist_desc = existing_loc.description or ""
                                    if not exist_desc:find(prefix, 1, true) then
                                        if exist_desc ~= "" then
                                            existing_loc.description = exist_desc .. "\n\n" .. prefix .. clean_desc
                                        else
                                            existing_loc.description = prefix .. clean_desc
                                        end
                                    end
                                    existing_loc.description = SeriesManager.reorderSeriesDescription(existing_loc.description)
                                end
                                break
                            end
                        end
                    end
                    if not found then
                        local loc_copy = {}
                        for k, v in pairs(new_loc) do loc_copy[k] = v end
                        loc_copy.source = "series_prior"
                        loc_copy.is_series = true
                        loc_copy.from_series = true
                        loc_copy.source_book = idx
                        table.insert(self.locations, loc_copy)
                    end
                end
            end

            for _, new_term in ipairs(book_data.terms or {}) do
                if new_term and new_term.name and new_term.name ~= "" then
                    local found = false
                    local lower_name = new_term.name:lower()
                    for _, existing_term in ipairs(self.terms) do
                        if existing_term and existing_term.name then
                            if existing_term.name:lower() == lower_name then
                                found = true
                                existing_term.is_series = true
                                existing_term.from_series = true
                                local prefix = string.format("[From Book %s] ", SeriesManager.formatIndex(idx))
                                local clean_def = (new_term.definition or ""):gsub("^%[From Book [%d%.]+%]%s*", "")
                                if clean_def ~= "" then
                                    local exist_def = existing_term.definition or ""
                                    if not exist_def:find(prefix, 1, true) then
                                        if exist_def ~= "" then
                                            existing_term.definition = exist_def .. "\n\n" .. prefix .. clean_def
                                        else
                                            existing_term.definition = prefix .. clean_def
                                        end
                                    end
                                    existing_term.definition = SeriesManager.reorderSeriesDescription(existing_term.definition)
                                end
                                break
                            end
                        end
                    end
                    if not found then
                        local term_copy = {}
                        for k, v in pairs(new_term) do term_copy[k] = v end
                        term_copy.source = "series_prior"
                        term_copy.is_series = true
                        term_copy.from_series = true
                        term_copy.source_book = idx
                        table.insert(self.terms, term_copy)
                    end
                end
            end

            local events = {}
            for _, new_event in ipairs(book_data.timeline or {}) do
                if new_event and new_event.event and new_event.event ~= "" then
                    table.insert(events, new_event.event)
                end
            end
            if #events > 0 then
                local book_title = book_data.title or (cache_data.books and cache_data.books[idx] and cache_data.books[idx].title) or ""
                local label
                if book_title and book_title ~= "" then
                    label = string.format("[Book %s: %s]", SeriesManager.formatIndex(idx), book_title)
                else
                    label = string.format("[Book %s]", SeriesManager.formatIndex(idx))
                end
                local consolidated_event = table.concat(events, "\n\n")
                local ev_copy = {
                    chapter = label,
                    event = consolidated_event,
                    page = -1000 + idx,
                    source = "series_prior",
                    source_book = idx
                }
                table.insert(self.timeline, ev_copy)
            end
        end
    end

    local toc = self.ui and self.ui.document and self.ui.document.getToc and utils:flattenTOC(self.ui.document:getToc()) or {}
    self:assignTimelinePages(self.timeline, toc, true)
    if self.filterOrphanTimelineEvents then
        self.timeline = self:filterOrphanTimelineEvents(self.timeline, toc)
    end
    self:sortTimelineByTOC(self.timeline)

    -- Re-sort characters by frequency against current book text if provided
    local text_for_sort = book_text or self.book_text or ""
    if self.characters and #self.characters > 0 and text_for_sort ~= "" then
        self:sortDataByFrequency(self.characters, text_for_sort, "name")
    end

    self.series_context_loaded = true
    if not skip_save then
        if not self.cache_manager then
            self.cache_manager = require(plugin_path .. "xray_cachemanager"):new()
        end
        local book_path = self.ui and self.ui.document and self.ui.document.file
        if book_path then
            if not self.book_data then
                self.book_data = self.cache_manager:loadCache(book_path) or {}
            end
            local cache = self.book_data
            cache.series_context_loaded = true
            cache.series_slug = series_info.slug
            if series_info.index then
                cache.series_index = series_info.index
            end
            if series_info.name then
                cache.series = series_info.name
            end
            cache.characters = self.characters
            cache.locations = self.locations
            cache.terms = self.terms
            cache.timeline = self.timeline
            cache.images = (self.images and #self.images > 0 and self.images) or cache.images or (self.book_data and self.book_data.images)
            self.cache_manager:asyncSaveCache(book_path, cache)
            self.book_data = cache
        end
    end
end

function M:fetchSeriesContext(is_silent, init_wait_dialog, cancel_ref)
    if self.flushSeriesSync then
        self:flushSeriesSync()
    end

    local function closeInitWait()
        if init_wait_dialog then
            UIManager:close(init_wait_dialog)
            init_wait_dialog = nil
        end
    end

    if cancel_ref and cancel_ref.cancelled then
        self:log("XRayPlugin: Series: fetchSeriesContext early exit: cancel_ref is cancelled")
        closeInitWait()
        return
    end

    if not self.ui or not self.ui.document then
        self:log("XRayPlugin: Series: fetchSeriesContext called with no document/ui, aborting")
        closeInitWait()
        return
    end

    if not self.ai_helper or not self.ai_helper.settings or not self.ai_helper.settings.series_context_enabled then
        self:log("XRayPlugin: Series: fetchSeriesContext early exit: setting series_context_enabled is false or nil")
        closeInitWait()
        return
    end

    local props = self.ui.document:getProps() or {}
    local title = sanitizeMetadata(props.title)
    local author = sanitizeMetadata(props.authors)

    self:log("XRayPlugin: Series: fetchSeriesContext starting for: title=" .. tostring(title) .. ", author=" .. tostring(author))

    if init_wait_dialog and self.ai_helper then self.ai_helper:setTrapWidget(init_wait_dialog) end
    local series_info = (self.series_manager and self.series_manager.getSeriesInfo and self.series_manager:getSeriesInfo(self.book_data, props, title, author, self.ai_helper))
        or (self.series_manager and self.series_manager.detectSeries and self.series_manager:detectSeries(props, title, author, self.ai_helper))
    if init_wait_dialog and self.ai_helper then self.ai_helper:resetTrapWidget() end
    if cancel_ref and cancel_ref.cancelled then
        self:log("XRayPlugin: Series: fetchSeriesContext cancelled after detectSeries")
        closeInitWait()
        return
    end

    if not series_info or not series_info.name or not series_info.index or series_info.index <= 1 then
        self:log("XRayPlugin: Series: No series detected or current book is the first one in the series. series_info=" .. (series_info and ("name=" .. tostring(series_info.name) .. ", index=" .. tostring(series_info.index)) or "nil"))
        closeInitWait()
        if not is_silent then
            UIManager:show(InfoMessage:new{
                text = self.loc:t("series_no_prior_detected") or "No prior books detected for this series.",
                timeout = 5
            })
        end
        return
    end

    local slug = series_info.slug
    self:log("XRayPlugin: Series: Detected series=" .. series_info.name .. ", index=" .. tostring(series_info.index) .. ", slug=" .. tostring(slug))

    local cache_data = self.series_manager:loadSeriesCache(slug) or { books = {} }
    cache_data.books = cache_data.books or {}

    if init_wait_dialog and self.ai_helper then self.ai_helper:setTrapWidget(init_wait_dialog) end
    local doc_file = self.ui and self.ui.document and self.ui.document.file
    local prior_books = self.series_manager:getPriorBookList(series_info, author, self.ai_helper, doc_file)
    if init_wait_dialog and self.ai_helper then self.ai_helper:resetTrapWidget() end
    if cancel_ref and cancel_ref.cancelled then
        self:log("XRayPlugin: Series: fetchSeriesContext cancelled after getPriorBookList")
        closeInitWait()
        return
    end

    if #prior_books == 0 then
        self:log("XRayPlugin: Series: getPriorBookList returned empty list, using generated placeholders")
        for _, i in ipairs(SeriesManager.wholeIndicesBefore(series_info.index)) do
            table.insert(prior_books, {
                index = i,
                title = string.format("%s (Book %d)", series_info.name, i),
                author = author or "Unknown Author"
            })
        end
    else
        self:log("XRayPlugin: Series: getPriorBookList returned " .. tostring(#prior_books) .. " prior books")
    end

    local missing_books = {}
    local books_needing_timeline_summary = {}

    for _, book in ipairs(prior_books) do
        local idx = book.index
        local cached_book = cache_data.books and cache_data.books[idx]

        -- If missing, or roster stub, or missing entities, or from LLM: check local device storage first!
        local has_entities = bookHasEntities(cached_book, self.series_manager)
        if not cached_book or not has_entities or cached_book.source ~= "local_xray" then
            local check_path = book.path or (cache_data.book_paths and cache_data.book_paths[idx]) or doc_file
            local local_book = self.series_manager and self.series_manager.findLocalBookXRay and self.series_manager:findLocalBookXRay(series_info, idx, check_path, book.title, self.cache_manager)
            if bookHasEntities(local_book, self.series_manager) then
                cached_book = local_book
                cache_data.books[idx] = local_book
                has_entities = true
                self:log("XRayPlugin: Series: Found local X-Ray data on device for Book " .. tostring(idx) .. ": " .. tostring(book.title))
            end
        end

        if cached_book and has_entities then
            self:log("XRayPlugin: Series: Cache HIT for book index " .. tostring(idx) .. " (" .. (cached_book.source or "cached") .. "): " .. tostring(book.title))
            if cached_book.source == "local_xray" and cached_book.timeline and #cached_book.timeline > 1 and not cached_book.timeline_summarized then
                table.insert(books_needing_timeline_summary, { index = idx, book = cached_book })
            end
        else
            self:log("XRayPlugin: Series: Cache MISS for book index " .. tostring(idx) .. ": " .. tostring(book.title))
            table.insert(missing_books, book)
        end
    end

    if #missing_books == 0 and #books_needing_timeline_summary == 0 then
        self:log("XRayPlugin: Series: All prior books are already cached. Merging context immediately.")
        closeInitWait()
        self:mergeSeriesContext(cache_data, series_info)
        if not is_silent then
            local count = #prior_books
            local loaded_msg = self.loc:t("series_context_loaded", count)
            UIManager:show(InfoMessage:new{
                text = loaded_msg,
                timeout = 5
            })
        end
        return
    end

    local NetworkMgr = require("ui/network/manager")
    local is_online = NetworkMgr and NetworkMgr.isOnline and NetworkMgr:isOnline()
    if #missing_books == 0 and not is_online then
        self:log("XRayPlugin: Series: Device offline. Merging local series context with raw chapter timeline events.")
        closeInitWait()
        self:mergeSeriesContext(cache_data, series_info)
        if not is_silent then
            local count = #prior_books
            local loaded_msg = self.loc:t("series_context_loaded", count)
            UIManager:show(InfoMessage:new{
                text = loaded_msg,
                timeout = 5
            })
        end
        return
    end

    local total_tasks = #books_needing_timeline_summary + #missing_books
    self:log("XRayPlugin: Series: Needs " .. tostring(#books_needing_timeline_summary) .. " timeline summaries and " .. tostring(#missing_books) .. " AI book fetches. Running when online.")

    NetworkMgr:runWhenOnline(function()
        closeInitWait()
        if cancel_ref and cancel_ref.cancelled then
            self:log("XRayPlugin: Series: runWhenOnline fired after user cancelled")
            return
        end
        local is_cancelled = cancel_ref and cancel_ref.cancelled or false
        local wait_msg

        local function showProgress(current_idx, total_count, book_title)
            if is_silent then return end
            closeInitWait()
            if wait_msg then UIManager:close(wait_msg) end

            local progress_text = self.loc:t("fetching_series_context", current_idx, total_count)
            wait_msg = ButtonDialog:new{
                modal = true,
                title = progress_text .. "\n\n" .. book_title .. "\n\n" .. (self.loc:t("fetching_wait") or "This may take a moment.\nTap Cancel to stop."),
                buttons = {{{
                    text = self.loc:t("cancel") or "Cancel",
                    callback = function()
                        is_cancelled = true
                        self:log("XRayPlugin: Series: User tapped Cancel on progress dialog.")
                        if wait_msg then
                            if wait_msg.dismiss_callback then
                                wait_msg.dismiss_callback()
                            end
                            UIManager:close(wait_msg)
                        end
                    end
                }}}
            }
            UIManager:show(wait_msg)
        end

        local function processNextTask(task_idx)
            if is_cancelled then
                self:log("XRayPlugin: Series: fetch series context cancelled by user.")
                return
            end

            if task_idx > total_tasks then
                self:log("XRayPlugin: Series: All series tasks completed. Saving series cache and merging context.")
                if wait_msg then UIManager:close(wait_msg) end
                self.series_manager:saveSeriesCache(slug, cache_data)
                self:mergeSeriesContext(cache_data, series_info)

                if not is_silent then
                    local count = #prior_books
                    local loaded_msg = self.loc:t("series_context_loaded", count)
                    UIManager:show(InfoMessage:new{
                        text = loaded_msg,
                        timeout = 5
                    })
                end
                return
            end

            -- Tasks 1..#books_needing_timeline_summary: summarize local timelines
            if task_idx <= #books_needing_timeline_summary then
                local item = books_needing_timeline_summary[task_idx]
                local current_book = item.book
                self:log("XRayPlugin: Series: Summarizing local chapter events for Book " .. tostring(item.index) .. " (" .. tostring(task_idx) .. "/" .. tostring(total_tasks) .. "): " .. tostring(current_book.title))
                showProgress(task_idx, total_tasks, current_book.title or ("Book " .. tostring(item.index)))

                UIManager:scheduleIn(0.5, function()
                    coroutine.wrap(function()
                        if is_cancelled or self.destroyed or not self.ui or not self.ui.document then return end

                        local event_lines = {}
                        for _, ev in ipairs(current_book.timeline or {}) do
                            if ev.event and ev.event ~= "" then
                                table.insert(event_lines, string.format("[%s] %s", ev.chapter or "Event", ev.event))
                            end
                        end
                        local events_text = table.concat(event_lines, "\n\n")

                        local context = {
                            series_name = series_info.name,
                            index = item.index,
                            events_text = events_text
                        }
                        local prompt = self.ai_helper:createPrompt(current_book.title, current_book.author or author, context, "local_timeline_summary")
                        self.ai_helper:setTrapWidget(wait_msg)
                        local result, err_code, err_msg = self.ai_helper:executeUnifiedRequest(prompt)
                        self.ai_helper:resetTrapWidget()

                        if is_cancelled then return end

                        if result and result.timeline and #result.timeline > 0 then
                            self:log("XRayPlugin: Series: Synthesized full book summary for local Book " .. tostring(item.index))
                            current_book.timeline = result.timeline
                            current_book.timeline_summarized = true
                            cache_data.books[item.index].timeline = result.timeline
                            cache_data.books[item.index].timeline_summarized = true
                            self.series_manager:saveSeriesCache(slug, cache_data)
                        else
                            self:log("XRayPlugin: Series: Local timeline summary AI call skipped/failed (err: " .. tostring(err_msg) .. "). Keeping raw chapter events.")
                        end

                        processNextTask(task_idx + 1)
                    end)()
                end)
                return
            end

            -- Remaining tasks: fetch missing books from AI via series_book_summary
            local missing_idx = task_idx - #books_needing_timeline_summary
            local current_book = missing_books[missing_idx]
            self:log("XRayPlugin: Series: Fetching AI context for book " .. tostring(current_book.index) .. " (" .. tostring(task_idx) .. "/" .. tostring(total_tasks) .. "): " .. tostring(current_book.title))
            showProgress(task_idx, total_tasks, current_book.title)

            UIManager:scheduleIn(0.5, function()
                coroutine.wrap(function()
                    if is_cancelled or self.destroyed or not self.ui or not self.ui.document then return end

                    local context = {
                        series_name = series_info.name,
                        index = current_book.index
                    }
                    local prompt = self.ai_helper:createPrompt(current_book.title, current_book.author or author, context, "series_book_summary")
                    
                    self.ai_helper:setTrapWidget(wait_msg)
                    local result, err_code, err_msg = self.ai_helper:executeUnifiedRequest(prompt)
                    self.ai_helper:resetTrapWidget()

                    if is_cancelled then return end

                    if not result then
                        self:log("XRayPlugin: Series: Failed fetching book summary for " .. tostring(current_book.title) .. ", err_code=" .. tostring(err_code) .. ", err_msg=" .. tostring(err_msg))
                        if wait_msg then UIManager:close(wait_msg) end
                        if not is_silent then
                            local ButtonDialog = require("ui/widget/buttondialog")
                            local err_title, err_text = utils:getFriendlyError(err_code, err_msg, self.loc)
                            local err_box
                            err_box = ButtonDialog:new{
                                modal = true,
                                title = err_title .. "\n\n" .. err_text,
                                text = err_text,
                                buttons = {{{ text = self.loc:t("ok") or "OK", callback = function() if err_box then UIManager:close(err_box) end end }}}
                            }
                            UIManager:show(err_box)
                        end
                        return
                    end

                    self:log("XRayPlugin: Series: Fetched context for " .. tostring(current_book.title) .. ". Characters=" .. tostring(#(result.characters or {})) .. ", locations=" .. tostring(#(result.locations or {})) .. ", terms=" .. tostring(#(result.terms or {})) .. ", timeline=" .. tostring(#(result.timeline or {})))

                    local existing_book = cache_data.books[current_book.index]
                    local book_path = current_book.path or (cache_data.book_paths and cache_data.book_paths[current_book.index]) or (existing_book and existing_book.path)
                    cache_data.books[current_book.index] = {
                        title = current_book.title,
                        author = current_book.author,
                        path = book_path,
                        characters = result.characters or {},
                        locations = result.locations or {},
                        terms = result.terms or {},
                        timeline = result.timeline or {},
                        source = "llm_summary"
                    }
                    if book_path then
                        cache_data.book_paths = cache_data.book_paths or {}
                        cache_data.book_paths[current_book.index] = book_path
                    end
                    -- Save after each book so a later failure or cancel doesn't
                    -- discard the books already fetched; a retry then only
                    -- fetches the ones still missing.
                    self.series_manager:saveSeriesCache(slug, cache_data)

                    processNextTask(task_idx + 1)
                end)()
            end)
        end

        processNextTask(1)
    end)
end

function M:checkpointHorizonScan()
    local doc_file = (self.ui and self.ui.document) and self.ui.document.file
    if not doc_file then return end
    if not self.cache_manager then self.cache_manager = require(plugin_path .. "xray_cachemanager"):new() end
    if not self.book_data then self.book_data = {} end

    if self.sortTimelineByTOC and self.timeline and #self.timeline > 1 then
        self:sortTimelineByTOC(self.timeline)
    end

    local cache = self.book_data
    cache.characters = self.characters or {}
    cache.locations = self.locations or {}
    cache.terms = self.terms or {}
    cache.historical_figures = self.historical_figures or {}
    cache.timeline = self.timeline or {}
    cache.chapters_fetched = self.chapters_fetched or {}
    cache.author_info = self.author_info or cache.author_info
    cache.book_title = cache.book_title or (self.ui and self.ui.document and self.ui.document.getProps and self.ui.document:getProps().title)
    cache.book_author = cache.book_author or (self.ui and self.ui.document and self.ui.document.getProps and self.ui.document:getProps().authors)
    cache.images = (self.images and #self.images > 0 and self.images) or cache.images or (self.book_data and self.book_data.images)

    self.cache_manager:asyncSaveCache(doc_file, cache)
    self:log(string.format("XRayPlugin: Checkpoint saved - Cache totals: %d characters, %d locations, %d terms, %d timeline events.",
        #(self.characters or {}), #(self.locations or {}), #(self.terms or {}), #(self.timeline or {})))
end

function M:buildCompactEntityManifest(story_id)
    local lines = {}
    local chars = self.characters or {}
    if story_id then
        local filt = {}
        for _, c in ipairs(chars) do
            local is_rec = c.is_recurring or (self.isEntityRecurring and self:isEntityRecurring(c))
            local st = c.story_id or (self.resolveEntityStory and self:resolveEntityStory(c))
            if is_rec or st == story_id then table.insert(filt, c) end
        end
        chars = filt
    end
    if #chars > 0 then
        table.insert(lines, "CHARACTERS:")
        for _, c in ipairs(chars) do
            local role, status, desc
            if self.resolveEntityState then
                role, status, desc = self:resolveEntityState(c)
            else
                role, status, desc = c.role, c.status or "alive", c.description
            end
            local aliases = (c.aliases and #c.aliases > 0) and (" (Aliases: " .. table.concat(c.aliases, ", ") .. ")") or ""
            local desc_snippet = desc and (desc:sub(1, 280) .. (#desc > 280 and "..." or "")) or ""
            table.insert(lines, string.format("- %s%s | Role: %s | Status: %s | %s", c.name or "?", aliases, role or "Unknown", status or "alive", desc_snippet))
        end
    end
    local locs = self.locations or {}
    if story_id then
        local filt = {}
        for _, l in ipairs(locs) do
            local is_rec = l.is_recurring or (self.isEntityRecurring and self:isEntityRecurring(l))
            local st = l.story_id or (self.resolveEntityStory and self:resolveEntityStory(l))
            if is_rec or st == story_id then table.insert(filt, l) end
        end
        locs = filt
    end
    if #locs > 0 then
        table.insert(lines, "\nLOCATIONS:")
        for _, l in ipairs(locs) do
            local desc
            if self.resolveEntityState then
                local _, _, r_desc = self:resolveEntityState(l)
                desc = r_desc
            end
            desc = desc or l.description
            local desc_snippet = desc and (desc:sub(1, 150) .. (#desc > 150 and "..." or "")) or ""
            table.insert(lines, string.format("- %s | %s", l.name or "?", desc_snippet))
        end
    end
    local terms = self.terms or {}
    if story_id then
        local filt = {}
        for _, t in ipairs(terms) do
            local is_rec = t.is_recurring or (self.isEntityRecurring and self:isEntityRecurring(t))
            local st = t.story_id or (self.resolveEntityStory and self:resolveEntityStory(t))
            if is_rec or st == story_id then table.insert(filt, t) end
        end
        terms = filt
    end
    if #terms > 0 then
        table.insert(lines, "\nTERMS:")
        for _, t in ipairs(terms) do
            local desc
            if self.resolveEntityState then
                local _, _, r_desc = self:resolveEntityState(t)
                desc = r_desc
            end
            desc = desc or t.description or t.definition
            local desc_snippet = desc and (desc:sub(1, 150) .. (#desc > 150 and "..." or "")) or ""
            table.insert(lines, string.format("- %s | %s", t.name or "?", desc_snippet))
        end
    end
    if #lines == 0 then return "None" end
    return table.concat(lines, "\n")
end

function M:mergeSequentialChapterDelta(delta_data, chapter, chapter_idx, skip_checkpoint)
    if not delta_data or type(delta_data) ~= "table" then return end
    if type(chapter) == "number" then
        chapter = { toc_index = chapter, page = chapter_idx }
    else
        chapter = chapter or {}
    end
    chapter_idx = chapter_idx or chapter.toc_index or 1
    local ch_title = chapter.title or ("Chapter " .. tostring(chapter_idx))
    local ch_page = tonumber(chapter.page)
    local ch_xp = chapter.xpointer

    local is_anthology = self.isAnthologyMode and self:isAnthologyMode()
    local ch_story_id = chapter.story_id
    local ch_story_title = chapter.story_title
    if is_anthology and not ch_story_id then
        local st = self:getCurrentStory(ch_page or (chapter_idx and self.chapter_analyzer and self.chapter_analyzer:getStoryForTocIndex(self.ui, chapter_idx)))
        if st then
            ch_story_id = st.story_id
            ch_story_title = st.story_title
        end
    end

    self.characters = self.characters or {}
    self.locations = self.locations or {}
    self.terms = self.terms or {}
    self.timeline = self.timeline or {}

    local new_chars, updated_chars = 0, 0
    local new_locs, updated_locs = 0, 0
    local new_terms, updated_terms = 0, 0
    local new_events = 0

    local function norm(s)
        if not s then return "" end
        return tostring(s):lower():gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    end

    local function makeId(prefix, name)
        local clean = (name or ""):lower():gsub("%s+", "_"):gsub("[^%w_]", "")
        return prefix .. "_" .. (clean ~= "" and clean or tostring(os.time()))
    end

    local function isSpecificMultiWordName(n)
        if not n or type(n) ~= "string" then return false end
        local words = {}
        for w in n:gmatch("%S+") do table.insert(words, w) end
        return #words >= 2
    end

    local function findEntity(list, name, aliases)
        local n_target = norm(name)
        if n_target == "" then return nil end
        -- Pass 1: exact match or canonical match in the same story
        for _, e in ipairs(list) do
            local story_match = not is_anthology or not ch_story_id or (e.story_id or (self.resolveEntityStory and self:resolveEntityStory(e))) == ch_story_id
            if story_match then
                if norm(e.name) == n_target then return e end
                if e.aliases then
                    for _, a in ipairs(e.aliases) do
                        if norm(a) == n_target then return e end
                    end
                end
                if aliases then
                    for _, a in ipairs(aliases) do
                        if norm(e.name) == norm(a) then return e end
                    end
                end
                if self.namesMatchCanonical and self:namesMatchCanonical(e.name, name) then
                    return e
                end
            end
        end

        -- Pass 2: in anthology mode, link across stories for multi-word or recurring entities
        if is_anthology and ch_story_id then
            for _, e in ipairs(list) do
                local eligible = e.is_recurring or (self.isEntityRecurring and self:isEntityRecurring(e)) or isSpecificMultiWordName(e.name)
                if eligible then
                    local matched = (norm(e.name) == n_target)
                    if not matched and e.aliases then
                        for _, a in ipairs(e.aliases) do
                            if norm(a) == n_target then matched = true; break end
                        end
                    end
                    if not matched and aliases then
                        for _, a in ipairs(aliases) do
                            if norm(e.name) == norm(a) then matched = true; break end
                        end
                    end
                    if not matched and self.namesMatchCanonical and self:namesMatchCanonical(e.name, name) then
                        matched = true
                    end
                    if matched then
                        e.is_recurring = true
                        local ex_st = e.story_id or (self.resolveEntityStory and self:resolveEntityStory(e))
                        if self.markStoryPresence then
                            if ex_st then self:markStoryPresence(e.name, ex_st) end
                            self:markStoryPresence(e.name, ch_story_id)
                        else
                            if self.book_data then
                                self.book_data.story_presence = self.book_data.story_presence or {}
                                self.book_data.story_presence[e.name] = self.book_data.story_presence[e.name] or {}
                                if ex_st then self.book_data.story_presence[e.name][ex_st] = true end
                                self.book_data.story_presence[e.name][ch_story_id] = true
                            end
                        end
                        return e
                    end
                end
            end
        end

        return nil
    end

    local function promotePriorEntity(existing)
        if existing.source == "series_prior" then
            existing.source = nil
            existing.is_series = true
            existing.sort_order = nil
        end
        if not existing.visible_from then
            existing.visible_from = {
                chapter_index = chapter_idx,
                chapter_title = ch_title,
                page_hint = ch_page,
                xpointer = ch_xp
            }
        end
    end

    local function updateEntityDescPreservingPrior(existing, new_desc, key)
        if self.updateEntityDescPreservingPrior then
            return self:updateEntityDescPreservingPrior(existing, new_desc, key)
        end
        return M.updateEntityDescPreservingPrior(self, existing, new_desc, key)
    end

    local function mergeAliases(existing, new_aliases)
        if not new_aliases or type(new_aliases) ~= "table" then return end
        existing.aliases = existing.aliases or {}
        local seen_a = {}
        for _, a in ipairs(existing.aliases) do seen_a[a:lower()] = true end
        for _, a in ipairs(new_aliases) do
            if a and a ~= "" and not seen_a[a:lower()] then
                table.insert(existing.aliases, a)
                seen_a[a:lower()] = true
            end
        end
    end

    -- 1. Characters: new
    if delta_data.new_characters and type(delta_data.new_characters) == "table" then
        for _, c in ipairs(delta_data.new_characters) do
            if c.name and c.name ~= "" then
                local existing = findEntity(self.characters, c.name, c.aliases)
                if existing then
                    updated_chars = updated_chars + 1
                    promotePriorEntity(existing)
                    mergeAliases(existing, c.aliases)
                    existing.states = existing.states or {}
                    table.insert(existing.states, {
                        chapter_index = chapter_idx,
                        chapter_title = ch_title,
                        page_hint = ch_page,
                        xpointer = ch_xp,
                        role = c.role or existing.role,
                        status = c.status or existing.status or "alive",
                        description = c.description or existing.description,
                        evidence = c.evidence or ""
                    })
                    if c.role and c.role ~= "" then existing.role = c.role end
                    if c.status and c.status ~= "" then existing.status = c.status end
                    updateEntityDescPreservingPrior(existing, c.description)
                else
                    new_chars = new_chars + 1
                    local new_char = {
                        id = c.id or makeId("char", c.name),
                        name = c.name,
                        aliases = c.aliases or {},
                        role = c.role or "Character",
                        status = c.status or "alive",
                        description = c.description or "",
                        story_id = ch_story_id,
                        story_title = ch_story_title,
                        visible_from = {
                            chapter_index = chapter_idx,
                            chapter_title = ch_title,
                            page_hint = ch_page,
                            xpointer = ch_xp
                        },
                        states = {
                            {
                                chapter_index = chapter_idx,
                                chapter_title = ch_title,
                                page_hint = ch_page,
                                xpointer = ch_xp,
                                role = c.role or "Character",
                                status = c.status or "alive",
                                description = c.description or "",
                                evidence = c.evidence or ""
                            }
                        }
                    }
                    table.insert(self.characters, new_char)
                end
            end
        end
    end

    -- 2. Characters: state updates
    if delta_data.character_state_updates and type(delta_data.character_state_updates) == "table" then
        for _, u in ipairs(delta_data.character_state_updates) do
            if u.name and u.name ~= "" then
                local existing = findEntity(self.characters, u.name, u.aliases)
                if existing then
                    updated_chars = updated_chars + 1
                    promotePriorEntity(existing)
                    mergeAliases(existing, u.aliases)
                    existing.states = existing.states or {}
                    local already_has_chapter_state = false
                    for _, s in ipairs(existing.states) do
                        if s.chapter_index == chapter_idx then
                            already_has_chapter_state = true
                            if u.role and u.role ~= "" then s.role = u.role end
                            if u.status and u.status ~= "" then s.status = u.status end
                            if u.change and u.change ~= "" then s.change = u.change end
                            if u.description and u.description ~= "" then s.description = u.description end
                            if u.evidence and u.evidence ~= "" then s.evidence = u.evidence end
                            break
                        end
                    end
                    if not already_has_chapter_state then
                        table.insert(existing.states, {
                            chapter_index = chapter_idx,
                            chapter_title = ch_title,
                            page_hint = ch_page,
                            xpointer = ch_xp,
                            role = u.role or existing.role,
                            status = u.status or existing.status or "alive",
                            change = u.change or "",
                            description = u.description or existing.description,
                            evidence = u.evidence or ""
                        })
                    end
                    if u.role and u.role ~= "" then existing.role = u.role end
                    if u.status and u.status ~= "" then existing.status = u.status end
                    updateEntityDescPreservingPrior(existing, u.description)
                else
                    new_chars = new_chars + 1
                    table.insert(self.characters, {
                        id = u.id or makeId("char", u.name),
                        name = u.name,
                        aliases = u.aliases or {},
                        role = u.role or "Character",
                        status = u.status or "alive",
                        description = u.description or "",
                        story_id = ch_story_id,
                        story_title = ch_story_title,
                        visible_from = {
                            chapter_index = chapter_idx,
                            chapter_title = ch_title,
                            page_hint = ch_page,
                            xpointer = ch_xp
                        },
                        states = {
                            {
                                chapter_index = chapter_idx,
                                chapter_title = ch_title,
                                page_hint = ch_page,
                                xpointer = ch_xp,
                                role = u.role or "Character",
                                status = u.status or "alive",
                                change = u.change or "",
                                description = u.description or "",
                                evidence = u.evidence or ""
                            }
                        }
                    })
                end
            end
        end
    end

    -- 3. Locations: new & updates
    if delta_data.new_locations and type(delta_data.new_locations) == "table" then
        for _, l in ipairs(delta_data.new_locations) do
            if l.name and l.name ~= "" then
                local existing = findEntity(self.locations, l.name)
                if existing then
                    updated_locs = updated_locs + 1
                    promotePriorEntity(existing)
                    existing.states = existing.states or {}
                    table.insert(existing.states, {
                        chapter_index = chapter_idx,
                        chapter_title = ch_title,
                        page_hint = ch_page,
                        xpointer = ch_xp,
                        description = l.description or existing.description,
                        evidence = l.evidence or ""
                    })
                    updateEntityDescPreservingPrior(existing, l.description)
                else
                    new_locs = new_locs + 1
                    table.insert(self.locations, {
                        id = l.id or makeId("loc", l.name),
                        name = l.name,
                        description = l.description or "",
                        story_id = ch_story_id,
                        story_title = ch_story_title,
                        visible_from = {
                            chapter_index = chapter_idx,
                            chapter_title = ch_title,
                            page_hint = ch_page,
                            xpointer = ch_xp
                        },
                        states = {
                            {
                                chapter_index = chapter_idx,
                                chapter_title = ch_title,
                                page_hint = ch_page,
                                xpointer = ch_xp,
                                description = l.description or "",
                                evidence = l.evidence or ""
                            }
                        }
                    })
                end
            end
        end
    end
    if delta_data.location_state_updates and type(delta_data.location_state_updates) == "table" then
        for _, u in ipairs(delta_data.location_state_updates) do
            if u.name and u.name ~= "" then
                local existing = findEntity(self.locations, u.name)
                if existing then
                    updated_locs = updated_locs + 1
                    promotePriorEntity(existing)
                    existing.states = existing.states or {}
                    table.insert(existing.states, {
                        chapter_index = chapter_idx,
                        chapter_title = ch_title,
                        page_hint = ch_page,
                        xpointer = ch_xp,
                        change = u.change or "",
                        description = u.description or existing.description,
                        evidence = u.evidence or ""
                    })
                    updateEntityDescPreservingPrior(existing, u.description)
                else
                    new_locs = new_locs + 1
                    table.insert(self.locations, {
                        id = u.id or makeId("loc", u.name),
                        name = u.name,
                        description = u.description or "",
                        story_id = ch_story_id,
                        story_title = ch_story_title,
                        visible_from = {
                            chapter_index = chapter_idx,
                            chapter_title = ch_title,
                            page_hint = ch_page,
                            xpointer = ch_xp
                        },
                        states = {
                            {
                                chapter_index = chapter_idx,
                                chapter_title = ch_title,
                                page_hint = ch_page,
                                xpointer = ch_xp,
                                change = u.change or "",
                                description = u.description or "",
                                evidence = u.evidence or ""
                            }
                        }
                    })
                end
            end
        end
    end

    -- 4. Terms: new & updates
    if delta_data.new_terms and type(delta_data.new_terms) == "table" then
        for _, t in ipairs(delta_data.new_terms) do
            if t.name and t.name ~= "" then
                local existing = findEntity(self.terms, t.name)
                if existing then
                    updated_terms = updated_terms + 1
                    promotePriorEntity(existing)
                    existing.states = existing.states or {}
                    local desc = t.description or t.definition or existing.description or existing.definition
                    table.insert(existing.states, {
                        chapter_index = chapter_idx,
                        chapter_title = ch_title,
                        page_hint = ch_page,
                        xpointer = ch_xp,
                        description = desc,
                        evidence = t.evidence or ""
                    })
                    updateEntityDescPreservingPrior(existing, desc, "definition")
                else
                    new_terms = new_terms + 1
                    table.insert(self.terms, {
                        id = t.id or makeId("term", t.name),
                        name = t.name,
                        definition = t.description or t.definition or "",
                        description = t.description or t.definition or "",
                        story_id = ch_story_id,
                        story_title = ch_story_title,
                        visible_from = {
                            chapter_index = chapter_idx,
                            chapter_title = ch_title,
                            page_hint = ch_page,
                            xpointer = ch_xp
                        },
                        states = {
                            {
                                chapter_index = chapter_idx,
                                chapter_title = ch_title,
                                page_hint = ch_page,
                                xpointer = ch_xp,
                                description = t.description or t.definition or "",
                                evidence = t.evidence or ""
                            }
                        }
                    })
                end
            end
        end
    end
    if delta_data.term_state_updates and type(delta_data.term_state_updates) == "table" then
        for _, u in ipairs(delta_data.term_state_updates) do
            if u.name and u.name ~= "" then
                local existing = findEntity(self.terms, u.name)
                if existing then
                    updated_terms = updated_terms + 1
                    promotePriorEntity(existing)
                    existing.states = existing.states or {}
                    local desc = u.description or u.definition or existing.description or existing.definition
                    table.insert(existing.states, {
                        chapter_index = chapter_idx,
                        chapter_title = ch_title,
                        page_hint = ch_page,
                        xpointer = ch_xp,
                        change = u.change or "",
                        description = desc,
                        evidence = u.evidence or ""
                    })
                    updateEntityDescPreservingPrior(existing, desc, "definition")
                else
                    new_terms = new_terms + 1
                    local desc = u.description or u.definition or ""
                    table.insert(self.terms, {
                        id = u.id or makeId("term", u.name),
                        name = u.name,
                        definition = desc,
                        description = desc,
                        story_id = ch_story_id,
                        story_title = ch_story_title,
                        visible_from = {
                            chapter_index = chapter_idx,
                            chapter_title = ch_title,
                            page_hint = ch_page,
                            xpointer = ch_xp
                        },
                        states = {
                            {
                                chapter_index = chapter_idx,
                                chapter_title = ch_title,
                                page_hint = ch_page,
                                xpointer = ch_xp,
                                change = u.change or "",
                                description = desc,
                                evidence = u.evidence or ""
                            }
                        }
                    })
                end
            end
        end
    end

    -- 5. Timeline Event (accepts both string from batch scan and table from single chapter)
    local timeline_ev = delta_data.timeline_event
    local ev_text = nil
    local ev_title = ch_title

    if type(timeline_ev) == "string" then
        ev_text = timeline_ev
    elseif type(timeline_ev) == "table" then
        ev_text = timeline_ev.event or timeline_ev.summary or timeline_ev.description or timeline_ev.text
        if type(timeline_ev.chapter) == "string" and timeline_ev.chapter:match("%S") then
            ev_title = timeline_ev.chapter
        end
    end

    if type(ev_text) == "string" then
        ev_text = ev_text:gsub("^%s+", ""):gsub("%s+$", "")
    else
        ev_text = nil
    end

    if ev_text and ev_text ~= "" then
        if is_anthology and self.chapter_analyzer then
            local st = nil
            if ch_page then
                st = self.chapter_analyzer:getStoryForPage(self.ui, ch_page)
            end
            if not st and ev_title and self.normalizeChapterName then
                local n_ev = self:normalizeChapterName(ev_title)
                local sm = self.chapter_analyzer:getStoryMap(self.ui)
                if sm and sm.stories then
                    for _, s in ipairs(sm.stories) do
                        if self:normalizeChapterName(s.story_title) == n_ev then
                            st = s
                            break
                        end
                    end
                end
            end
            if not st and chapter_idx then
                st = self.chapter_analyzer:getStoryForTocIndex(self.ui, chapter_idx)
            end
            if st then
                ch_story_id = st.story_id
                ch_story_title = st.story_title
            end
        end

        local already_has_ev = false
        local norm_ev_title = self.normalizeChapterName and self:normalizeChapterName(ev_title) or ev_title:lower()
        for _, ev in ipairs(self.timeline) do
            local story_match = not is_anthology or not ch_story_id or (ev.story_id or (self.resolveEntityStory and self:resolveEntityStory(ev))) == ch_story_id
            local norm_existing = self.normalizeChapterName and self:normalizeChapterName(ev.chapter or "") or (ev.chapter or ""):lower()
            local same_chapter = (norm_existing ~= "" and norm_existing == norm_ev_title)
            local same_index = (ev.chapter_index and chapter_idx and ev.chapter_index == chapter_idx)
            local same_page = (ev.page and ch_page and tonumber(ev.page) == tonumber(ch_page))

            if story_match and (same_index or (same_chapter and same_page) or (ev.chapter == ev_title and (same_page or same_index))) then
                already_has_ev = true
                ev.event = ev_text
                ev.chapter = ev_title
                if ch_page and not ev.page then ev.page = ch_page end
                if chapter_idx and not ev.chapter_index then ev.chapter_index = chapter_idx end
                break
            end
        end
        if not already_has_ev then
            new_events = new_events + 1
            table.insert(self.timeline, {
                chapter = ev_title,
                event = ev_text,
                chapter_index = chapter_idx,
                page = ch_page,
                story_id = ch_story_id,
                story_title = ch_story_title,
            })
        end
    end

    self:log(string.format("XRayPlugin: Merged delta for '%s' (Ch. %s) -> New: [%d chars, %d locs, %d terms], Updated states: [%d chars, %d locs, %d terms], Events: %d",
        ch_title, tostring(chapter_idx), new_chars, new_locs, new_terms, updated_chars, updated_locs, updated_terms, new_events))

    -- Mark chapter as fetched
    self.chapters_fetched = self.chapters_fetched or {}
    local unique_id = ch_title .. "_" .. tostring(ch_page)
    self.chapters_fetched[unique_id] = true

    if is_anthology and ch_story_id then
        self.book_data = self.book_data or {}
        self.book_data.story_fetch_state = self.book_data.story_fetch_state or {}
        local st_state = self.book_data.story_fetch_state[ch_story_id] or {
            story_id = ch_story_id,
            story_title = ch_story_title,
        }
        st_state.story_id = ch_story_id
        st_state.story_title = ch_story_title or st_state.story_title
        if ch_page and (not st_state.last_fetch_page or ch_page > st_state.last_fetch_page) then
            st_state.last_fetch_page = ch_page
        end
        if chapter_idx and (not st_state.last_fetch_chapter or chapter_idx > st_state.last_fetch_chapter) then
            st_state.last_fetch_chapter = chapter_idx
        end
        st_state.terms_fetched = true
        self.book_data.story_fetch_state[ch_story_id] = st_state
    end

    -- Checkpoint immediately (unless part of a multi-chapter batch)
    if not skip_checkpoint and self.checkpointHorizonScan then
        self:checkpointHorizonScan()
    end
end

function M:queueSequentialChapterScan(target_chapter_indices, is_manual, on_progress, on_done)
    if not target_chapter_indices or #target_chapter_indices == 0 then
        if on_done then on_done(true) end
        return
    end

    self.chapters_fetched = self.chapters_fetched or {}

    -- Resolve raw TOC
    local raw_toc
    if self.ui and self.ui.document and self.ui.document.getToc then
        pcall(function() raw_toc = self.ui.document:getToc() end)
    end
    local toc = utils:flattenTOC(raw_toc) or {}

    -- Normalize target chapters into an array of chapter descriptors
    local queue = {}
    for _, item in ipairs(target_chapter_indices) do
        local ch = nil
        local idx = nil
        if type(item) == "table" then
            ch = item
            idx = item.toc_index
            if not idx then
                for ti, tc in ipairs(toc) do
                    if tc == item or (tc.title == item.title and tc.page == item.page) then
                        idx = ti
                        break
                    end
                end
            end
        elseif type(item) == "number" then
            idx = item
            ch = toc[item]
        end
        if ch then
            ch.toc_index = idx or ch.toc_index or 1
            if self.isAnthologyMode and self:isAnthologyMode() and self.chapter_analyzer then
                local st = self.chapter_analyzer:getStoryForTocIndex(self.ui, ch.toc_index)
                if st then
                    ch.story_id = st.story_id
                    ch.story_title = st.story_title
                end
            end
            table.insert(queue, ch)
        end
    end

    if #queue == 0 then
        if on_done then on_done(true) end
        return
    end

    -- Build parent chapter mapping to distinguish actual TOC chapters from virtual segments
    local parent_chapter_map = {}
    local parent_order = {}
    for _, ch in ipairs(queue) do
        local pid = ch.parent_toc_index or ch.toc_index or ch.title
        if not parent_chapter_map[pid] then
            parent_chapter_map[pid] = {
                title = ch.parent_title or ch.title,
                total_parts = ch.total_parts or 1,
                parts_completed = 0,
                done = false,
            }
            table.insert(parent_order, pid)
        elseif ch.total_parts and ch.total_parts > parent_chapter_map[pid].total_parts then
            parent_chapter_map[pid].total_parts = ch.total_parts
        end
    end

    local function markChapterItemComplete(item)
        local pid = item.parent_toc_index or item.toc_index or item.title
        local p_info = parent_chapter_map[pid]
        if p_info then
            p_info.parts_completed = p_info.parts_completed + 1
            if not p_info.done and p_info.parts_completed >= p_info.total_parts then
                p_info.done = true
                self.active_sequential_completed_chapters = (self.active_sequential_completed_chapters or 0) + 1
            end
        end
    end

    self.active_sequential_queue = queue
    self.active_sequential_is_manual = is_manual
    self.active_sequential_on_progress = on_progress
    self.active_sequential_on_done = on_done
    self.active_sequential_total = #queue
    self.active_sequential_completed = 0
    self.active_sequential_total_chapters = #parent_order
    self.active_sequential_completed_chapters = 0
    self.active_sequential_cancelled = false

    local function notifyProgress()
        if self.active_sequential_on_progress then
            self.active_sequential_on_progress(
                self.active_sequential_completed,
                self.active_sequential_total,
                self.active_sequential_completed_chapters,
                self.active_sequential_total_chapters
            )
        end
    end

    local scan_mode = is_manual and "Manual full-book pre-generation" or "Horizon prefetch"
    self:log(string.format("XRayPlugin: %s started - %d chapters (%d segments) queued.",
        scan_mode, self.active_sequential_total_chapters, self.active_sequential_total))

    -- If a scan is already running, re-targeting the queue is sufficient;
    -- the running step will pick up from the new active_sequential_queue when finished.
    if self.is_sequential_scan_active then
        self:log("XRayPlugin: Re-targeted active sequential scan queue with " .. tostring(#queue) .. " chapters.")
        return
    end

    self.is_sequential_scan_active = true
    local batches_processed = 0
    local is_anthology = self.isAnthologyMode and self:isAnthologyMode()

    local function finishScan(success)
        self.is_sequential_scan_active = false
        self.active_sequential_queue = nil
        local cb = self.active_sequential_on_done
        self.active_sequential_on_done = nil
        self.active_sequential_on_progress = nil
        if success then
            if self.sortTimelineByTOC and self.timeline and #self.timeline > 1 then
                self:sortTimelineByTOC(self.timeline)
            end
            self:log(string.format("XRayPlugin: Sequential chapter scan complete! Processed %d of %d chapters (%d segments). Final cache: %d chars, %d locs, %d terms, %d events.",
                self.active_sequential_completed_chapters or self.active_sequential_completed or 0,
                self.active_sequential_total_chapters or self.active_sequential_total or 0,
                self.active_sequential_completed or 0,
                #(self.characters or {}), #(self.locations or {}), #(self.terms or {}), #(self.timeline or {})))
        else
            self:log("XRayPlugin: Sequential chapter scan halted or cancelled.")
        end
        if cb then cb(success) end
        if success then
            if batches_processed > 0 then
                pcall(function()
                    local cur_p = self.ui and self.ui.getCurrentPage and self.ui:getCurrentPage() or 1
                    local tot_p = self.ui and self.ui.document and self.ui.document.getPageCount and self.ui.document:getPageCount() or 1
                    local r_pct = tot_p and tot_p > 0 and math.floor((cur_p / tot_p) * 100) or 100
                    self:runPostFetchDuplicateCheck(nil, nil, r_pct, true)
                end)
            else
                self:log("XRayPlugin: Sequential scan completed with 0 new batches processed; skipping post-fetch duplicate check.")
            end
        end
    end

    local ChapterAnalyzer = require(plugin_path .. "xray_chapteranalyzer")
    local MAX_BATCH_CHAPTERS = 3
    local MAX_BATCH_CHARS = 45000

    local function processNext()
        if self.destroyed or not self.ui or not self.ui.document or self.active_sequential_cancelled then
            finishScan(false)
            return
        end

        local utils = require(plugin_path .. "xray_utils")
        if utils and utils.isLowMemory and utils:isLowMemory() then
            collectgarbage("collect")
            if utils:isLowMemory() then
                self:log("XRayPlugin: Device memory critically low, pausing sequential chapter prefetch.")
                finishScan(false)
                return
            end
        end

        local q = self.active_sequential_queue
        if not q or #q == 0 then
            finishScan(true)
            return
        end

        local cur_page = self.getCurrentDocPage and self:getCurrentDocPage() or nil
        local batch_items = {}
        local total_batch_chars = 0

        while #q > 0 and #batch_items < MAX_BATCH_CHAPTERS do
            local candidate = q[1]
            local cand_idx = candidate.toc_index or 1
            local cand_id = (candidate.title or ("Chapter " .. tostring(cand_idx))) .. "_" .. tostring(candidate.page)

            local cand_already_fetched = self.chapters_fetched and self.chapters_fetched[cand_id]
            if not cand_already_fetched and self.timeline then
                for _, ev in ipairs(self.timeline) do
                    local story_match = not is_anthology or not candidate.story_id or (ev.story_id == candidate.story_id)
                    if story_match then
                        if (ev.chapter_index and ev.chapter_index == cand_idx) or
                           (ev.page and candidate.page and tonumber(ev.page) == tonumber(candidate.page)) then
                            cand_already_fetched = true
                            self.chapters_fetched[cand_id] = true
                            break
                        end
                    end
                end
            end

            if cand_already_fetched then
                self:log(string.format("XRayPlugin: Skipping already-fetched chapter '%s' (p. %s).", tostring(candidate.title), tostring(candidate.page)))
                table.remove(q, 1)
                self.active_sequential_completed = self.active_sequential_completed + 1
                markChapterItemComplete(candidate)
                notifyProgress()
            else
                -- Find next chapter in TOC for bounding candidate
                local next_chapter = nil
                for ti = cand_idx + 1, #toc do
                    local tc = toc[ti]
                    if tc and not (self.isNonNarrativeChapter and self:isNonNarrativeChapter(tc.title or "")) then
                        next_chapter = tc
                        break
                    end
                end

                local ch_text = ChapterAnalyzer:getSingleChapterText(self.ui, candidate, next_chapter, nil, 50000)
                if not ch_text or #ch_text < 100 then
                    self:log("XRayPlugin: Chapter text empty or too short (<100 chars), skipping: " .. tostring(candidate.title))
                    table.remove(q, 1)
                    self.chapters_fetched[cand_id] = true
                    self.active_sequential_completed = self.active_sequential_completed + 1
                    markChapterItemComplete(candidate)
                    notifyProgress()
                else
                    if #batch_items > 0 then
                        if (total_batch_chars + #ch_text) > MAX_BATCH_CHARS then
                            -- Reached character budget for this batch, process current batch first
                            break
                        end
                        if self.isAnthologyMode and self:isAnthologyMode() then
                            local b1_st = batch_items[1].story_id
                            local cand_st = candidate.story_id
                            if b1_st and cand_st and b1_st ~= cand_st then
                                -- Story boundary reached, split batch
                                break
                            end
                        end
                    end
                    table.remove(q, 1)
                    local item_entry = {
                        title = candidate.title,
                        parent_title = candidate.parent_title,
                        parent_toc_index = candidate.parent_toc_index,
                        part_index = candidate.part_index,
                        total_parts = candidate.total_parts,
                        is_virtual_segment = candidate.is_virtual_segment,
                        page = candidate.page,
                        end_page = candidate.end_page,
                        xpointer = candidate.xpointer,
                        toc_index = candidate.toc_index or cand_idx,
                        depth = candidate.depth,
                        unique_id = cand_id,
                        text = ch_text,
                        story_id = candidate.story_id,
                        story_title = candidate.story_title,
                    }
                    table.insert(batch_items, item_entry)
                    total_batch_chars = total_batch_chars + #ch_text
                end
            end
        end

        if #batch_items == 0 then
            if #q > 0 then
                UIManager:scheduleIn(0.1, processNext)
            else
                finishScan(true)
            end
            return
        end

        self:log(string.format("XRayPlugin: Assembling batch (%d items, %d characters total)...", #batch_items, total_batch_chars))
        for b_idx, bi in ipairs(batch_items) do
            self:log(string.format("XRayPlugin:   [%d/%d] '%s' (p. %s-%s, %d chars)",
                b_idx, #batch_items, bi.title, tostring(bi.page), tostring(bi.end_page or "?"), #(bi.text or "")))
        end

        local props = (self.ui and self.ui.document and self.ui.document.getProps and self.ui.document:getProps()) or {}
        local title = props.title or "Book"
        local author = props.authors or props.author or "Author"
        local manifest_story_id = (self.isAnthologyMode and self:isAnthologyMode() and batch_items[1]) and batch_items[1].story_id or nil
        local manifest = self:buildCompactEntityManifest(manifest_story_id)

        local prompt, err
        if #batch_items == 1 and not (self.ai_helper.prompts and self.ai_helper.prompts.batch_chapter_delta) then
            prompt, err = self.ai_helper:buildChapterDeltaPrompt(title, author, batch_items[1].title, manifest, batch_items[1].text)
        else
            prompt, err = self.ai_helper:buildBatchChapterDeltaPrompt(title, author, batch_items, manifest)
            if not prompt then
                prompt, err = self.ai_helper:buildChapterDeltaPrompt(title, author, batch_items[1].title, manifest, batch_items[1].text)
            end
        end

        -- Immediately free pinned raw chapter texts from batch items once prompt is built
        for _, bi in ipairs(batch_items) do
            bi.text = nil
        end

        if not prompt then
            self:log("XRayPlugin: Failed to build chapter delta prompt: " .. tostring(err))
            finishScan(false)
            return
        end

        local prompt_chars = #prompt
        local manifest_count = (self.characters and #self.characters or 0) + (self.locations and #self.locations or 0) + (self.terms and #self.terms or 0)

        local req_params, req_err = self.ai_helper:buildComprehensiveRequest(nil, nil, nil, prompt)
        if not req_params then
            self:log("XRayPlugin: Failed to build comprehensive request: " .. tostring(req_err))
            finishScan(false)
            return
        end

        self.active_sequential_current_batch = batch_items
        self.active_sequential_batch_start_time = os.time()
        self.active_sequential_status = "Waiting for AI response..."

        local first_idx = batch_items[1].toc_index or 1
        local DataStorage = require("datastorage")
        local settings_xray_dir = DataStorage:getSettingsDir() .. "/xray"
        local result_file = settings_xray_dir .. "/bg_delta_" .. tostring(os.time()) .. "_" .. tostring(first_idx) .. ".json"

        collectgarbage("step", 100)
        local pid = self.ai_helper:makeRequestAsync(req_params, result_file)
        if not pid then
            self:log("XRayPlugin: Failed to start async AI request for batch starting at chapter " .. tostring(first_idx))
            pcall(function() os.remove(result_file) end)
            finishScan(false)
            return
        end

        self:log(string.format("XRayPlugin: Prompt generated (%d chars, manifest: %d entities). Dispatched async AI request (PID %s)...",
            prompt_chars, manifest_count, tostring(pid)))

        local start_t = os.time()
        local last_logged_elapsed = 0
        local timeout = 300
        local function pollResult()
            if self.destroyed or self.active_sequential_cancelled then
                pcall(function() os.remove(result_file) end)
                finishScan(false)
                return
            end
            local data, p_err = self.ai_helper:checkAsyncResult(result_file, pid)
            if data == nil then
                local elapsed = os.time() - start_t
                if elapsed > 0 and (elapsed % 15 == 0) and elapsed ~= last_logged_elapsed then
                    last_logged_elapsed = elapsed
                    self:log(string.format("XRayPlugin: Waiting for AI response... (%ds elapsed)", elapsed))
                end
                if elapsed < timeout then
                    UIManager:scheduleIn(2, pollResult)
                else
                    pcall(function() os.remove(result_file) end)
                    self:log("XRayPlugin: Sequential chapter scan timed out for batch starting at: " .. tostring(batch_items[1].title))
                    finishScan(false)
                end
            else
                pcall(function() os.remove(result_file) end)
                local duration = math.max(0, os.time() - start_t)
                if type(data) == "table" then
                    batches_processed = batches_processed + 1
                    self:log(string.format("XRayPlugin: AI response received in %ds. Merging delta data...", duration))
                    self.active_sequential_status = "Merging delta results..."
                    if data.chapters and type(data.chapters) == "table" then
                        -- Multi-chapter response
                        for _, ch_delta in ipairs(data.chapters) do
                            local target_item = nil
                            local target_idx = ch_delta.chapter_index
                            if target_idx then
                                for _, bi in ipairs(batch_items) do
                                    if (bi.toc_index or bi.chapter_index) == target_idx then
                                        target_item = bi
                                        break
                                    end
                                end
                            end
                            if not target_item and ch_delta.chapter_title then
                                for _, bi in ipairs(batch_items) do
                                    if bi.title == ch_delta.chapter_title then
                                        target_item = bi
                                        break
                                    end
                                end
                            end
                            target_item = target_item or batch_items[1]
                            local resolved_idx = target_item.toc_index or target_idx or 1
                            self:mergeSequentialChapterDelta(ch_delta, target_item, resolved_idx, true)
                        end
                    else
                        -- Single-chapter fallback response
                        self:mergeSequentialChapterDelta(data, batch_items[1], batch_items[1].toc_index or 1, true)
                    end

                    self:checkpointHorizonScan()
                    collectgarbage("step", 200)

                    for _, bi in ipairs(batch_items) do
                        self.chapters_fetched[bi.unique_id] = true
                        self.active_sequential_completed = self.active_sequential_completed + 1
                        markChapterItemComplete(bi)
                    end
                    self.active_sequential_status = "Batch completed. Pacing..."
                    notifyProgress()

                    self:log(string.format("XRayPlugin: Batch completed (%d/%d chapters, %d/%d segments). Pacing cooldown: waiting 3s before next batch...",
                        self.active_sequential_completed_chapters or self.active_sequential_completed,
                        self.active_sequential_total_chapters or self.active_sequential_total,
                        self.active_sequential_completed,
                        self.active_sequential_total))

                    -- 3s pacing cooldown between batches to prevent rate limits (HTTP 429)
                    UIManager:scheduleIn(3, processNext)
                else
                    local retry_count = batch_items._retries or 0
                    if retry_count < 2 then
                        batch_items._retries = retry_count + 1
                        self:log(string.format("XRayPlugin: Batch failed (%s). Re-queuing to retry in 5s (attempt %d/2)...", tostring(p_err), retry_count + 1))
                        self.active_sequential_status = string.format("Temporary error (%s). Retrying in 5s...", tostring(p_err))
                        for i = #batch_items, 1, -1 do
                            table.insert(q, 1, batch_items[i])
                        end
                        UIManager:scheduleIn(5, processNext)
                    else
                        self:log(string.format("XRayPlugin: Batch failed after %d retries (%s). Advancing queue.", retry_count, tostring(p_err)))
                        self.active_sequential_status = "Batch skipped after repeated errors. Advancing..."
                        for _, bi in ipairs(batch_items) do
                            self.chapters_fetched[bi.unique_id] = true
                            self.active_sequential_completed = self.active_sequential_completed + 1
                            markChapterItemComplete(bi)
                        end
                        notifyProgress()
                        UIManager:scheduleIn(3, processNext)
                    end
                end
            end
        end

        UIManager:scheduleIn(2, pollResult)
    end

    processNext()
end

function M:cancelSequentialChapterScan()
    self.active_sequential_cancelled = true
    self.active_sequential_queue = nil
    self.active_sequential_current_batch = nil
    self.active_sequential_batch_start_time = nil
    self.active_sequential_status = nil
    self.is_sequential_scan_active = false
end

return M
