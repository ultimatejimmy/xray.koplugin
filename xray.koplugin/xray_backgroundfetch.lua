-- Persistent background sampling queue. Reader events only wake this scheduler;
-- all requests continue to use the plugin's single foreground-aware AI slot.
local UIManager = require("ui/uimanager")
local plugin_path = ((...) or ""):match("(.-)[^%.]+$") or ""
local utils = require(plugin_path .. "xray_utils")
local M = {}

local function identity(document)
    local ok, lfs = pcall(require, "lfs")
    local attr = ok and lfs.attributes(document.file) or nil
    return { file = document.file, size = attr and attr.size, modified = attr and attr.modification }
end

local function hasBookData(plugin)
    for _, field in ipairs({ "characters", "historical_figures", "locations", "terms", "timeline" }) do
        if plugin[field] and #plugin[field] > 0 then return true end
    end
    return false
end

function M:backgroundPosition(page)
    local position = { page = page }
    local doc = self.ui.document
    if self.ui.rolling and page > 0 and doc.getPageXPointer then
        local ok, xp = pcall(doc.getPageXPointer, doc, page)
        if ok then position.xpointer = xp end
    end
    return position
end

function M:cancelBackgroundSchedule()
    -- Cancel execution, not the persisted obligation (disable/close/suspend).
    if self._background_catch_up_callback and UIManager.unschedule then
        UIManager:unschedule(self._background_catch_up_callback)
    end
    self._background_catch_up_callback = nil
    self._background_epoch = (self._background_epoch or 0) + 1
end

function M:persistBackgroundQueue(synchronous)
    if not self.ui or not self.ui.document or not self.ui.document.file then return end
    if not self.book_data and not self.background_fetch_queue then return end
    if not self.cache_manager then self.cache_manager = require(plugin_path .. "xray_cachemanager"):new() end
    local data = utils:copyTable(self.book_data or {})
    data.background_fetch_queue = utils:copyTable(self.background_fetch_queue)
    self.book_data = data
    if synchronous then
        return self.cache_manager:saveCache(self.ui.document.file, data)
    end
    if self._background_inflight then return end
    self._background_saving = (self._background_saving or 0) + 1
    local document = self.ui.document
    self.cache_manager:asyncSaveCache(document.file, data, function(success)
        self._background_saving = math.max(0, (self._background_saving or 1) - 1)
        if self.destroyed or not self.ui or self.ui.document ~= document then return end
        if not success and self.background_fetch_queue then
            self.background_fetch_queue.paused = "cache"
            self:log("XRayPlugin: Background queue paused because its cache could not be saved")
        end
    end)
end

function M:restoreBackgroundQueue()
    self:cancelBackgroundSchedule()
    self.background_fetch_queue = nil
    local saved = self.book_data and self.book_data.background_fetch_queue
    if type(saved) ~= "table" or saved.version ~= 1
            or type(saved.cursor) ~= "table" or type(saved.target) ~= "table" then return end
    if type(saved.cursor.page) ~= "number" or type(saved.target.page) ~= "number"
            or saved.cursor.page < 0 or saved.target.page < saved.cursor.page then return end
    local current = identity(self.ui.document)
    local old = saved.document or {}
    if old.file ~= current.file or old.size ~= current.size or old.modified ~= current.modified then return end
    local queue = utils:copyTable(saved)
    local doc = self.ui.document
    local repaginated = queue.page_count ~= doc:getPageCount()
    for _, position in ipairs({ queue.cursor, queue.target }) do
        if position.xpointer and doc.getPageFromXPointer then
            local ok, page = pcall(doc.getPageFromXPointer, doc, position.xpointer)
            if not ok or not page or page < 1 then return end
            -- Revisit the page containing the old completed anchor: its end
            -- may have moved after a font or layout change.
            position.page = position == queue.cursor and repaginated and math.max(0, page - 1) or page
        elseif position.page > 0 and repaginated and self.ui.rolling then
            -- Without an anchor, restart sampling rather than trusting old pagination.
            queue.cursor = { page = 0 }
            queue.target = self:backgroundPosition(self.ui:getCurrentPage())
            break
        end
    end
    queue.page_count = doc:getPageCount()
    queue.target.page = math.min(queue.target.page, queue.page_count)
    queue.window_pages = math.max(1, math.min(60, tonumber(queue.window_pages) or 60))
    queue.chapter_limit = math.max(1, math.min(200, tonumber(queue.chapter_limit) or 200))
    queue.retries = tonumber(queue.retries) or 0
    queue.retry_at = tonumber(queue.retry_at)
    queue.last_attempt_at = tonumber(queue.last_attempt_at)
    if queue.cursor.chapter_index and type(queue.cursor.chapter_index) ~= "number" then return end
    self.background_fetch_queue = queue
    self:wakeBackgroundQueue()
