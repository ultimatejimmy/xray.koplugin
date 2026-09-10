require("spec.spec_helper")

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
            assert.is_true(count < 200, "Scheduled callbacks did not settle")
        end
        now = target
    end

    local function skipOfflineFetch(chapter_title)
        connected, online = false, false
        plugin:triggerBackgroundMergeFetch(chapter_title or "Chapter 2")
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
            last_bg_fetch_time = nil,
            chapters_fetched = {},
            timeline = { { chapter = "Chapter 1", page = 1 } },
            book_data = { last_fetch_page = 100 },
            ai_helper = {
                settings = { auto_fetch_page_interval = 20, auto_fetch_cooldown = 60 },
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
                            { title = "Chapter 2", page = 50 },
                            { title = "Chapter 3", page = 100 },
                            { title = "Chapter 4", page = 130 },
                            { title = "Chapter 5", page = 150 },
                            { title = "Chapter 6", page = 165 },
                            { title = "Chapter 7", page = 200 },
                        }
                    end,
                },
            },
            loc = {
                t = function(k, ...) return k end
            },
            log = function() end,
            checkSeriesContext = function(self)
                self.series_checks = (self.series_checks or 0) + 1
            end,
            continueWithFetch = function(self, reading_percent, is_update, last_fetch_page, is_silent, batch_end_page, on_complete_cb)
                table.insert(requests, {
                    reading_percent = reading_percent,
                    is_update = is_update,
                    last_fetch_page = last_fetch_page,
                    is_silent = is_silent,
                    batch_end_page = batch_end_page,
                })
                self.bg_fetch_active = true
                -- Simulate asynchronous completion after 1s
                UIManager:scheduleIn(1, function()
                    self.bg_fetch_active = false
                    if self.book_data then
                        self.book_data.last_fetch_page = batch_end_page or current_page
                    end
                    if on_complete_cb then
                        on_complete_cb(true)
                    end
                end)
            end,
            cancelActiveAIRequest = function() end,
            closeAllMenus = function() end,
            isNonNarrativeChapter = function(self, title)
                return false
            end,
        }, { __index = XRayPlugin })
    end)

    after_each(function()
        os.time = original_time
        UIManager.scheduleIn = original_schedule
        UIManager.unschedule = original_unschedule
        package.loaded["ui/network/manager"] = original_network
    end)

    it("flags pending_background_fetch when triggerBackgroundMergeFetch is offline", function()
        connected, online = false, false
        plugin:triggerBackgroundMergeFetch("Chapter 4")
        assert.is_true(plugin.pending_background_fetch)
        assert.are.equal(0, #requests)
    end)

    it("does not fetch on reconnect when no offline skip occurred", function()
        reconnect()
        advance(10)
        assert.are.equal(0, #requests)
        assert.are.equal(1, plugin.series_checks)
        assert.is_nil(plugin._background_catch_up_callback)
    end)

    it("catches up small backlog in a single fetch upon reconnecting", function()
        -- last_fetch_page = 100, current_page = 165 (Chapters 4, 5, 6 = 3 chapters <= 4 limit)
        skipOfflineFetch("Chapter 4")
        reconnect()
        advance(5)

        assert.are.equal(1, #requests)
        assert.are.equal(100, requests[1].last_fetch_page)
        assert.are.equal(165, requests[1].batch_end_page)
        assert.is_true(requests[1].is_silent)
        assert.is_true(requests[1].is_update)

        -- Advance past completion
        advance(5)
        assert.are.equal(165, plugin.book_data.last_fetch_page)
        assert.is_false(plugin.pending_background_fetch)
    end)

    it("chunks large backlog into progressive batches of 4 chapters", function()
        -- Book TOC has 10 chapters, user read from page 10 up to page 280
        plugin.book_data.last_fetch_page = 10
        current_page = 280
        plugin.ui.document.getToc = function()
            local toc = {}
            for i = 1, 10 do
                table.insert(toc, { title = "Chapter " .. i, page = (i - 1) * 30 + 1 })
            end
            return toc
        end

        skipOfflineFetch("Chapter 2")
        reconnect()

        -- Initial delay: 3s + fetch async execution: 1s
        advance(5)
        -- First batch runs through Chapter 5 (which ends at page 150, right before Chapter 6 at 151)
        assert.are.equal(1, #requests)
        assert.are.equal(10, requests[1].last_fetch_page)
        assert.are.equal(150, requests[1].batch_end_page)
        assert.are.equal(150, plugin.book_data.last_fetch_page)

        -- Now wait proper cooldown (15s)
        advance(10)
        assert.are.equal(1, #requests) -- Still in cooldown!
        advance(6) -- Cooldown expires, batch 2 executes

        -- Second batch runs through Chapter 9 (which ends at page 270, right before Chapter 10 at 271)
        assert.are.equal(2, #requests)
        assert.are.equal(150, requests[2].last_fetch_page)
        assert.are.equal(270, requests[2].batch_end_page)
        assert.are.equal(270, plugin.book_data.last_fetch_page)

        -- Advance another cooldown for final batch up to current_page (280)
        advance(20)
        assert.are.equal(3, #requests)
        assert.are.equal(270, requests[3].last_fetch_page)
        assert.are.equal(280, requests[3].batch_end_page)

        advance(5)
        assert.are.equal(280, plugin.book_data.last_fetch_page)
        assert.is_false(plugin.pending_background_fetch)
    end)

    it("coalesces repeated reconnect events without stacking requests", function()
        skipOfflineFetch("Chapter 4")
        reconnect()
        local cb = plugin._background_catch_up_callback
        reconnect()
        reconnect()
        assert.are.equal(cb, plugin._background_catch_up_callback)
        advance(5)
        assert.are.equal(1, #requests)
        assert.are.equal(3, plugin.series_checks)
    end)

    it("reschedules catch-up when unit scan is active", function()
        skipOfflineFetch("Chapter 4")
        plugin._unit_scan_in_progress = true
        reconnect()
        advance(5)
        assert.are.equal(0, #requests) -- deferred!
        assert.is_true(plugin.pending_background_fetch)

        plugin._unit_scan_in_progress = false
        advance(12)
        assert.are.equal(1, #requests)
    end)

    it("reschedules catch-up when another AI request is active", function()
        skipOfflineFetch("Chapter 4")
        plugin._active_ai_cancel = function() end
        reconnect()
        advance(5)
        assert.are.equal(0, #requests) -- deferred!

        plugin._active_ai_cancel = nil
        advance(12)
        assert.are.equal(1, #requests)
    end)

    it("clears pending catch-up when current page is already covered", function()
        skipOfflineFetch("Chapter 4")
        current_page = 100 -- same as last_fetch_page
        reconnect()
        advance(5)
        assert.are.equal(0, #requests)
        assert.is_false(plugin.pending_background_fetch)
    end)

    it("clears pending catch-up when auto_fetch_enabled is false", function()
        skipOfflineFetch("Chapter 4")
        plugin.auto_fetch_enabled = false
        reconnect()
        advance(5)
        assert.are.equal(0, #requests)
        assert.is_false(plugin.pending_background_fetch)
    end)

    it("cancels pending catch-up callback when document is closed or plugin destroyed", function()
        skipOfflineFetch("Chapter 4")
        reconnect()
        plugin:clearPendingBackgroundFetch()
        assert.is_false(plugin.pending_background_fetch)
        assert.is_nil(plugin._background_catch_up_callback)
        advance(10)
        assert.are.equal(0, #requests)
    end)

    it("preserves full_book spoiler setting during catch-up", function()
        plugin.ai_helper.settings.spoiler_setting = "full_book"
        skipOfflineFetch("Chapter 4")
        reconnect()
        advance(5)
        assert.are.equal(1, #requests)
        assert.are.equal(100, requests[1].reading_percent)
    end)

    it("handles flat books without TOC by chunking pages in batches of 50", function()
        plugin.ui.document.getToc = function() return {} end
        plugin.book_data.last_fetch_page = 10
        current_page = 120 -- diff = 110 > 50

        skipOfflineFetch("Page 20")
        reconnect()
        advance(5)

        assert.are.equal(1, #requests)
        assert.are.equal(10, requests[1].last_fetch_page)
        assert.are.equal(60, requests[1].batch_end_page) -- 10 + 50 = 60
    end)

    it("chains consecutive catch-up batches in full_book mode until entire book is fetched", function()
        plugin.ai_helper.settings.spoiler_setting = "full_book"
        plugin.book_data.last_fetch_page = 0
        current_page = 50 -- reader is only on chapter 2, but full_book targets 300
        plugin.pending_background_fetch = true

        plugin:scheduleBackgroundCatchUp(0)
        advance(1) -- batch 1 starts
        assert.are.equal(1, #requests)
        assert.are.equal(0, requests[1].last_fetch_page)
        assert.are.equal(149, requests[1].batch_end_page)

        -- Complete batch 1
        advance(1)
        assert.are.equal(149, plugin.book_data.last_fetch_page)
        assert.is_true(plugin.pending_background_fetch)

        -- Cooldown: advance 10s (not enough, cooldown is 15s)
        advance(10)
        assert.are.equal(1, #requests)

        -- Advance past 15s cooldown -> batch 2 fires
        advance(6)
        assert.are.equal(2, #requests)
        assert.are.equal(149, requests[2].last_fetch_page)
        assert.are.equal(300, requests[2].batch_end_page)

        -- Complete batch 2
        advance(1)
        assert.are.equal(300, plugin.book_data.last_fetch_page)
        assert.is_false(plugin.pending_background_fetch)
    end)

    it("chains direct background fetch into catch-up when reader is multiple batches ahead", function()
        plugin.book_data.last_fetch_page = 0
        current_page = 200 -- Chapter 7 (7 chapters ahead, limit is 4 per batch)
        plugin.last_bg_fetch_time = nil

        plugin:triggerBackgroundMergeFetch("Chapter 7")
        assert.are.equal(1, #requests)
        assert.are.equal(0, requests[1].last_fetch_page)
        assert.are.equal(149, requests[1].batch_end_page)

        -- Complete batch 1
        advance(1)
        assert.are.equal(149, plugin.book_data.last_fetch_page)
        assert.is_true(plugin.pending_background_fetch)

        -- Advance past cooldown to trigger batch 2
        advance(20)
        assert.are.equal(2, #requests)
        assert.are.equal(149, requests[2].last_fetch_page)
        assert.are.equal(200, requests[2].batch_end_page)

        -- Complete batch 2
        advance(1)
        assert.are.equal(200, plugin.book_data.last_fetch_page)
        assert.is_false(plugin.pending_background_fetch)
    end)

    it("triggers and chains catch-up on network restoration in full_book mode without prior offline flag", function()
        plugin.ai_helper.settings.spoiler_setting = "full_book"
        plugin.book_data.last_fetch_page = 50
        current_page = 50
        plugin.pending_background_fetch = false

        -- WiFi connects
        reconnect()
        assert.is_true(plugin.pending_background_fetch)

        advance(5)
        assert.are.equal(1, #requests)
        assert.are.equal(50, requests[1].last_fetch_page)
        assert.are.equal(199, requests[1].batch_end_page)

        -- Complete batch 1
        advance(1)
        assert.are.equal(199, plugin.book_data.last_fetch_page)
        assert.is_true(plugin.pending_background_fetch)

        -- Advance past cooldown to complete to page 300
        advance(20)
        assert.are.equal(2, #requests)
        assert.are.equal(199, requests[2].last_fetch_page)
        assert.are.equal(300, requests[2].batch_end_page)

        advance(1)
        assert.are.equal(300, plugin.book_data.last_fetch_page)
        assert.is_false(plugin.pending_background_fetch)
    end)
end)
