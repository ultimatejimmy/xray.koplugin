require("spec/spec_helper")

local UIManager = require("ui/uimanager")
local XRayPlugin = dofile("xray.koplugin/main.lua")

describe("X-Ray Background Catch-Up", function()
    local plugin, requests, scheduled
    local now, current_page, connected, online, has_key, total_pages
    local original_time, original_schedule, original_unschedule, original_network

    local function advance(seconds)
        local target = now + seconds
        local count = 0
        while true do
            local next_index
            for i, task in ipairs(scheduled) do
                if task.time <= target and (not next_index or task.time < scheduled[next_index].time) then
                    next_index = i
                end
            end
            if not next_index then break end
            local task = table.remove(scheduled, next_index)
            now = task.time
            task.callback()
            count = count + 1
            assert.is_true(count < 100, "Scheduled callbacks did not settle")
        end
        now = target
    end

    local function skipOfflineFetch()
        connected, online = false, false
        plugin:triggerBackgroundMergeFetch("Chapter 2")
        assert.is_true(plugin.pending_background_fetch)
        assert.are.equal(0, #requests)
    end

    local function reconnect()
        connected, online = true, true
        plugin:onNetworkConnected()
    end

    before_each(function()
        now, current_page, total_pages = 1000, 165, 300
        connected, online, has_key = true, true, true
        requests, scheduled = {}, {}
        original_time = os.time
        original_schedule = UIManager.scheduleIn
        original_unschedule = UIManager.unschedule
        original_network = package.loaded["ui/network/manager"]
        os.time = function() return now end
        UIManager.scheduleIn = function(_, delay, callback)
            table.insert(scheduled, { time = now + delay, callback = callback })
        end
        UIManager.unschedule = function(_, callback)
            for i = #scheduled, 1, -1 do
                if scheduled[i].callback == callback then table.remove(scheduled, i) end
            end
        end
        package.loaded["ui/network/manager"] = {
            isConnected = function() return connected end,
            isOnline = function() return online end,
        }

        plugin = setmetatable({
            destroyed = false,
            auto_fetch_enabled = true,
            bg_fetch_pending = false,
            bg_fetch_active = false,
            pending_background_fetch = false,
            last_bg_fetch_page = 100,
            chapters_fetched = {},
            timeline = { { chapter = "Chapter 1", page = 1 } },
            book_data = { last_fetch_page = 100 },
            ai_helper = {
                settings = { auto_fetch_page_interval = 20, auto_fetch_cooldown = 0 },
                hasApiKey = function() return has_key end,
            },
            ui = {
                getCurrentPage = function() return current_page end,
                document = {
                    file = "catch-up.epub",
                    getPageCount = function() return total_pages end,
                    getToc = function()
                        return {
                            { title = "Chapter 1", page = 1 },
                            { title = "Chapter 2", page = 100 },
                            { title = "Chapter 3", page = 150 },
                        }
                    end,
                },
            },
            log = function() end,
            checkSeriesContext = function(self)
                self.series_checks = (self.series_checks or 0) + 1
            end,
            continueWithFetch = function(self, reading_percent, is_update, last_fetch_page, is_silent)
                table.insert(requests, {
                    page = current_page,
                    reading_percent = reading_percent,
                    is_update = is_update,
                    last_fetch_page = last_fetch_page,
                    is_silent = is_silent,
                })
                self.bg_fetch_active = true
            end,
            cancelActiveAIRequest = function() end,
            closeAllMenus = function() end,
            clearHighlightOverlay = function() end,
            clearUnitUnderlines = function() end,
            clearTileCaches = function() end,
        }, { __index = XRayPlugin })
    end)

    after_each(function()
        os.time = original_time
        UIManager.scheduleIn = original_schedule
        UIManager.unschedule = original_unschedule
        package.loaded["ui/network/manager"] = original_network
    end)

    it("catches up several missed page intervals with one silent incremental fetch", function()
        connected, online = false, false
        for _, page in ipairs({ 120, 140, 160 }) do
            current_page = page
            plugin:onPageUpdate(page)
            advance(2)
            assert.is_true(plugin.pending_background_fetch)
            assert.is_false(plugin.bg_fetch_pending)
        end
        assert.are.equal(0, #requests)
        assert.is_nil(plugin.fetch_attempts)
        assert.is_nil(plugin.last_bg_fetch_time)

        current_page = 165
        reconnect()
        advance(2)

        assert.are.same({ {
            page = 165,
            reading_percent = 55,
            is_update = true,
            last_fetch_page = 100,
            is_silent = true,
        } }, requests)
        assert.are.equal(1, plugin.fetch_attempts["Chapter 3"])
        assert.are.equal(165, plugin.last_bg_fetch_page)
        assert.is_false(plugin.pending_background_fetch)
        assert.is_nil(plugin._background_catch_up_callback)
    end)

    it("also catches up missed chapter-based updates", function()
        plugin.ai_helper.settings.auto_fetch_page_interval = nil
        connected, online = false, false
        for _, page in ipairs({ 120, 160 }) do
            current_page = page
            plugin:onPageUpdate(page)
            advance(2)
        end
        assert.is_true(plugin.pending_background_fetch)
        current_page = 165
        reconnect()
        advance(2)
        assert.are.equal(1, #requests)
        assert.are.equal(100, requests[1].last_fetch_page)
    end)

    it("coalesces repeated reconnect events and preserves series context checks", function()
        skipOfflineFetch()
        reconnect()
        local callback = plugin._background_catch_up_callback
        reconnect()
        reconnect()
        assert.are.equal(callback, plugin._background_catch_up_callback)
        advance(2)
        assert.are.equal(1, #requests)
        assert.are.equal(3, plugin.series_checks)

        plugin.bg_fetch_active = false
        reconnect()
        advance(10)
        assert.are.equal(1, #requests)
        assert.are.equal(4, plugin.series_checks)
    end)

    it("does not fetch on reconnect without an offline skip", function()
        reconnect()
        advance(10)
        assert.are.equal(0, #requests)
        assert.are.equal(1, plugin.series_checks)
        assert.is_nil(plugin._background_catch_up_callback)
    end)

    it("waits for the remaining cooldown without another page turn", function()
        plugin.ai_helper.settings.auto_fetch_cooldown = 30
        plugin.last_bg_fetch_time = now
        skipOfflineFetch()
        reconnect()
        advance(2)
        assert.are.equal(1000, plugin.last_bg_fetch_time)
        assert.is_true(plugin.pending_background_fetch)
        advance(27)
        assert.are.equal(0, #requests)
        advance(1)
        assert.are.equal(1, #requests)
        assert.are.equal(1030, plugin.last_bg_fetch_time)
    end)

    for _, busy_field in ipairs({
        "bg_fetch_pending", "bg_fetch_active", "_unit_scan_in_progress", "_active_ai_cancel", "_async_child_pid",
    }) do
        it("waits for " .. busy_field .. " without another page turn", function()
            skipOfflineFetch()
            local owner = busy_field == "_async_child_pid" and plugin.ai_helper or plugin
            owner[busy_field] = true
            reconnect()
            advance(7)
            assert.are.equal(0, #requests)
            assert.is_true(plugin.pending_background_fetch)
            assert.is_nil(plugin.last_bg_fetch_time)

            owner[busy_field] = nil
            current_page = 170
            advance(5)
            assert.are.equal(1, #requests)
            assert.are.equal(170, requests[1].page)
        end)
    end

    it("lets a scheduled normal fetch satisfy the pending catch-up", function()
        skipOfflineFetch()
        reconnect()
        current_page = 180
        plugin:onPageUpdate(current_page)
        advance(2)
        assert.are.equal(1, #requests)
        assert.is_false(plugin.pending_background_fetch)
        assert.is_nil(plugin._background_catch_up_callback)

        plugin.bg_fetch_active = false
        advance(10)
        assert.are.equal(1, #requests)
    end)

    it("does not turn an online busy skip into deferred offline work", function()
        plugin._active_ai_cancel = function() end
        plugin:triggerBackgroundMergeFetch("Chapter 3")
        assert.is_false(plugin.pending_background_fetch)
        assert.is_nil(plugin.last_bg_fetch_time)
        plugin._active_ai_cancel = nil
        reconnect()
        advance(2)
        assert.are.equal(0, #requests)
    end)

    it("does not race a normal fetch deferred by a unit scan", function()
        skipOfflineFetch()
        plugin._unit_scan_in_progress = true
        reconnect()
        advance(2)
        current_page = 180
        plugin:onPageUpdate(current_page)
        advance(2)
        assert.is_true(plugin.bg_fetch_pending)

        plugin._unit_scan_in_progress = false
        advance(3)
        assert.are.equal(0, #requests)
        advance(2)
        assert.are.equal(1, #requests)
        assert.is_false(plugin.bg_fetch_pending)
        assert.is_false(plugin.pending_background_fetch)
        plugin.bg_fetch_active = false
        advance(5)
        assert.are.equal(1, #requests)
    end)

    for _, state in ipairs({ "disconnected", "connected without internet" }) do
        it("retains pending work without polling when " .. state, function()
            skipOfflineFetch()
            reconnect()
            connected = state ~= "disconnected"
            online = false
            advance(60)
            assert.are.equal(0, #requests)
            assert.is_true(plugin.pending_background_fetch)
            assert.is_nil(plugin._background_catch_up_callback)
            assert.are.equal(0, #scheduled)

            reconnect()
            advance(2)
            assert.are.equal(1, #requests)
        end)
    end

    it("stops waiting if connectivity disappears during cooldown", function()
        plugin.ai_helper.settings.auto_fetch_cooldown = 10
        plugin.last_bg_fetch_time = now
        skipOfflineFetch()
        reconnect()
        advance(2)
        connected, online = false, false
        advance(8)
        assert.are.equal(0, #requests)
        assert.is_true(plugin.pending_background_fetch)
        assert.is_nil(plugin._background_catch_up_callback)
        reconnect()
        advance(2)
        assert.are.equal(1, #requests)
    end)

    it("clears deferred work when automatic fetching is disabled", function()
        skipOfflineFetch()
        reconnect()
        plugin.auto_fetch_enabled = false
        advance(2)
        assert.are.equal(0, #requests)
        assert.is_false(plugin.pending_background_fetch)
        assert.is_nil(plugin._background_catch_up_callback)
    end)

    it("rechecks enablement before a delayed normal background fetch", function()
        current_page = 120
        plugin:onPageUpdate(current_page)
        plugin.auto_fetch_enabled = false
        connected, online = false, false
        advance(2)
        assert.are.equal(0, #requests)
        assert.is_false(plugin.pending_background_fetch)
    end)

    it("cancels catch-up on a page update after automatic fetching is disabled", function()
        skipOfflineFetch()
        reconnect()
        plugin.auto_fetch_enabled = false
        plugin:onPageUpdate(current_page)
        assert.is_false(plugin.pending_background_fetch)
        assert.is_nil(plugin._background_catch_up_callback)
        advance(2)
        assert.are.equal(0, #requests)
    end)

    it("does not consume pending work or schedule retries without credentials", function()
        skipOfflineFetch()
        reconnect()
        has_key = false
        advance(10)
        assert.are.equal(0, #requests)
        assert.is_true(plugin.pending_background_fetch)
        assert.is_nil(plugin._background_catch_up_callback)
        assert.is_nil(plugin.last_bg_fetch_time)
    end)

    for _, page in ipairs({ 100, 90 }) do
        it("clears deferred work when the current page is already covered: " .. page, function()
            skipOfflineFetch()
            reconnect()
            current_page = page
            advance(2)
            assert.are.equal(0, #requests)
            assert.is_false(plugin.pending_background_fetch)
        end)
    end

    it("discards catch-up when a manual fetch covers the current position while waiting", function()
        skipOfflineFetch()
        plugin._active_ai_cancel = function() end
        reconnect()
        advance(2)
        plugin.book_data.last_fetch_page = current_page
        plugin._active_ai_cancel = nil
        advance(5)
        assert.are.equal(0, #requests)
        assert.is_false(plugin.pending_background_fetch)
        assert.is_nil(plugin._background_catch_up_callback)
    end)

    it("uses an initial fetch and a page label when there is no cache or TOC", function()
        plugin.book_data = nil
        plugin.timeline = {}
        plugin.last_bg_fetch_page = nil
        plugin.ui.document.getToc = function() return {} end
        connected, online = false, false
        plugin:onPageUpdate(current_page)
        advance(2)
        assert.is_true(plugin.pending_background_fetch)
        reconnect()
        advance(2)
        assert.are.equal(1, #requests)
        assert.is_false(requests[1].is_update)
        assert.is_nil(requests[1].last_fetch_page)
        assert.are.equal(1, plugin.fetch_attempts["Page 165"])
    end)

    it("preserves the full-book spoiler setting", function()
        plugin.ai_helper.settings.spoiler_setting = "full_book"
        skipOfflineFetch()
        reconnect()
        advance(2)
        assert.are.equal(100, requests[1].reading_percent)
    end)

    it("does not consume deferred work when page count is unavailable", function()
        skipOfflineFetch()
        reconnect()
        total_pages = 0
        advance(2)
        assert.are.equal(0, #requests)
        assert.is_true(plugin.pending_background_fetch)
        assert.is_nil(plugin.last_bg_fetch_time)
    end)

    it("cancels catch-up when the document closes", function()
        skipOfflineFetch()
        reconnect()
        local callback = plugin._background_catch_up_callback
        plugin:onCloseDocument()
        assert.is_true(plugin.destroyed)
        assert.is_false(plugin.pending_background_fetch)
        assert.is_nil(plugin._background_catch_up_callback)
        callback()
        advance(10)
        assert.are.equal(0, #requests)
        assert.is_nil(plugin.series_checks)
    end)

    it("resets catch-up when the reader becomes ready for a document", function()
        skipOfflineFetch()
        reconnect()
        local callback = plugin._background_catch_up_callback
        plugin.autoLoadCache = function() end
        plugin.applyLanguageLogic = function() end
        plugin:onReaderReady()
        assert.is_false(plugin.pending_background_fetch)
        assert.is_nil(plugin._background_catch_up_callback)
        callback()
        assert.are.equal(0, #requests)
    end)

    it("ignores catch-up callbacks after the document changes or disappears", function()
        skipOfflineFetch()
        reconnect()
        plugin.ui.document = { file = "another-book.epub" }
        advance(2)
        assert.are.equal(0, #requests)
        reconnect()
        plugin.ui.document = nil
        advance(2)
        assert.are.equal(0, #requests)
    end)
end)
