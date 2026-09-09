require("spec/spec_helper")

local UIManager = require("ui/uimanager")
local XRayPlugin = dofile("xray.koplugin/main.lua")
local utils = require("xray_utils")
local Analyzer = require("xray_chapteranalyzer")

describe("persistent background catch-up", function()
    local plugin, now, page, connected, online, scheduled, requests, disk
    local original_time, original_schedule, original_unschedule, original_network
    local response, failure, fail_start, fail_save, hold_result, save_delay

    local function advance(seconds)
        local target, count = now + seconds, 0
        while true do
            local index
            for i, task in ipairs(scheduled) do
                if task.time <= target and (not index or task.time < scheduled[index].time) then index = i end
            end
            if not index then break end
            local task = table.remove(scheduled, index)
            now = task.time
            task.callback()
            count = count + 1
            assert.is_true(count < 500, "Background callbacks did not settle")
        end
        now = target
    end

    local function offline()
        connected, online = false, false
        plugin:triggerBackgroundMergeFetch("Chapter 3")
        advance(1)
        assert.is_table(plugin.background_fetch_queue)
        assert.are.equal(0, #requests)
    end

    local function reconnect()
        connected, online = true, true
        plugin:onNetworkConnected()
    end

    before_each(function()
        now, page, connected, online = 1000, 165, true, true
        scheduled, requests, disk = {}, {}, {}
        failure, fail_start, fail_save, hold_result = nil, false, false, false
        save_delay = 0.1
        response = { locations = {}, historical_figures = {}, terms = {}, characters = {{ name = "Alice", description = "New knowledge" }},
            timeline = {{ chapter = "Chapter 3", page = 150, event = "An event" }} }
        original_time, original_schedule, original_unschedule = os.time, UIManager.scheduleIn, UIManager.unschedule
        original_network = package.loaded["ui/network/manager"]
        os.time = function() return now end
        UIManager.scheduleIn = function(_, delay, callback)
            scheduled[#scheduled + 1] = { time = now + delay, callback = callback }
        end
        UIManager.unschedule = function(_, callback)
            for i = #scheduled, 1, -1 do
                if scheduled[i].callback == callback then table.remove(scheduled, i) end
            end
        end
        package.loaded["ui/network/manager"] = {
            isConnected = function() return connected end, isOnline = function() return online end,
        }
        plugin = setmetatable(createMockPlugin(), { __index = XRayPlugin })
        plugin.auto_fetch_enabled = true
        plugin.chapters_fetched = {}
        plugin.last_bg_fetch_page = 100
        plugin.timeline = {{ chapter = "Chapter 1", page = 1 }}
        plugin.book_data = { last_fetch_page = 100, timeline = utils:copyTable(plugin.timeline) }
        plugin.chapter_analyzer = Analyzer:new()
        plugin.ui.getCurrentPage = function() return page end
        plugin.ui.document.getPageCount = function() return 300 end
        plugin.ui.document.getToc = function()
            return {{ title = "Chapter 1", page = 1 }, { title = "Chapter 2", page = 100 },
                { title = "Chapter 3", page = 150 }}
        end
        plugin.ui.document.getPageText = function(_, p) return string.rep("Page " .. tostring(p) .. " Alice. ", 20) end
        plugin.cache_manager = {
            loadCache = function() return utils:copyTable(disk) end,
            saveCache = function(_, _, data) disk = utils:copyTable(data); return true end,
            asyncSaveCache = function(_, _, data, callback)
                local snapshot, cancelled = utils:copyTable(data), false
                UIManager:scheduleIn(save_delay, function()
                    if cancelled then return end
                    if not fail_save then disk = snapshot end
                    if callback then callback(not fail_save) end
                end)
                return true, function() cancelled = true; if callback then callback(false) end end
            end,
        }
        plugin.ai_helper.settings = { auto_fetch_page_interval = 20, auto_fetch_cooldown = 0,
            spoiler_setting = "spoiler_free", auto_dupe_check_enabled = false,
            unit_converter_enabled = false, unit_new_feature_prompt_seen = true, language = "book" }
        plugin.ai_helper.hasApiKey = function() return true end
        plugin.ai_helper.buildComprehensiveRequest = function(_, _, _, context)
            requests[#requests + 1] = utils:copyTable(context)
            return {{ url = "https://example.invalid" }}
        end
        plugin.ai_helper.makeRequestAsync = function(self)
            if fail_start then return false end
            self._async_child_pid = 42
            return 42
        end
        plugin.ai_helper.checkAsyncResult = function(self)
            if hold_result then return nil end
            self._async_child_pid = nil
            if failure then return false, failure, "injected failure" end
            return utils:copyTable(response)
        end
        plugin.ai_helper.cancelAsyncChild = function(self) self._async_child_pid = nil end
        plugin.runPostFetchDuplicateCheck = function(self) self.duplicate_checks = (self.duplicate_checks or 0) + 1 end
        plugin.checkSeriesContext = function(self) self.series_checks = (self.series_checks or 0) + 1 end
        plugin.closeAllMenus = function() end
        plugin.clearHighlightOverlay = function() end
        plugin.clearUnitUnderlines = function() end
        plugin.clearTileCaches = function() end
    end)

    after_each(function()
        os.time, UIManager.scheduleIn, UIManager.unschedule = original_time, original_schedule, original_unschedule
        package.loaded["ui/network/manager"] = original_network
    end)

    it("runs the real extraction, merge and completion path across a 65-page backlog", function()
        offline()
        reconnect()
        advance(5)
        assert.are.equal(160, disk.last_fetch_page)
        assert.are.equal(165, disk.background_fetch_queue.target.page)
        advance(5)
        assert.are.equal(2, #requests)
        assert.are.equal(165, disk.last_fetch_page)
        assert.is_nil(disk.background_fetch_queue)
        assert.is_nil(plugin.background_fetch_queue)
        assert.are.equal(1, plugin.duplicate_checks)
        assert.are.equal("Alice", requests[2].existing_characters[1].name)
    end)

    it("coalesces missed intervals and repeated reconnect events", function()
        connected, online = false, false
        for _, p in ipairs({120, 140, 165}) do page = p; plugin:onPageUpdate(p); advance(2) end
        reconnect(); reconnect(); reconnect()
        advance(15)
        assert.are.equal(2, #requests)
        assert.are.equal(3, plugin.series_checks)
    end)

    it("handles chapter-based triggers", function()
        plugin.ai_helper.settings.auto_fetch_page_interval = nil
        connected, online = false, false
        plugin:onPageUpdate(page)
        advance(2)
        reconnect(); advance(15)
        assert.are.equal(165, disk.last_fetch_page)
    end)

    it("does not fetch on reconnect without work", function()
        reconnect(); advance(20)
        assert.are.equal(0, #requests)
        assert.are.equal(1, plugin.series_checks)
    end)

    it("honors cooldown between batches without page turns", function()
        plugin.ai_helper.settings.auto_fetch_cooldown = 30
        plugin.last_bg_fetch_time = now
        offline(); reconnect(); advance(28)
        assert.are.equal(0, #requests)
        advance(2); assert.are.equal(1, #requests)
        advance(30); assert.are.equal(2, #requests)
    end)

    for _, field in ipairs({ "bg_fetch_pending", "bg_fetch_active", "_unit_scan_in_progress", "_active_ai_cancel", "_async_child_pid" }) do
        it("waits while " .. field .. " owns the reader", function()
            offline()
            local owner = field == "_async_child_pid" and plugin.ai_helper or plugin
            owner[field] = true
            reconnect(); advance(7)
            assert.are.equal(0, #requests)
            owner[field] = nil
            advance(15)
            assert.are.equal(165, disk.last_fetch_page)
        end)
    end

    it("retains offline work without polling", function()
        offline(); advance(120)
        assert.are.equal(0, #scheduled)
        assert.is_table(disk.background_fetch_queue)
    end)

    it("retries internet readiness after Wi-Fi connects", function()
        offline(); reconnect(); online = false
        advance(3); online = true
        advance(15)
        assert.are.equal(165, disk.last_fetch_page)
    end)

    it("bounds readiness retries and wakes again on resume", function()
        offline(); reconnect(); online = false
        advance(65)
        assert.are.equal(0, #scheduled)
        online = true; plugin:onResume(); advance(15)
        assert.are.equal(165, disk.last_fetch_page)
    end)

    it("pauses without credentials and resumes after settings change", function()
        offline(); plugin.ai_helper.hasApiKey = function() return false end
        reconnect(); advance(15)
        assert.are.equal(0, #requests)
        plugin.ai_helper.hasApiKey = function() return true end
        plugin:onXRaySettingsChanged(); advance(15)
        assert.are.equal(165, disk.last_fetch_page)
    end)

    it("retains work while disabled", function()
        offline(); plugin.ai_helper.settings.auto_fetch_on_chapter = false
        plugin:onXRaySettingsChanged(); reconnect(); advance(15)
        assert.are.equal(0, #requests)
        assert.is_table(disk.background_fetch_queue)
        plugin.ai_helper.settings.auto_fetch_on_chapter = true
        plugin:onXRaySettingsChanged(); advance(15)
        assert.are.equal(165, disk.last_fetch_page)
    end)

    it("defers ranges past the current spoiler boundary", function()
        offline(); page = 130; reconnect(); advance(15)
        assert.are.equal(130, disk.last_fetch_page)
        assert.are.equal(165, disk.background_fetch_queue.target.page)
        page = 165; plugin:onPageUpdate(page); advance(15)
        assert.are.equal(165, disk.last_fetch_page)
    end)

    it("keeps the full-book target across sequential requests", function()
        plugin.ai_helper.settings.spoiler_setting = "full_book"
        offline(); reconnect(); advance(30)
        assert.are.equal(300, disk.last_fetch_page)
        for _, request in ipairs(requests) do assert.are.equal(100, request.reading_percent) end
        assert.are.equal(1, plugin.duplicate_checks)
    end)

    it("initializes without a timeline and merges later batches", function()
        plugin.timeline, plugin.book_data = {}, nil
        plugin.ui.document.getToc = function() return {} end
        offline(); reconnect(); advance(25)
        assert.is_nil(requests[1].existing_characters)
        assert.are.equal("Alice", requests[2].existing_characters[1].name)
        assert.are.equal(165, disk.last_fetch_page)
    end)

    for _, code in ipairs({ "error_api", "error_empty", "error_start", "error_extract" }) do
        it("retains and retries " .. code .. " without advancing", function()
            offline()
            if code == "error_empty" then response = {}
            elseif code == "error_start" then fail_start = true
            elseif code == "error_extract" then plugin.chapter_analyzer.getTextForAnalysis = function() error("extraction failed") end
            else failure = code end
            reconnect(); advance(10)
            assert.are.equal(100, disk.last_fetch_page)
            assert.are.equal(100, plugin.background_fetch_queue.cursor.page)
            assert.are.equal(1, plugin.background_fetch_queue.retries)
        end)
    end

    it("waits for the cache callback before advancing", function()
        offline(); save_delay = 10; reconnect(); advance(5)
        assert.are.equal(100, disk.last_fetch_page)
        assert.are.equal(100, plugin.background_fetch_queue.cursor.page)
        assert.is_true(plugin.bg_fetch_active)
        advance(10)
        assert.are.equal(160, disk.last_fetch_page)
    end)

    it("rolls back merged data and progress if the cache write fails", function()
        offline(); fail_save = true; reconnect(); advance(5)
        assert.are.equal(100, disk.last_fetch_page)
        assert.are.equal(100, plugin.book_data.last_fetch_page)
        assert.are.equal(0, #plugin.characters)
        assert.are.equal(100, plugin.background_fetch_queue.cursor.page)
    end)

    it("limits transient failures to three retries", function()
        offline(); failure = "error_api"; reconnect(); advance(300)
        assert.are.equal(4, #requests)
        assert.are.equal("retry", plugin.background_fetch_queue.paused)
    end)

    for _, code in ipairs({ "error_auth", "error_config" }) do
        it("pauses " .. code .. " until settings change", function()
            offline(); failure = code; reconnect(); advance(120)
            assert.are.equal(1, #requests)
            reconnect(); advance(10); assert.are.equal(1, #requests)
            failure = nil; plugin:onXRaySettingsChanged(); advance(15)
            assert.are.equal(165, disk.last_fetch_page)
        end)
    end

    it("splits oversized batches and pauses an irreducible request", function()
        offline(); failure = "error_context"; reconnect(); advance(80)
        assert.are.equal(100, disk.last_fetch_page)
        assert.are.equal(1, plugin.background_fetch_queue.window_pages)
        assert.are.equal(1, plugin.background_fetch_queue.chapter_limit)
        assert.are.equal("context", plugin.background_fetch_queue.paused)
    end)

    it("suspends an active request and resumes its unfinished batch", function()
        offline(); hold_result = true; reconnect(); advance(3)
        plugin:onSuspend()
        assert.is_nil(plugin.ai_helper._async_child_pid)
        assert.are.equal(100, disk.background_fetch_queue.cursor.page)
        hold_result = false; plugin:onResume(); advance(15)
        assert.are.equal(165, disk.last_fetch_page)
    end)

    it("cancels a pending result save on suspend", function()
        offline(); save_delay = 10; reconnect(); advance(5)
        plugin:onSuspend(); advance(12)
        assert.are.equal(100, disk.last_fetch_page)
        assert.are.equal(100, disk.background_fetch_queue.cursor.page)
    end)

    it("restores per-book work and ignores a different document identity", function()
        offline()
        plugin.background_fetch_queue = nil
        plugin.book_data = utils:copyTable(disk)
        plugin:restoreBackgroundQueue()
        assert.are.equal(165, plugin.background_fetch_queue.target.page)
        plugin.ui.document.file = "other.epub"
        plugin:restoreBackgroundQueue()
        assert.is_nil(plugin.background_fetch_queue)
    end)

    it("remaps persisted XPointers after repagination", function()
        plugin.ui.rolling = {}
        plugin.ui.document.getPageXPointer = function(_, p) return "xp" .. p end
        offline()
        plugin.ui.document.getPageCount = function() return 600 end
        plugin.ui.document.getPageFromXPointer = function(_, xp) return tonumber(xp:match("%d+")) * 2 end
        plugin:restoreBackgroundQueue()
        assert.are.equal(199, plugin.background_fetch_queue.cursor.page)
        assert.are.equal(330, plugin.background_fetch_queue.target.page)
    end)

    it("ignores delayed callbacks after the document changes", function()
        offline(); reconnect()
        plugin.ui.document = { file = "other.epub" }
        advance(15)
        assert.are.equal(0, #requests)
    end)

    it("retains eligible reading added while a request runs", function()
        offline(); hold_result = true; reconnect(); advance(3)
        page = 220; plugin:onPageUpdate(page)
        hold_result = false; advance(30)
        assert.are.equal(220, disk.last_fetch_page)
    end)

    it("extends pending catch-up to the reconnect position without another interval", function()
        page = 160; offline()
        page = 165; reconnect(); advance(20)
        assert.are.equal(165, disk.last_fetch_page)
    end)

    it("lets a manual request cancel a batch and resumes after manual completion", function()
        offline(); hold_result = true; reconnect(); advance(3)
        plugin:continueWithFetch(55, true, 100, false)
        assert.is_false(plugin._background_inflight)
        hold_result = false; advance(25)
        assert.are.equal(165, disk.last_fetch_page)
        assert.is_nil(plugin.background_fetch_queue)
    end)

    it("flushes queued work on close and restores it after reader-ready", function()
        offline(); plugin:onCloseDocument()
        assert.are.equal(165, disk.background_fetch_queue.target.page)
        plugin.destroyed = false
        plugin.autoLoadCache = function(self) self.book_data = utils:copyTable(disk) end
        plugin.applyLanguageLogic = function() end
        plugin:onReaderReady()
        reconnect(); advance(15)
        assert.are.equal(165, disk.last_fetch_page)
    end)

    it("ignores malformed queue metadata", function()
        plugin.book_data.background_fetch_queue = { version = 1, cursor = { page = "wrong" }, target = {} }
        plugin:restoreBackgroundQueue()
        assert.is_nil(plugin.background_fetch_queue)
    end)

    it("merges later batches even when the first response has no timeline", function()
        plugin.timeline, plugin.book_data = {}, nil
        response.timeline = {}
        offline(); reconnect(); advance(5)
        assert.are.equal("Alice", plugin.characters[1].name)
        response.characters = {{ name = "Bob", description = "Later knowledge" }}
        advance(20)
        assert.are.equal("Alice", requests[2].existing_characters[1].name)
        local names = {}
        for _, character in ipairs(plugin.characters) do names[character.name] = true end
        assert.is_true(names.Alice)
        assert.is_true(names.Bob)
    end)

    it("commits the final result and removes its queue in the same snapshot", function()
        page = 130; offline()
        local result_snapshot
        local save = plugin.cache_manager.asyncSaveCache
        plugin.cache_manager.asyncSaveCache = function(self, file, data, callback)
            if data.last_fetch_page == 130 then result_snapshot = utils:copyTable(data) end
            return save(self, file, data, callback)
        end
        reconnect(); advance(5)
        assert.are.equal(130, result_snapshot.last_fetch_page)
        assert.is_nil(result_snapshot.background_fetch_queue)
    end)

    it("uses title and chapter page as the retry identity", function()
        offline(); reconnect(); advance(3)
        assert.are.equal(1, plugin.fetch_attempts["Chapter 3_150"])
        assert.is_nil(plugin.fetch_attempts["Chapter 3"])
    end)
end)