end

function M:wakeBackgroundQueue(settings_changed)
    local queue = self.background_fetch_queue
    if not queue then return end
    self._background_readiness_attempt = 0
    if settings_changed or queue.paused == "retry" or queue.paused == "cache" then
        queue.paused, queue.retries, queue.retry_at = nil, 0, nil
    end
    local old_target = queue.target.page
    self:queueBackgroundFetch()
    if old_target == queue.target.page and settings_changed then self:persistBackgroundQueue() end
    self:scheduleBackgroundCatchUp(2)
end

function M:queueBackgroundFetch()
    if self.destroyed or not self.auto_fetch_enabled or not self.ui or not self.ui.document then return end
    local doc = self.ui.document
    if not doc.file or not doc.getPageCount or not doc:getPageCount() or doc:getPageCount() < 1 then return end
    local full = self.ai_helper.settings.spoiler_setting == "full_book"
    local page = full and doc:getPageCount() or self.ui:getCurrentPage()
    local queue = self.background_fetch_queue
    if not queue then
        local cursor = self.book_data and self.book_data.last_fetch_page or 0
        if not hasBookData(self) then cursor = 0 end
        if cursor >= page then return end
        queue = {
            version = 1, document = identity(doc), page_count = doc:getPageCount(),
            cursor = self:backgroundPosition(cursor), target = self:backgroundPosition(page),
            retries = 0, window_pages = 60, chapter_limit = 200,
        }
        self.background_fetch_queue = queue
    elseif page > queue.target.page then
        queue.target = self:backgroundPosition(page)
    else
        return
    end
    self:persistBackgroundQueue()
end

function M:triggerBackgroundMergeFetch(chapter_title)
    self:queueBackgroundFetch()
    self:scheduleBackgroundCatchUp(0)
end

function M:scheduleBackgroundCatchUp(delay)
    if not self.background_fetch_queue or self._background_catch_up_callback then return end
    if self.destroyed or not self.ui or not self.ui.document or not self.auto_fetch_enabled then return end
    local document, epoch = self.ui.document, self._background_epoch
    local callback
    callback = function()
        if self._background_catch_up_callback ~= callback then return end
        self._background_catch_up_callback = nil
        if self.destroyed or not self.ui or self.ui.document ~= document or self._background_epoch ~= epoch then return end
        self:runBackgroundBatch()
    end
    self._background_catch_up_callback = callback
    UIManager:scheduleIn(delay or 2, callback)
end

function M:runBackgroundBatch()
    local queue = self.background_fetch_queue
    if not queue or queue.paused or not self.auto_fetch_enabled then return end
    if not self.ai_helper or not self.ai_helper:hasApiKey() then return end
    local NetworkMgr = require("ui/network/manager")
    if not NetworkMgr:isConnected() then return end
    if not NetworkMgr:isOnline() then
        local delays = { 5, 15, 30 }
        self._background_readiness_attempt = (self._background_readiness_attempt or 0) + 1
        local delay = delays[self._background_readiness_attempt]
        if delay then self:scheduleBackgroundCatchUp(delay) end
        return
    end
    self._background_readiness_attempt = 0
    if self.bg_fetch_pending or self.bg_fetch_active or self._unit_scan_in_progress
            or self._active_ai_cancel or self.ai_helper._async_child_pid
            or self._background_inflight or (self._background_saving or 0) > 0 then
        self:scheduleBackgroundCatchUp(5)
        return
    end
    local settings = self.ai_helper.settings or {}
    local cooldown = settings.auto_fetch_cooldown or 300
    local ready_at = math.max(queue.retry_at or 0, (queue.last_attempt_at or self.last_bg_fetch_time or 0) + cooldown)
    if ready_at > os.time() then self:scheduleBackgroundCatchUp(ready_at - os.time()); return end
    local target = queue.target.page
    if settings.spoiler_setting ~= "full_book" then target = math.min(target, self.ui:getCurrentPage()) end
    if target <= queue.cursor.page then return end
    if not self.chapter_analyzer then self.chapter_analyzer = require(plugin_path .. "xray_chapteranalyzer"):new() end
    local batch = self.chapter_analyzer:getBackgroundBatch(self.ui, queue.cursor, target, queue.window_pages, queue.chapter_limit)
    if not batch then return end
    local document = self.ui.document
    local title, chapter_page = "Page " .. tostring(batch.end_page), -1
    for _, entry in ipairs(self:_getFlatToc() or {}) do
        local page = tonumber(entry.page)
        if page and page <= batch.end_page and page >= chapter_page then
            title, chapter_page = entry.title, page
        end
    end
    if chapter_page < 0 then chapter_page = batch.end_page end
    local key = tostring(title) .. "_" .. tostring(chapter_page)
    self.fetch_attempts = self.fetch_attempts or {}
    self.fetch_attempts[key] = (self.fetch_attempts[key] or 0) + 1
    self.last_bg_fetch_time = os.time()
    queue.last_attempt_at = self.last_bg_fetch_time
    self._background_inflight = true
    local options = {
        batch = batch, defer_duplicates = true,
        checkpoint = function(data)
            local next_queue = utils:copyTable(self.background_fetch_queue or queue)
            next_queue.cursor = self:backgroundPosition(batch.next_cursor.page)
            next_queue.cursor.chapter_index = batch.next_cursor.chapter_index
            next_queue.has_result = true
            next_queue.retries, next_queue.retry_at, next_queue.paused = 0, nil, nil
            next_queue.window_pages, next_queue.chapter_limit = 60, 200
            if next_queue.cursor.page >= next_queue.target.page then
                data.background_fetch_queue = nil
            else
                data.background_fetch_queue = next_queue
            end
            data.last_fetch_page = batch.next_cursor.page
        end,
        on_done = function(success, code, message)
            self._background_inflight = false
            if not self.ui or self.ui.document ~= document then return end
            local current = self.background_fetch_queue or queue
            if success then
                current.cursor = self:backgroundPosition(batch.next_cursor.page)
                current.cursor.chapter_index = batch.next_cursor.chapter_index
                current.has_result = true
                current.retries, current.retry_at, current.paused = 0, nil, nil
                current.window_pages, current.chapter_limit = 60, 200
                self.last_bg_fetch_page = batch.next_cursor.page
                if current.cursor.page >= current.target.page then
                    self.background_fetch_queue = nil
                    if not self.destroyed and self.runPostFetchDuplicateCheck then
                        local props = document:getProps() or {}
                        local percent = settings.spoiler_setting == "full_book" and 100
                            or math.floor(batch.end_page / document:getPageCount() * 100)
                        self:runPostFetchDuplicateCheck(props.title, props.authors, percent, true)
                    end
                end
            elseif code == "cancelled" then
                -- Lifecycle/manual cancellation pauses execution without consuming retries.
            elseif code == "error_context" then
                if (current.window_pages or 60) <= 1 and (current.chapter_limit or 200) <= 1 then
                    current.paused = "context"
                else
                    current.window_pages = math.max(1, math.floor((current.window_pages or 60) / 2))
                    current.chapter_limit = math.max(1, math.floor((current.chapter_limit or 200) / 2))
                end
            elseif code == "error_auth" or code == "error_config" then
                current.paused = "settings"
            else
                current.retries = (current.retries or 0) + 1
                if current.retries > 3 then current.paused = "retry"
                else current.retry_at = os.time() + math.max(cooldown, 30 * 2 ^ (current.retries - 1)) end
            end
            self:persistBackgroundQueue()
            if not self.destroyed and code ~= "cancelled" then self:scheduleBackgroundCatchUp(2) end
        end,
    }
    local percent = settings.spoiler_setting == "full_book" and 100
        or math.floor(batch.end_page / document:getPageCount() * 100)
    local is_update = queue.has_result or hasBookData(self)
    self:continueWithFetch(percent, is_update, batch.start_page, true, options)
end

function M:onXRaySettingsChanged()
    self.auto_fetch_enabled = self.ai_helper.settings.auto_fetch_on_chapter ~= false
    if self._background_inflight and self.cancelActiveAIRequest then
        self:cancelActiveAIRequest("Background settings changed")
    end
    if not self.auto_fetch_enabled then self:cancelBackgroundSchedule(); return end
    self:wakeBackgroundQueue(true)
end

function M:onResume()
    self:wakeBackgroundQueue()
end

return M
