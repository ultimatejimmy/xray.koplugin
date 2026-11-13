-- xray_fetch_spec.lua
require("spec.spec_helper")
local fetch = require("xray_fetch")
local data = require("xray_data")

describe("xray_fetch", function()
    local plugin

    before_each(function()
        plugin = createMockPlugin()
        -- Mix in data and fetch methods
        for k, v in pairs(data) do
            plugin[k] = v
        end
        for k, v in pairs(fetch) do
            plugin[k] = v
        end
        plugin.cache_manager = {
            saveCache = function() return true end,
            asyncSaveCache = function() return true end,
            loadCache = function() return {} end
        }
    end)

    describe("request deadlines", function()
        it("uses elapsed wall time so suspend cannot extend a timeout", function()
            local old_time = os.time
            os.time = function() return 1601 end

            local ok, timed_out = pcall(function()
                return plugin:isRequestTimedOut(1000, 600)
            end)

            os.time = old_time
            if not ok then error(timed_out) end
            assert.is_true(timed_out)
        end)

        it("keeps requests active before their wall-clock deadline", function()
            local old_time = os.time
            os.time = function() return 1299 end

            local ok, timed_out = pcall(function()
                return plugin:isRequestTimedOut(1000, 300)
            end)

            os.time = old_time
            if not ok then error(timed_out) end
            assert.is_false(timed_out)
        end)
    end)

    describe("active request cleanup", function()
        it("cancels the registered operation and clears suspend-sensitive state", function()
            local cancelled_reason
            local dialog = { type = "ButtonDialog" }
            plugin._active_ai_dialog = dialog
            plugin._active_ai_cancel = function(reason) cancelled_reason = reason end
            plugin._active_fetch_generation = 4
            plugin.bg_fetch_active = true
            plugin.bg_fetch_pending = true

            plugin:cancelActiveAIRequest("device suspended")

            assert.are.equal("device suspended", cancelled_reason)
            assert.is_nil(plugin._active_ai_dialog)
            assert.is_nil(plugin._active_ai_cancel)
            assert.is_nil(plugin._active_fetch_generation)
            assert.is_false(plugin.bg_fetch_active)
            assert.is_false(plugin.bg_fetch_pending)
        end)

        it("kills an unregistered orphan child", function()
            local cancelled = false
            plugin.ai_helper = {
                _async_child_pid = 77,
                cancelAsyncChild = function() cancelled = true end,
            }

            plugin:cancelActiveAIRequest("device suspended")

            assert.is_true(cancelled)
        end)

        it("still kills the helper child when a registered callback is stale", function()
            local callback_called = false
            local child_cancelled = false
            plugin._active_ai_cancel = function() callback_called = true end
            plugin.ai_helper = {
                _async_child_pid = 88,
                cancelAsyncChild = function(self)
                    child_cancelled = true
                    self._async_child_pid = nil
                end,
            }

            plugin:cancelActiveAIRequest("device suspended")

            assert.is_true(callback_called)
            assert.is_true(child_cancelled)
        end)
    end)

    describe("runPostFetchDuplicateCheck reader state", function()
        it("skips safely when the reader document is unavailable", function()
            local analyzer_called = false
            plugin.ui.document = nil
            plugin.ai_helper.hasApiKey = function() return true end
            plugin.chapter_analyzer = {
                getTextForAnalysis = function()
                    analyzer_called = true
                    return "text"
                end,
            }

            local ok, err = pcall(function()
                plugin:runPostFetchDuplicateCheck("Title", "Author", 50, true)
            end)

            assert.is_true(ok)
            assert.is_nil(err)
            assert.is_false(analyzer_called)
        end)

        it("continues when the reader document is available", function()
            local analyzer_called = false
            plugin.ui.getCurrentPage = function() return 10 end
            plugin.ai_helper.hasApiKey = function() return true end
            plugin.chapter_analyzer = {
                getTextForAnalysis = function(_, ui, limit, _, current_page)
                    analyzer_called = ui == plugin.ui and limit == 15000 and current_page == 10
                    return "text"
                end,
            }

            plugin:runPostFetchDuplicateCheck("Title", "Author", 50, true)

            assert.is_true(analyzer_called)
        end)

        it("skips safely when the plugin is destroyed", function()
            local analyzer_called = false
            plugin.destroyed = true
            plugin.ai_helper.hasApiKey = function() return true end
            plugin.chapter_analyzer = {
                getTextForAnalysis = function()
                    analyzer_called = true
                    return "text"
                end,
            }

            plugin:runPostFetchDuplicateCheck("Title", "Author", 50, true)

            assert.is_false(analyzer_called)
        end)
    end)

    describe("continueWithFetch cancellation", function()
        it("does not let a silent fetch replace another request's cancel handler", function()
            local original_cancel = function() end
            local scheduled = false
            local UIManager = require("ui/uimanager")
            local old_schedule = UIManager.scheduleIn
            UIManager.scheduleIn = function()
                scheduled = true
            end
            plugin._active_ai_cancel = original_cancel
            plugin.bg_fetch_pending = true

            local ok, err = pcall(function()
                plugin:continueWithFetch(50, true, nil, true)
                assert.are.equal(original_cancel, plugin._active_ai_cancel)
                assert.is_false(plugin.bg_fetch_pending)
                assert.is_false(scheduled)
            end)

            UIManager.scheduleIn = old_schedule
            if not ok then error(err) end
        end)

        it("aborts silent background fetch when last_fetch_page >= end_page_analysis", function()
            local UIManager = require("ui/uimanager")
            local old_schedule = UIManager.scheduleIn
            local callbacks = {}
            UIManager.scheduleIn = function(_, delay, cb)
                table.insert(callbacks, cb)
            end

            plugin.chapter_analyzer = {
                getEndPageForCurrentPage = function(_, _, page) return 50 end,
                getTextForAnalysis = function() error("Should not be called") end,
            }
            plugin.ui.getCurrentPage = function() return 50 end
            plugin.book_data = { last_fetch_page = 50 }

            local completed_success, completed_code
            local ok, err = pcall(function()
                plugin:continueWithFetch(50, true, 50, true, 50, function(success, code)
                    completed_success = success
                    completed_code = code
                end)
                assert.is_true(plugin.bg_fetch_active)
                local cb = table.remove(callbacks, 1)
                assert.is_not_nil(cb)
                cb()

                assert.is_false(plugin.bg_fetch_active)
                assert.is_false(completed_success)
                assert.are.equal("ALREADY_COVERED", completed_code)
            end)

            UIManager.scheduleIn = old_schedule
            if not ok then error(err) end
        end)

        it("cancels the owned child and allows a new fetch before the old poll runs", function()
            local UIManager = require("ui/uimanager")
            local old_schedule = UIManager.scheduleIn
            local old_remove = os.remove
            local scheduled = {}
            local removed_files = {}
            local started_pids = { 501, 502 }
            local start_count = 0
            local cancelled_pids = {}

            UIManager.scheduleIn = function(self, delay, callback)
                table.insert(scheduled, callback)
            end
            os.remove = function(path)
                table.insert(removed_files, path)
                return true
            end

            plugin.ui.getCurrentPage = function() return 10 end
            plugin.chapter_analyzer = {
                getEndPageForCurrentPage = function(_, _, current_page) return current_page end,
                getTextForAnalysis = function() return "enough extracted book text" end,
                getDetailedChapterSamples = function() return "chapter samples", { "Chapter 1" } end,
                getAnnotationsForAnalysis = function() return nil end,
            }
            plugin.ai_helper = {
                settings = { spoiler_setting = "spoiler_free" },
                buildComprehensiveRequest = function()
                    return { { url = "https://example.invalid" } }
                end,
                makeRequestAsync = function(self)
                    start_count = start_count + 1
                    self._async_child_pid = started_pids[start_count]
                    return self._async_child_pid
                end,
                cancelAsyncChild = function(self, expected_pid)
                    table.insert(cancelled_pids, expected_pid)
                    if self._async_child_pid ~= expected_pid then return false end
                    self._async_child_pid = nil
                    return true
                end,
                checkAsyncResult = function() return nil end,
            }

            local function runNext()
                local callback = table.remove(scheduled, 1)
                assert.is_not_nil(callback)
                callback()
            end

            local ok, err = pcall(function()
                plugin:continueWithFetch(50)
                local first_dialog = _G.ui_tracker.last_shown
                runNext() -- deferred extraction
                runNext() -- request construction and start

                assert.are.equal(501, plugin.ai_helper._async_child_pid)
                assert.is_true(plugin.bg_fetch_active)

                first_dialog.args.buttons[1][1].callback()
                assert.are.equal(501, cancelled_pids[1])
                assert.is_false(plugin.bg_fetch_active)
                assert.is_true(#removed_files > 0)
                assert.are.equal(first_dialog, _G.ui_tracker.closed[#_G.ui_tracker.closed])

                -- Start again before the cancelled fetch's queued poll runs.
                plugin:continueWithFetch(50)
                local second_dialog = _G.ui_tracker.last_shown
                assert.is_true(plugin.bg_fetch_active)

                runNext() -- stale poll from the cancelled fetch
                assert.is_true(plugin.bg_fetch_active)
                assert.are.equal(1, #cancelled_pids)

                runNext() -- second fetch extraction
                runNext() -- second request start
                assert.are.equal(2, start_count)
                assert.are.equal(502, plugin.ai_helper._async_child_pid)
                assert.is_true(plugin.bg_fetch_active)

                second_dialog.args.buttons[1][1].callback()
                assert.are.equal(502, cancelled_pids[2])
                assert.is_false(plugin.bg_fetch_active)
            end)

            UIManager.scheduleIn = old_schedule
            os.remove = old_remove
            if not ok then error(err) end
        end)

        it("clears fetch state and does not crash when self.ui.document becomes nil before scheduled callback fires", function()
            local UIManager = require("ui/uimanager")
            local old_schedule = UIManager.scheduleIn
            local scheduled = {}

            UIManager.scheduleIn = function(self, delay, callback)
                table.insert(scheduled, callback)
            end

            plugin.ui.getCurrentPage = function() return 10 end
            plugin:continueWithFetch(50)
            assert.is_true(plugin.bg_fetch_active)

            -- Simulate reader closing mid-flight
            plugin.ui.document = nil

            local callback = table.remove(scheduled, 1)
            assert.is_not_nil(callback)

            local ok, err = pcall(callback)
            assert.is_true(ok)
            assert.is_nil(err)
            assert.is_false(plugin.bg_fetch_active)

            UIManager.scheduleIn = old_schedule
        end)

        it("clears fetch state and does not crash when self.ui becomes nil before scheduled callback fires", function()
            local UIManager = require("ui/uimanager")
            local old_schedule = UIManager.scheduleIn
            local scheduled = {}

            UIManager.scheduleIn = function(self, delay, callback)
                table.insert(scheduled, callback)
            end

            plugin.ui.getCurrentPage = function() return 10 end
            plugin:continueWithFetch(50)
            assert.is_true(plugin.bg_fetch_active)

            -- Simulate reader UI closing completely mid-flight
            plugin.ui = nil

            local callback = table.remove(scheduled, 1)
            assert.is_not_nil(callback)

            local ok, err = pcall(callback)
            assert.is_true(ok)
            assert.is_nil(err)
            assert.is_false(plugin.bg_fetch_active)

            UIManager.scheduleIn = old_schedule
        end)
    end)

    describe("finalizeXRayData", function()
        it("merges new characters correctly in update mode", function()
            plugin.characters = {
                { name = "Alice", description = "Old description" }
            }
            local new_data = {
                characters = {
                    { name = "Alice", description = "New description" },
                    { name = "Bob", description = "A new character" }
                },
                locations = {},
                historical_figures = {},
                timeline = {}
            }

            plugin:finalizeXRayData(new_data, "Test Title", "Test Author", "Some text", true, true, 10)

            assert.are.equal(2, #plugin.characters)
            assert.are.equal("New description", plugin.characters[1].description)
            assert.are.equal("Bob", plugin.characters[2].name)
        end)

        it("filters non-narrative timeline entries", function()
            plugin.isNonNarrativeChapter = function(self, title)
                return title == "Table of Contents"
            end

            local new_data = {
                characters = {},
                locations = {},
                historical_figures = {},
                timeline = {
                    { chapter = "Chapter 1", text = "Event 1" },
                    { chapter = "Table of Contents", text = "Event 2" }
                }
            }

            plugin:finalizeXRayData(new_data, "Test Title", "Test Author", "Some text", false, true, 10)

            assert.are.equal(1, #plugin.timeline)
            assert.are.equal("Chapter 1", plugin.timeline[1].chapter)
        end)

        it("aborts and protects existing data when AI returns all-empty results", function()
            -- Set up existing data
            plugin.characters = { { name = "Alice", description = "Existing" } }
            plugin.locations = { { name = "Wonderland", description = "Existing" } }
            plugin.timeline = { { chapter = "Start", page = 1 } }
            plugin.historical_figures = { { name = "Lewis Carroll", biography = "Existing" } }

            local empty_data = {
                characters = {},
                locations = {},
                historical_figures = {},
                timeline = {}
            }

            -- Spy on cache save to ensure it's NOT called
            local save_called = false
            plugin.cache_manager.saveCache = function()
                save_called = true
                return true
            end

            plugin:finalizeXRayData(empty_data, "Test Title", "Test Author", "Some text", true, true, 20)

            -- Existing data should be UNTOUCHED
            assert.are.equal(1, #plugin.characters)
            assert.are.equal("Alice", plugin.characters[1].name)
            assert.are.equal(1, #plugin.locations)
            assert.are.equal(1, #plugin.timeline)
            assert.are.equal(1, #plugin.historical_figures)
            
            -- Cache save should NOT have happened
            assert.is_false(save_called)
        end)

        it("preserves series_prior timeline entries and updates matching chapter event descriptions on update", function()
            plugin.timeline = {
                { chapter = "[Book 1: Prior]", event = "Prior book summary", page = -999, source = "series_prior" },
                { chapter = "Chapter 1", event = "Old chapter 1 summary", page = 10 }
            }

            local new_data = {
                characters = {},
                locations = {},
                historical_figures = {},
                timeline = {
                    { chapter = "Chapter 1", event = "Updated chapter 1 summary", page = 10 },
                    { chapter = "Chapter 2", event = "New chapter 2 summary", page = 25 }
                }
            }

            plugin:finalizeXRayData(new_data, "Test Title", "Test Author", "Some text", true, true, 20)

            -- Should contain 3 events total: 1 prior series event, 2 current book events
            assert.are.equal(3, #plugin.timeline)

            -- Prior series event should be preserved
            local prior_found = false
            for _, ev in ipairs(plugin.timeline) do
                if ev.source == "series_prior" then
                    prior_found = true
                    assert.are.equal("[Book 1: Prior]", ev.chapter)
                end
            end
            assert.is_true(prior_found)

            -- Chapter 1 event description should be updated
            local ch1_event
            for _, ev in ipairs(plugin.timeline) do
                if ev.chapter == "Chapter 1" then
                    ch1_event = ev
                end
            end
            assert.is_not_nil(ch1_event)
            assert.are.equal("Updated chapter 1 summary", ch1_event.event)
        end)

        it("preserves series_prior timeline entries during non-merge updates", function()
            plugin.timeline = {
                { chapter = "[Book 1: Prior]", event = "Prior book summary", page = -999, source = "series_prior" },
                { chapter = "Chapter 1", event = "Old summary", page = 10 }
            }

            local new_data = {
                characters = {},
                locations = {},
                historical_figures = {},
                timeline = {
                    { chapter = "Chapter 1", event = "Fresh fetch summary", page = 10 }
                }
            }

            plugin:finalizeXRayData(new_data, "Test Title", "Test Author", "Some text", false, true, 20)

            assert.are.equal(2, #plugin.timeline)
            local prior_found = false
            for _, ev in ipairs(plugin.timeline) do
                if ev.source == "series_prior" then
                    prior_found = true
                end
            end
            assert.is_true(prior_found)
        end)
    end)

    describe("mergeSeriesContext", function()
        it("handles missing description/name fields in characters/locations/terms without crashing", function()
            plugin.characters = {
                { name = "Alice" } -- description is nil
            }
            plugin.locations = {
                { name = "Adua" } -- description is nil
            }
            plugin.terms = {
                { name = "The Union" } -- definition is nil
            }

            local cache_data = {
                books = {
                    [1] = {
                        title = "The Blade Itself",
                        characters = { { name = "Alice", description = "Prior description" } },
                        locations = { { name = "Adua", description = "Capital city" } },
                        terms = { { name = "The Union", definition = "Kingdom" } },
                        timeline = { { event = "War breaks out" } }
                    }
                }
            }

            local series_info = { index = 2, slug = "first_law" }

            -- Should merge prior series data without nil indexing error
            plugin:mergeSeriesContext(cache_data, series_info)

            assert.is_true(#plugin.characters > 0)
            assert.is_true(#plugin.timeline > 0)
            assert.is_true(plugin.series_context_loaded)
        end)

        it("persists series_index and series name to book cache when merging series context", function()
            local saved_cache = nil
            plugin.ui = {
                document = {
                    file = "/tmp/koreader/book2.epub",
                    getToc = function() return {} end,
                    getProps = function() return { title = "Golden Son" } end
                }
            }
            plugin.cache_manager = {
                loadCache = function(self, path) return { title = "Golden Son" } end,
                asyncSaveCache = function(self, path, data)
                    saved_cache = data
                    return true
                end
            }
            plugin.book_data = nil
            plugin.characters = {}
            plugin.locations = {}
            plugin.terms = {}
            plugin.timeline = {}

            local cache_data = {
                books = {
                    [1] = {
                        title = "Red Rising",
                        characters = { { name = "Darrow", description = "Red miner" } }
                    }
                }
            }
            local series_info = { name = "Red Rising", index = 2, slug = "red_rising" }
            plugin:mergeSeriesContext(cache_data, series_info)

            assert.is_not_nil(saved_cache)
            assert.are.equal("red_rising", saved_cache.series_slug)
            assert.are.equal(2, saved_cache.series_index)
            assert.are.equal("Red Rising", saved_cache.series)
            assert.is_true(saved_cache.series_context_loaded)
        end)
    end)

    describe("fetchSingleWord safety & edge cases", function()
        it("returns safely when reader document is unavailable", function()
            plugin.ui.document = nil
            local ok, err = pcall(function()
                plugin:fetchSingleWord("word", 1, 2)
            end)
            assert.is_true(ok)
            assert.is_nil(err)
        end)

        it("unwraps table text arguments without crashing", function()
            local called_text = nil
            plugin.ai_helper = {
                hasApiKey = function() return false end,
            }
            local ok, err = pcall(function()
                plugin:fetchSingleWord({ text = "ExtractedWord" }, 1, 2)
            end)
            assert.is_true(ok)
            assert.is_nil(err)
        end)

        it("cancels an active background fetch process before starting lookup", function()
            local cancelled = false
            plugin.ui.getCurrentPage = function() return 1 end
            plugin.chapter_analyzer = {
                getDetailedChapterSamples = function() return {}, {} end,
                getEndPageForCurrentPage = function() return 1 end,
                getTextFromPageRange = function() return "book text" end,
            }
            plugin.ai_helper = {
                _async_child_pid = 999,
                hasApiKey = function() return true end,
                cancelAsyncChild = function() cancelled = true end,
                lookupSingleWordAsync = function() return 1001 end,
                checkAsyncResult = function() return false, "error_api", "cancelled" end,
            }
            
            plugin:fetchSingleWord("TestTerm", 1, 2)
            assert.is_true(cancelled)
        end)

        it("shows a Cancel button that terminates the lookup child", function()
            local UIManager = require("ui/uimanager")
            local old_schedule = UIManager.scheduleIn
            local scheduled = {}
            local cancelled_pid

            UIManager.scheduleIn = function(self, delay, callback)
                table.insert(scheduled, callback)
            end
            plugin.ui.getCurrentPage = function() return 1 end
            plugin.chapter_analyzer = {
                getDetailedChapterSamples = function() return {}, {} end,
                getEndPageForCurrentPage = function() return 1 end,
                getTextFromPageRange = function() return "book text" end,
            }
            plugin.ai_helper = {
                hasApiKey = function() return true end,
                lookupSingleWordAsync = function() return 1001 end,
                cancelAsyncChild = function(_, pid) cancelled_pid = pid; return true end,
                checkAsyncResult = function() return nil end,
            }

            local ok, err = pcall(function()
                plugin:fetchSingleWord("TestTerm", 1, 2)
                assert.are.equal("ButtonDialog", plugin._active_ai_dialog.type)
                table.remove(scheduled, 1)()
                table.remove(scheduled, 1)()
                plugin._active_ai_dialog.args.buttons[1][1].callback()
                assert.are.equal(1001, cancelled_pid)
                assert.is_nil(plugin._active_ai_dialog)
                assert.is_nil(plugin._active_ai_cancel)
            end)

            UIManager.scheduleIn = old_schedule
            if not ok then error(err) end
        end)

        it("does not spawn a lookup child when cancelled before deferred analysis", function()
            local UIManager = require("ui/uimanager")
            local old_schedule = UIManager.scheduleIn
            local scheduled = {}
            local spawn_count = 0

            UIManager.scheduleIn = function(self, delay, callback)
                table.insert(scheduled, callback)
            end
            plugin.ui.getCurrentPage = function() return 1 end
            plugin.chapter_analyzer = {
                getDetailedChapterSamples = function() return {}, {} end,
                getEndPageForCurrentPage = function() return 1 end,
                getTextFromPageRange = function() return "book text" end,
            }
            plugin.ai_helper = {
                hasApiKey = function() return true end,
                lookupSingleWordAsync = function()
                    spawn_count = spawn_count + 1
                    return 1001
                end,
                cancelAsyncChild = function() return true end,
            }

            local ok, err = pcall(function()
                plugin:fetchSingleWord("TestTerm", 1, 2)
                plugin._active_ai_dialog.args.buttons[1][1].callback()
                while #scheduled > 0 do
                    table.remove(scheduled, 1)()
                end
                assert.are.equal(0, spawn_count)
            end)

            UIManager.scheduleIn = old_schedule
            if not ok then error(err) end
        end)

        it("handles invalid or non-table result in _processSingleWordResult without crashing", function()
            local ok, err = pcall(function()
                plugin:_processSingleWordResult("invalid_json", "text", "book_text", 1)
                plugin:_processSingleWordResult({ is_valid = true, item = nil }, "text", "book_text", 1)
            end)
            assert.is_true(ok)
            assert.is_nil(err)
        end)

        it("ensures progress dialog has modal = true", function()
            local UIManager = require("ui/uimanager")
            local old_schedule = UIManager.scheduleIn
            UIManager.scheduleIn = function(self, delay, cb) end

            plugin.ui.getCurrentPage = function() return 1 end
            plugin.ai_helper = {
                hasApiKey = function() return true end,
            }
            plugin:fetchSingleWord("TestTerm", 1, 2)
            assert.is_not_nil(plugin._active_ai_dialog)
            assert.are.equal("ButtonDialog", plugin._active_ai_dialog.type)
            assert.is_true(plugin._active_ai_dialog.args.modal)
            plugin:cancelActiveAIRequest("Test cleanup")
            UIManager.scheduleIn = old_schedule
        end)

        it("resolves current page via ui.paging or ui.document when ui.getCurrentPage is nil", function()
            local UIManager = require("ui/uimanager")
            local old_schedule = UIManager.scheduleIn
            UIManager.scheduleIn = function(self, delay, cb) end

            plugin.ui.getCurrentPage = nil
            plugin.ui.paging = {
                getCurrentPage = function() return 42 end,
            }
            plugin.ai_helper = {
                hasApiKey = function() return true end,
            }
            local ok, err = pcall(function()
                plugin:fetchSingleWord("TestTerm", 1, 2)
            end)
            assert.is_true(ok)
            assert.is_nil(err)
            assert.is_not_nil(plugin._active_ai_dialog)
            plugin:cancelActiveAIRequest("Test cleanup")
            UIManager.scheduleIn = old_schedule
        end)

        it("correctly normalizes capitalized and aliased types in _processSingleWordResult", function()
            local shown_type = nil
            local shown_item = nil
            plugin.lookup_manager = {
                showResult = function(self, item, item_type)
                    shown_item = item
                    shown_type = item_type
                end
            }
            plugin.characters = {}
            plugin.locations = {}
            plugin.historical_figures = {}
            plugin.terms = {}

            -- Test capitalized "Character"
            plugin:_processSingleWordResult({
                is_valid = true,
                type = "Character",
                item = { name = "Alanna of Trebond", description = "A knight" }
            }, "Alanna", "book text", 10)

            assert.are.equal("character", shown_type)
            assert.are.equal(1, #plugin.characters)
            assert.are.equal("Alanna of Trebond", plugin.characters[1].name)

            -- Test capitalized "Historical Figure"
            plugin:_processSingleWordResult({
                is_valid = true,
                type = "Historical Figure",
                item = { name = "Napoleon", biography = "Emperor of France", role = "Emperor" }
            }, "Napoleon", "book text", 10)

            assert.are.equal("historical_figure", shown_type)
            assert.are.equal(1, #plugin.historical_figures)
            assert.are.equal("Napoleon", plugin.historical_figures[1].name)

            -- Test "Location"
            plugin:_processSingleWordResult({
                is_valid = true,
                type = "Location",
                item = { name = "Camelot", description = "A castle" }
            }, "Camelot", "book text", 10)

            assert.are.equal("location", shown_type)
            assert.are.equal(1, #plugin.locations)

            -- Test "Term"
            plugin:_processSingleWordResult({
                is_valid = true,
                type = "Term",
                item = { name = "System 1", definition = "Fast thinking" }
            }, "System 1", "book text", 10)

            assert.are.equal("term", shown_type)
            assert.are.equal(1, #plugin.terms)
        end)
    end)

    describe("fetchMoreEntities modal behavior", function()
        it("shows key_dlg with modal = true when API key is missing", function()
            local shown_widget
            local UIManager = require("ui/uimanager")
            local old_show = UIManager.show
            UIManager.show = function(self, widget)
                shown_widget = widget
            end

            plugin.ai_helper = {
                hasApiKey = function() return false end,
                init = function() end,
            }

            plugin:fetchMoreCharacters()

            UIManager.show = old_show
            assert.is_not_nil(shown_widget)
            assert.are.equal("ButtonDialog", shown_widget.type)
            assert.is_true(shown_widget.args.modal)
        end)

        it("shows wait_msg with modal = true and does not prematurely clear char_menu", function()
            local shown_dialogs = {}
            local UIManager = require("ui/uimanager")
            local old_show = UIManager.show
            local old_schedule = UIManager.scheduleIn
            UIManager.show = function(self, widget)
                table.insert(shown_dialogs, widget)
            end
            UIManager.scheduleIn = function(self, delay, fn)
                -- Defer callback execution
            end

            local mock_menu = { id = "existing_menu" }
            plugin.char_menu = mock_menu

            plugin.ai_helper = {
                hasApiKey = function() return true end,
                init = function() end,
                settings = { spoiler_setting = "spoiler_free" },
            }
            plugin.ui.document.file = "/path/to/book.epub"
            plugin.ui.getCurrentPage = function() return 10 end
            plugin.ui.document.getPageCount = function() return 100 end

            plugin:fetchMoreCharacters()

            UIManager.show = old_show
            UIManager.scheduleIn = old_schedule

            assert.are.equal(mock_menu, plugin.char_menu)
            assert.is_not_nil(plugin._active_ai_dialog)
            assert.is_true(plugin._active_ai_dialog.args.modal)
        end)
    end)

    describe("fetchFromAI vs updateFromAI", function()
        it("fetchFromAI triggers clean fetch without is_update", function()
            local called_args = nil
            plugin.continueWithFetch = function(self, reading_percent, is_update, last_fetch_page, is_silent)
                called_args = {
                    reading_percent = reading_percent,
                    is_update = is_update,
                    last_fetch_page = last_fetch_page,
                    is_silent = is_silent,
                }
            end

            plugin.ui.getCurrentPage = function() return 25 end
            plugin.ui.document.getPageCount = function() return 100 end
            plugin.ai_helper = {
                settings = { spoiler_setting = "spoiler_free" }
            }

            plugin:fetchFromAI()

            assert.is_not_nil(called_args)
            assert.are.equal(25, called_args.reading_percent)
            assert.is_nil(called_args.is_update)
            assert.is_nil(called_args.last_fetch_page)
        end)

        it("fetchFromAI in full_book mode uses 100 percent without is_update", function()
            local called_args = nil
            plugin.continueWithFetch = function(self, reading_percent, is_update, last_fetch_page, is_silent)
                called_args = {
                    reading_percent = reading_percent,
                    is_update = is_update,
                    last_fetch_page = last_fetch_page,
                }
            end

            plugin.ui.getCurrentPage = function() return 25 end
            plugin.ui.document.getPageCount = function() return 100 end
            plugin.ai_helper = {
                settings = { spoiler_setting = "full_book" }
            }

            plugin:fetchFromAI()

            assert.is_not_nil(called_args)
            assert.are.equal(100, called_args.reading_percent)
            assert.is_nil(called_args.is_update)
        end)

        it("updateFromAI triggers merge fetch with is_update = true and last_fetch_page", function()
            local called_args = nil
            plugin.continueWithFetch = function(self, reading_percent, is_update, last_fetch_page, is_silent)
                called_args = {
                    reading_percent = reading_percent,
                    is_update = is_update,
                    last_fetch_page = last_fetch_page,
                }
            end

            plugin.ui.getCurrentPage = function() return 50 end
            plugin.ui.document.getPageCount = function() return 100 end
            plugin.book_data = { last_fetch_page = 30 }
            plugin.ai_helper = {
                settings = { spoiler_setting = "spoiler_free" }
            }

            plugin:updateFromAI()

            assert.is_not_nil(called_args)
            assert.are.equal(50, called_args.reading_percent)
            assert.is_true(called_args.is_update)
            assert.are.equal(30, called_args.last_fetch_page)
        end)
    end)

    describe("sequential prefetch and Story Arc delta updates", function()
        it("creates character entry for orphan character_state_updates", function()
            plugin.characters = {}
            local delta_data = {
                character_state_updates = {
                    {
                        name = "Carrie White",
                        role = "Protagonist",
                        status = "alive",
                        change = "Discovers telekinetic abilities",
                        description = "A shy outcast who begins to manifest powerful telekinesis.",
                        evidence = "The mirrors began to flex."
                    }
                }
            }
            local chapter = { title = "Part One (1/4)", page = 1 }
            plugin:mergeSequentialChapterDelta(delta_data, chapter, 1, true)

            assert.are.equal(1, #plugin.characters)
            local c = plugin.characters[1]
            assert.are.equal("Carrie White", c.name)
            assert.are.equal("Protagonist", c.role)
            assert.are.equal(1, #c.states)
            assert.are.equal("Part One (1/4)", c.states[1].chapter_title)
            assert.are.equal("Discovers telekinetic abilities", c.states[1].change)
        end)

        it("honors skip_checkpoint parameter in mergeSequentialChapterDelta", function()
            local checkpoints = 0
            plugin.checkpointHorizonScan = function() checkpoints = checkpoints + 1 end
            local delta_data = { new_characters = {} }
            local chapter = { title = "Chapter 1", page = 1 }

            plugin:mergeSequentialChapterDelta(delta_data, chapter, 1, true)
            assert.are.equal(0, checkpoints)

            plugin:mergeSequentialChapterDelta(delta_data, chapter, 1, false)
            assert.are.equal(1, checkpoints)
        end)

        it("handles string timeline_event in mergeSequentialChapterDelta (batch scan format)", function()
            plugin.timeline = {}
            local delta_data = {
                timeline_event = "Alice tumbles down the rabbit hole and discovers a locked door."
            }
            local chapter = { title = "Down the Rabbit-Hole", page = 5 }
            plugin:mergeSequentialChapterDelta(delta_data, chapter, 1, true)

            assert.are.equal(1, #plugin.timeline)
            local ev = plugin.timeline[1]
            assert.are.equal("Down the Rabbit-Hole", ev.chapter)
            assert.are.equal("Alice tumbles down the rabbit hole and discovers a locked door.", ev.event)
            assert.are.equal(1, ev.chapter_index)
            assert.are.equal(5, ev.page)
        end)

        it("handles table timeline_event with event or fallback keys in mergeSequentialChapterDelta", function()
            plugin.timeline = {}
            -- Table with explicit chapter and event
            local delta1 = {
                timeline_event = {
                    chapter = "Chapter 2: The Pool of Tears",
                    event = "Alice cries a pool of giant tears."
                }
            }
            plugin:mergeSequentialChapterDelta(delta1, { title = "Chapter 2", page = 12 }, 2, true)

            -- Table with fallback summary key
            local delta2 = {
                timeline_event = {
                    summary = "Alice runs the Caucus-Race with birds and beasts."
                }
            }
            plugin:mergeSequentialChapterDelta(delta2, { title = "Chapter 3", page = 20 }, 3, true)

            assert.are.equal(2, #plugin.timeline)
            assert.are.equal("Chapter 2: The Pool of Tears", plugin.timeline[1].chapter)
            assert.are.equal("Alice cries a pool of giant tears.", plugin.timeline[1].event)
            assert.are.equal(12, plugin.timeline[1].page)

            assert.are.equal("Chapter 3", plugin.timeline[2].chapter)
            assert.are.equal("Alice runs the Caucus-Race with birds and beasts.", plugin.timeline[2].event)
            assert.are.equal(20, plugin.timeline[2].page)
        end)

        it("updates existing timeline event on re-scan without creating duplicate entries", function()
            plugin.timeline = {}
            local delta1 = { timeline_event = "Initial plot event." }
            plugin:mergeSequentialChapterDelta(delta1, { title = "Chapter 1", page = 1 }, 1, true)
            assert.are.equal(1, #plugin.timeline)

            local delta2 = { timeline_event = "Updated plot event with more detail." }
            plugin:mergeSequentialChapterDelta(delta2, { title = "Chapter 1", page = 1 }, 1, true)
            assert.are.equal(1, #plugin.timeline)
            assert.are.equal("Updated plot event with more detail.", plugin.timeline[1].event)
        end)

        it("persists chapters_fetched and sorts timeline in checkpointHorizonScan", function()
            plugin.book_data = {}
            plugin.chapters_fetched = { ["Chapter 1_5"] = true }
            plugin.timeline = {
                { chapter = "Chapter 2", page = 20, event = "Second" },
                { chapter = "Chapter 1", page = 5, event = "First" }
            }
            plugin:checkpointHorizonScan()

            assert.is_not_nil(plugin.book_data.chapters_fetched)
            assert.is_true(plugin.book_data.chapters_fetched["Chapter 1_5"])
            assert.are.equal(5, plugin.timeline[1].page)
            assert.are.equal(20, plugin.timeline[2].page)
        end)

        it("skips chapters already present in chapters_fetched or timeline in queueSequentialChapterScan", function()
            plugin.timeline = {
                { chapter = "Chapter 1", page = 5, chapter_index = 1, event = "Already done" }
            }
            plugin.chapters_fetched = {}
            local raw_toc = {
                { title = "Chapter 1", page = 5 },
                { title = "Chapter 2", page = 15 }
            }
            plugin.ui.document.getToc = function() return raw_toc end

            local scanned = false
            plugin.ai_helper = {
                hasApiKey = function() return true end,
                settings = {},
                buildBatchChapterDeltaPrompt = function()
                    scanned = true
                    return "mock_prompt"
                end,
                buildComprehensiveRequest = function()
                    return { url = "mock" }
                end
            }

            local done_called = false
            plugin:queueSequentialChapterScan({ { title = "Chapter 1", page = 5, toc_index = 1 } }, true, nil, function(success)
                done_called = true
            end)

            assert.is_true(done_called)
            assert.is_false(scanned)
            assert.is_true(plugin.chapters_fetched["Chapter 1_5"])
        end)

        it("skips post-fetch duplicate check in queueSequentialChapterScan if zero batches were processed", function()
            plugin.timeline = {
                { chapter = "Chapter 1", page = 5, chapter_index = 1, event = "Done" }
            }
            plugin.chapters_fetched = { ["Chapter 1_5"] = true }
            local dupe_check_called = false
            plugin.runPostFetchDuplicateCheck = function()
                dupe_check_called = true
            end

            local done_called = false
            local ret_batches = nil
            plugin:queueSequentialChapterScan({ { title = "Chapter 1", page = 5, toc_index = 1 } }, true, nil, function(success, err, batches)
                done_called = true
                ret_batches = batches
            end)

            assert.is_true(done_called)
            assert.are.equal(0, ret_batches)
            assert.is_false(dupe_check_called)
        end)

        it("force_rescan re-analyzes chapters even if present in chapters_fetched or timeline", function()
            plugin.timeline = {
                { chapter = "Chapter 1", page = 5, chapter_index = 1, event = "Old event" }
            }
            plugin.chapters_fetched = { ["Chapter 1_5"] = true }
            local raw_toc = {
                { title = "Chapter 1", page = 5 },
                { title = "Chapter 2", page = 15 }
            }
            plugin.ui.document.getToc = function() return raw_toc end

            local ChapterAnalyzer = require("xray_chapteranalyzer")
            local orig_getText = ChapterAnalyzer.getSingleChapterText
            ChapterAnalyzer.getSingleChapterText = function()
                return string.rep("Sample chapter content for analysis test. ", 10)
            end

            local scanned = false
            plugin.ai_helper = {
                hasApiKey = function() return true end,
                settings = {},
                buildChapterDeltaPrompt = function()
                    scanned = true
                    return "mock_prompt"
                end,
                buildBatchChapterDeltaPrompt = function()
                    scanned = true
                    return "mock_prompt"
                end,
                buildComprehensiveRequest = function()
                    return { url = "mock" }
                end,
                makeRequestAsync = function()
                    -- Return nil with custom mock error to stop loop without hang
                    return nil, "error_test", "Test stop"
                end,
            }

            local done_called = false
            local reported_err = nil
            local ok, err_run = pcall(function()
                plugin:queueSequentialChapterScan({ { title = "Chapter 1", page = 5, toc_index = 1 } }, true, nil, function(success, err)
                    done_called = true
                    reported_err = err
                end, true) -- force_rescan = true
            end)

            ChapterAnalyzer.getSingleChapterText = orig_getText

            if not ok then error(err_run) end
            assert.is_true(done_called)
            assert.is_true(scanned) -- Chapter was NOT skipped!
            assert.are.equal("Test stop", reported_err)
        end)

        it("pre-empts background book-type detection when manual pregeneration starts", function()
            plugin._book_type_detecting = true
            local cancel_called = false
            plugin.ai_helper = {
                hasApiKey = function() return true end,
                settings = {},
                cancelAsyncChild = function()
                    cancel_called = true
                    return true
                end,
                buildChapterDeltaPrompt = function() return "prompt" end,
                buildBatchChapterDeltaPrompt = function() return "prompt" end,
                buildComprehensiveRequest = function() return { url = "mock" } end,
                makeRequestAsync = function() return nil, "error_test", "Stop" end,
            }

            plugin:queueSequentialChapterScan({ { title = "Chapter 1", page = 5, toc_index = 1 } }, true)

            assert.is_true(cancel_called)
            assert.is_nil(plugin._book_type_detecting)
        end)

        it("retries when makeRequestAsync returns error_busy instead of immediately failing", function()
            local UIManager = require("ui/uimanager")
            local ChapterAnalyzer = require("xray_chapteranalyzer")
            local orig_getText = ChapterAnalyzer.getSingleChapterText
            ChapterAnalyzer.getSingleChapterText = function()
                return string.rep("Sample chapter content for analysis test. ", 10)
            end

            local attempts = 0
            local scheduled_delay = nil
            local scheduled_cb = nil
            local orig_schedule = UIManager.scheduleIn
            UIManager.scheduleIn = function(self_ui, delay, cb)
                scheduled_delay = delay
                scheduled_cb = cb
            end

            plugin.timeline = nil
            plugin.chapters_fetched = {}
            plugin.ui.document.getToc = function() return { { title = "Chapter 1", page = 5 } } end

            plugin.ai_helper = {
                hasApiKey = function() return true end,
                settings = {},
                buildChapterDeltaPrompt = function() return "prompt" end,
                buildBatchChapterDeltaPrompt = function() return "prompt" end,
                buildComprehensiveRequest = function() return { url = "mock" } end,
                makeRequestAsync = function()
                    attempts = attempts + 1
                    if attempts == 1 then
                        return nil, "error_busy", "Another AI request is already in progress"
                    else
                        return 12345 -- successfully dispatched on attempt 2
                    end
                end,
                checkAsyncResult = function()
                    return nil -- still running
                end,
            }

            local ok, err_run = pcall(function()
                plugin:queueSequentialChapterScan({ { title = "Chapter 1", page = 5, toc_index = 1 } }, true)

                assert.are.equal(1, attempts)
                assert.are.equal(2, scheduled_delay)
                assert.is_not_nil(scheduled_cb)

                -- Invoke scheduled retry
                scheduled_cb()
                assert.are.equal(2, attempts)
                assert.is_true(plugin.is_sequential_scan_active)
            end)

            -- Restore schedule & analyzer
            UIManager.scheduleIn = orig_schedule
            ChapterAnalyzer.getSingleChapterText = orig_getText
            plugin:cancelSequentialChapterScan()

            if not ok then error(err_run) end
        end)

        it("subdivides oversized Part-only TOC chapters into virtual segments", function()
            local ChapterAnalyzer = require("xray_chapteranalyzer")
            local raw_toc = {
                { title = "Part One: Blood Sport", page = 1 },
                { title = "Part Two: Prom Night", page = 91 },
                { title = "Part Three: Wreckage", page = 171 },
            }
            local expanded = ChapterAnalyzer:expandOversizedTocChapters(raw_toc, 200, 25)
            assert.is_not_nil(expanded)
            -- Part 1: 90 pages -> ceil(90/25) = 4 parts
            -- Part 2: 80 pages -> ceil(80/25) = 4 parts
            -- Part 3: 30 pages -> ceil(30/25) = 2 parts
            -- Total parts = 10
            assert.are.equal(10, #expanded)
            assert.are.equal("Part One: Blood Sport (1/4)", expanded[1].title)
            assert.are.equal(1, expanded[1].page)
            assert.is_true(expanded[1].is_virtual_segment)
            assert.are.equal("Part One: Blood Sport", expanded[1].parent_title)
            assert.are.equal("Part One: Blood Sport (2/4)", expanded[2].title)
            assert.is_true(expanded[2].page > 1)
            assert.is_true(expanded[2].end_page >= expanded[2].page)
        end)

        it("does not split normal-sized TOC chapters", function()
            local ChapterAnalyzer = require("xray_chapteranalyzer")
            local raw_toc = {
                { title = "Chapter 1", page = 1 },
                { title = "Chapter 2", page = 15 },
                { title = "Chapter 3", page = 30 },
            }
            local expanded = ChapterAnalyzer:expandOversizedTocChapters(raw_toc, 45, 25)
            assert.are.equal(3, #expanded)
            assert.are.equal("Chapter 1", expanded[1].title)
            assert.is_nil(expanded[1].is_virtual_segment)
        end)

        it("does not split chapters between 25 and 60 pages with default threshold", function()
            local ChapterAnalyzer = require("xray_chapteranalyzer")
            local raw_toc = {
                { title = "Chapter 23", page = 585 },
                { title = "Chapter 24", page = 610 }, -- 25 pages
                { title = "Chapter 25", page = 636 }, -- 26 pages
                { title = "Chapter 26", page = 668 }, -- 50 pages
            }
            local expanded = ChapterAnalyzer:expandOversizedTocChapters(raw_toc, 718)
            assert.are.equal(4, #expanded)
            assert.is_nil(expanded[1].is_virtual_segment)
            assert.is_nil(expanded[2].is_virtual_segment)
            assert.is_nil(expanded[3].is_virtual_segment)
            assert.is_nil(expanded[4].is_virtual_segment)
            assert.are.equal(1, expanded[1].parent_toc_index)
            assert.are.equal(2, expanded[2].parent_toc_index)
            assert.are.equal(3, expanded[3].parent_toc_index)
            assert.are.equal(4, expanded[4].parent_toc_index)
        end)

        it("preserves parent_toc_index and part_index on virtual segments", function()
            local ChapterAnalyzer = require("xray_chapteranalyzer")
            local raw_toc = {
                { title = "Part One", page = 1 },
                { title = "Part Two", page = 121 },
            }
            local expanded = ChapterAnalyzer:expandOversizedTocChapters(raw_toc, 200, 50)
            assert.is_true(#expanded > 2)
            assert.are.equal(1, expanded[1].parent_toc_index)
            assert.are.equal(1, expanded[1].part_index)
            assert.are.equal("Part One", expanded[1].parent_title)
            assert.is_true(expanded[1].is_virtual_segment)
            assert.are.equal(1, expanded[2].parent_toc_index)
            assert.are.equal(2, expanded[2].part_index)
        end)
    end)

    describe("issue #156 optimizations", function()
        it("updateEntityDescPreservingPrior preserves [From Book X] prefixes and returns new description", function()
            local existing = {
                name = "Shallan",
                description = "Shallan is a scholar.\n\n[From Book 1] Apprentice to Jasnah.\n\n[From Book 2] Discovers the Knights Radiant."
            }
            local clean = plugin:updateEntityDescPreservingPrior(existing, "Now a full Knight Radiant.", "description")
            assert.are.equal("Now a full Knight Radiant.", clean)
            assert.is_not_nil(existing.description:find("Now a full Knight Radiant.", 1, true))
            assert.is_not_nil(existing.description:find("%[From Book 1%] Apprentice to Jasnah."))
            assert.is_not_nil(existing.description:find("%[From Book 2%] Discovers the Knights Radiant."))
        end)

        it("markSeriesSyncDirty and flushSeriesSync defer series writing until flushed", function()
            local sync_called = false
            local synced_slug, synced_index
            local synced_book_data, synced_doc_file, synced_has_explicit
            plugin.series_manager = {
                syncBookToSeriesCache = function(_, slug, index, book_data, doc_file, has_explicit)
                    sync_called = true
                    synced_slug = slug
                    synced_index = index
                    synced_book_data = book_data
                    synced_doc_file = doc_file
                    synced_has_explicit = has_explicit
                    return true
                end
            }
            plugin.book_data = { title = "Oathbringer", characters = {} }

            plugin:markSeriesSyncDirty("the_stormlight_archive", 3, "Oathbringer", "Brandon Sanderson", "/books/Oathbringer.epub", true)
            assert.is_false(sync_called)
            assert.is_not_nil(plugin._pending_series_sync)

            plugin:flushSeriesSync()
            assert.is_true(sync_called)
            assert.are.equal("the_stormlight_archive", synced_slug)
            assert.are.equal(3, synced_index)
            assert.are.equal("/books/Oathbringer.epub", synced_doc_file)
            assert.is_true(synced_has_explicit)
            assert.is_table(synced_book_data)
            assert.are.equal("Oathbringer", synced_book_data.title)
            assert.are.equal("Brandon Sanderson", synced_book_data.author)
            assert.is_nil(plugin._pending_series_sync)
        end)

        it("flushSeriesSync with real SeriesManager correctly tracks multiple books by same author without deleting or corrupting slots", function()
            local SeriesManager = require("xray_seriesmanager")
            local real_mgr = SeriesManager:new()
            
            local store = {}
            real_mgr.loadSeriesCache = function(_, slug)
                return store[slug]
            end
            real_mgr.saveSeriesCache = function(_, slug, cache_data)
                store[slug] = cache_data
                return true
            end

            plugin.series_manager = real_mgr

            -- Step 1: Book 1 of Red Rising
            plugin.book_data = {
                title = "Red Rising",
                author = "Pierce Brown",
                characters = { { name = "Darrow", description = "Helldiver" } }
            }
            plugin:markSeriesSyncDirty("red_rising", 1, "Red Rising", "Pierce Brown", "/books/red_rising.epub", true)
            plugin:flushSeriesSync()

            local series_cache = store["red_rising"]
            assert.is_not_nil(series_cache)
            assert.is_not_nil(series_cache.books[1])
            assert.are.equal("Red Rising", series_cache.books[1].title)
            assert.are.equal("Pierce Brown", series_cache.books[1].author)
            assert.are.equal("/books/red_rising.epub", series_cache.book_paths[1])
            assert.are.equal(1, #series_cache.books[1].characters)
            assert.are.equal("Darrow", series_cache.books[1].characters[1].name)

            -- Step 2: Book 2 of Red Rising (same author!)
            plugin.book_data = {
                title = "Golden Son",
                author = "Pierce Brown",
                characters = { { name = "Mustang", description = "Gold Sovereign" } }
            }
            plugin:markSeriesSyncDirty("red_rising", 2, "Golden Son", "Pierce Brown", "/books/golden_son.epub", true)
            plugin:flushSeriesSync()

            series_cache = store["red_rising"]
            assert.is_not_nil(series_cache.books[1], "Book 1 must not be deleted when Book 2 by the same author is synced!")
            assert.are.equal("Red Rising", series_cache.books[1].title)
            assert.are.equal("Pierce Brown", series_cache.books[1].author)
            assert.are.equal("/books/red_rising.epub", series_cache.book_paths[1])

            assert.is_not_nil(series_cache.books[2])
            assert.are.equal("Golden Son", series_cache.books[2].title)
            assert.are.equal("Pierce Brown", series_cache.books[2].author)
            assert.are.equal("/books/golden_son.epub", series_cache.book_paths[2])
            assert.are.equal(1, #series_cache.books[2].characters)
            assert.are.equal("Mustang", series_cache.books[2].characters[1].name)

            -- Step 3: Guard for non-explicit (guessed) index (#134 case)
            plugin.book_data = {
                title = "Iron Gold",
                author = "Pierce Brown",
                characters = { { name = "Lysander" } }
            }
            plugin:markSeriesSyncDirty("red_rising", 1, "Iron Gold", "Pierce Brown", "/books/iron_gold.epub", false)
            plugin:flushSeriesSync()

            assert.are.equal("Red Rising", store["red_rising"].books[1].title)
            assert.are.equal("/books/red_rising.epub", store["red_rising"].book_paths[1])
        end)

        it("finalizeXRayData propagates merged series context and series_context_loaded to saved cache on initial fetch", function()
            local SeriesManager = require("xray_seriesmanager")
            local series_mgr = SeriesManager:new()
            plugin.series_manager = series_mgr
            series_mgr.getSeriesInfo = function()
                return { slug = "stormlight", index = 2, has_explicit_index = true, name = "The Stormlight Archive" }
            end
            series_mgr.loadSeriesCache = function()
                return {
                    slug = "stormlight",
                    books = {
                        [1] = {
                            title = "The Way of Kings",
                            characters = {
                                { name = "Dalinar", description = "Highprince of War." }
                            }
                        }
                    }
                }
            end

            local saved_payload = nil
            plugin.cache_manager = {
                asyncSaveCache = function(_, doc_file, data_to_save)
                    saved_payload = data_to_save
                    return true
                end,
                loadCache = function() return {} end
            }
            plugin.ui = {
                document = {
                    file = "/books/words_of_radiance.epub",
                    getProps = function() return { title = "Words of Radiance", authors = "Brandon Sanderson" } end,
                    getToc = function() return {} end,
                    getPageCount = function() return 100 end,
                }
            }

            local initial_data = {
                characters = {
                    { name = "Kaladin", description = "Windrunner." }
                }
            }

            plugin:finalizeXRayData(initial_data, "Words of Radiance", "Brandon Sanderson", "Kaladin Windrunner", false, true, 1)

            assert.is_not_nil(saved_payload)
            assert.is_true(saved_payload.series_context_loaded)
            assert.is_true(plugin.series_context_loaded)
            -- Both Kaladin and merged Dalinar should be present in saved_payload.characters
            local found_dalinar = false
            for _, c in ipairs(saved_payload.characters or {}) do
                if c.name == "Dalinar" then found_dalinar = true end
            end
            assert.is_true(found_dalinar)
        end)

        it("autoLoadCache detects and heals damaged series cache entries", function()
            local Main = require("main")
            local dirty_marked = false
            local dirty_slug, dirty_idx, dirty_title, dirty_author, dirty_path
            local mock_p = createMockPlugin()
            for k, v in pairs(data) do mock_p[k] = v end
            for k, v in pairs(fetch) do mock_p[k] = v end
            mock_p.autoLoadCache = Main.autoLoadCache
            mock_p.isAnthologyMode = function() return false end
            mock_p.ui = {
                document = {
                    file = "/books/iron_gold.epub",
                    getProps = function() return { title = "Iron Gold", authors = "Pierce Brown" } end,
                    getToc = function() return {} end,
                    getPageCount = function() return 100 end,
                }
            }
            mock_p.markSeriesSyncDirty = function(_, slug, index, title, author, book_path, is_explicit)
                dirty_marked = true
                dirty_slug = slug
                dirty_idx = index
                dirty_title = title
                dirty_author = author
                dirty_path = book_path
            end
            mock_p.cache_manager = {
                loadCache = function()
                    return {
                        title = "Iron Gold",
                        author = "Pierce Brown",
                        series = "Red Rising",
                        series_slug = "red_rising",
                        series_index = 4,
                        cached_at = 1000,
                        characters = { { name = "Darrow", description = "Reaper" } },
                    }
                end
            }
            mock_p.series_manager = {
                getSeriesInfo = function()
                    return { slug = "red_rising", index = 4, has_explicit_index = true, name = "Red Rising" }
                end,
                getSeriesCachePath = function()
                    return "/tmp/series_red_rising.lua"
                end,
                loadSeriesCache = function()
                    -- Damaged series cache from 26.11.5: title is nil, path is author name
                    return {
                        series_slug = "red_rising",
                        books = {
                            [4] = { title = nil, characters = {} }
                        },
                        book_paths = {
                            [4] = "Pierce Brown"
                        }
                    }
                end,
                hasBookEntities = function(entry)
                    return entry and entry.characters and #entry.characters > 0
                end
            }

            mock_p:autoLoadCache()

            assert.is_true(dirty_marked)
            assert.are.equal("red_rising", dirty_slug)
            assert.are.equal(4, dirty_idx)
            assert.are.equal("Iron Gold", dirty_title)
            assert.are.equal("Pierce Brown", dirty_author)
            assert.are.equal("/books/iron_gold.epub", dirty_path)
        end)

        it("mergeSeriesContext respects skip_save and does not save cache or call getTextForAnalysis", function()
            local saved_called = false
            plugin.cache_manager = {
                asyncSaveCache = function() saved_called = true end,
                loadCache = function() return {} end
            }
            local text_analysis_called = false
            plugin.chapter_analyzer = {
                getTextForAnalysis = function() text_analysis_called = true; return "" end
            }
            plugin.characters = { { name = "Kaladin" } }
            local cache_data = {
                books = {
                    [1] = { title = "Way of Kings", characters = { { name = "Szeth", description = "Assassin" } } }
                }
            }
            local series_info = { slug = "stormlight", index = 2 }

            plugin:mergeSeriesContext(cache_data, series_info, "Kaladin flew with Syl", true)

            assert.is_false(saved_called)
            assert.is_false(text_analysis_called)
            assert.is_true(plugin.series_context_loaded)
            assert.are.equal(2, #plugin.characters)
        end)

        it("finalizeXRayData does not reload series cache or merge series context when updating and already loaded", function()
            local load_series_called = false
            plugin.series_manager = {
                getSeriesInfo = function() return { slug = "stormlight", index = 2 } end,
                loadSeriesCache = function() load_series_called = true; return {} end
            }
            local merge_called = false
            plugin.mergeSeriesContext = function() merge_called = true end

            local save_count = 0
            plugin.cache_manager = {
                asyncSaveCache = function() save_count = save_count + 1 end,
                loadCache = function() return {} end
            }

            plugin.series_context_loaded = true
            plugin.characters = {
                {
                    name = "Kaladin",
                    description = "Highprince bodyguard.\n\n[From Book 1] Bridge Four leader."
                }
            }
            local new_data = {
                characters = {
                    {
                        name = "Kaladin",
                        description = "Knight Radiant Windrunner."
                    }
                }
            }

            plugin:finalizeXRayData(new_data, "Words of Radiance", "Brandon Sanderson", "Kaladin Windrunner", true, true, 50)

            assert.is_false(load_series_called)
            assert.is_false(merge_called)
            assert.are.equal(1, save_count)
            assert.is_not_nil(plugin.characters[1].description:find("Knight Radiant Windrunner."))
            assert.is_not_nil(plugin.characters[1].description:find("%[From Book 1%] Bridge Four leader."))
        end)
    end)

    describe("checkWeeklyUpdate", function()
        local orig_time, orig_schedule
        local now, scheduled

        before_each(function()
            now = 1000000
            scheduled = {}
            orig_time = os.time
            orig_schedule = require("ui/uimanager").scheduleIn
            os.time = function() return now end
            require("ui/uimanager").scheduleIn = function(_, delay, cb)
                table.insert(scheduled, { time = now + delay, cb = cb })
            end
        end)

        after_each(function()
            os.time = orig_time
            require("ui/uimanager").scheduleIn = orig_schedule
        end)

        it("never invokes isOnline and stamps 7-day interval on success", function()
            local online_called = false
            package.loaded["ui/network/manager"] = {
                isConnected = function() return true end,
                hasDefaultRoute = function() return true end,
                isOnline = function()
                    online_called = true
                    error("isOnline should not be called!")
                end,
            }

            local saved_settings = nil
            plugin.ai_helper = {
                settings = { last_update_check = 0, beta_channel_enabled = false },
                saveSettings = function(_, s) saved_settings = s end,
            }

            local updater = require("xray_updater")
            local orig_check = updater.checkSilentForUpdates
            updater.checkSilentForUpdates = function(loc, use_beta, opts)
                if opts and opts.on_done then
                    opts.on_done("shown", { version = "2.0.0" })
                end
            end

            plugin:checkWeeklyUpdate()
            assert.is_false(online_called)
            assert.is_not_nil(saved_settings)
            assert.are.equal(now, saved_settings.last_update_check)

            updater.checkSilentForUpdates = orig_check
        end)

        it("backs off 24 hours when silent update check reports an error", function()
            package.loaded["ui/network/manager"] = {
                isConnected = function() return true end,
                hasDefaultRoute = function() return true end,
                isOnline = function() return true end,
            }

            local saved_settings = nil
            plugin.ai_helper = {
                settings = { last_update_check = 0, beta_channel_enabled = false },
                saveSettings = function(_, s) saved_settings = s end,
            }

            local updater = require("xray_updater")
            local orig_check = updater.checkSilentForUpdates
            updater.checkSilentForUpdates = function(loc, use_beta, opts)
                if opts and opts.on_done then
                    opts.on_done("error", { error = "dns timeout" })
                end
            end

            plugin:checkWeeklyUpdate()
            assert.is_not_nil(saved_settings)
            -- now - 7 days + 1 day = now - 6 days
            local expected = now - (7 * 24 * 3600) + (24 * 3600)
            assert.are.equal(expected, saved_settings.last_update_check)

            updater.checkSilentForUpdates = orig_check
        end)

        it("defers by 15 seconds when background AI or unit scan is active", function()
            package.loaded["ui/network/manager"] = {
                isConnected = function() return true end,
                hasDefaultRoute = function() return true end,
                isOnline = function() return true end,
            }

            plugin.ai_helper = {
                settings = { last_update_check = 0, beta_channel_enabled = false },
                _async_child_pid = 1234,
                saveSettings = function() end,
            }

            plugin:checkWeeklyUpdate()
            assert.are.equal(1, #scheduled)
            assert.are.equal(now + 15, scheduled[1].time)
        end)
    end)

    describe("populateBatchTemporalGates (Ultra & Manual modes)", function()
        it("populates text-anchored visible_from and states for Ultra/Manual fetches and appends evolved states on update", function()
            plugin.ui.document.getToc = function()
                return {
                    { title = "Stave 1", page = 2 },
                    { title = "Stave 3", page = 58 },
                }
            end
            plugin.ui.document.findAllText = function(self_doc, pat)
                local hits = {}
                if pat:find("Scrooge") then
                    table.insert(hits, { matched_text = "Scrooge", start = "xp_p2" })
                end
                if pat:find("Ghost") then
                    table.insert(hits, { matched_text = "Ghost of Christmas Present", start = "xp_p84" })
                end
                return hits
            end
            plugin.ui.document.getPageFromXPointer = function(self_doc, xp)
                if xp == "xp_p2" then return 2 end
                if xp == "xp_p84" then return 84 end
                return 1
            end
            plugin.getCurrentChapterIndex = function(self_p, p)
                return (p and p >= 58) and 2 or 1
            end

            -- Batch 1: Ultra fetch at page 7 (window 1..7)
            local batch1 = {
                characters = {
                    { name = "Ebenezer Scrooge", aliases = { "Scrooge" }, description = "Stave 1 miser" }
                },
                locations = {},
                historical_figures = {},
                terms = {
                    { name = "Stave", definition = "Chapter" }
                },
                timeline = {},
            }
            plugin:finalizeXRayData(batch1, "A Christmas Carol", "Dickens", "Scrooge", false, true, 7, 1)

            local scrooge = plugin.characters[1]
            assert.is_not_nil(scrooge.visible_from)
            assert.are.equal(2, scrooge.visible_from.page_hint)
            assert.are.equal(1, #scrooge.states)
            assert.are.equal(2, scrooge.states[1].page_hint)
            assert.are.equal("Stave 1 miser", scrooge.states[1].description)

            -- Batch 2: Ultra update at page 106 (window 58..106)
            local batch2 = {
                characters = {
                    { name = "Ebenezer Scrooge", aliases = { "Scrooge" }, description = "Stave 3 penitent" },
                    { name = "Ghost of Christmas Present", aliases = { "Spirit" }, description = "Jolly giant" },
                },
                locations = {},
                historical_figures = {},
                terms = {},
                timeline = {},
            }
            plugin:finalizeXRayData(batch2, "A Christmas Carol", "Dickens", "Scrooge Ghost", true, true, 106, 58)

            local updated_scrooge = plugin.characters[1]
            assert.are.equal(2, updated_scrooge.visible_from.page_hint)
            assert.are.equal(2, #updated_scrooge.states)
            assert.are.equal(2, updated_scrooge.states[1].page_hint)
            assert.are.equal(106, updated_scrooge.states[2].page_hint)
            assert.are.equal("Stave 3 penitent", updated_scrooge.states[2].description)

            local present = plugin.characters[2]
            assert.is_not_nil(present.visible_from)
            assert.are.equal(84, present.visible_from.page_hint)
            assert.are.equal(2, present.visible_from.chapter_index)
        end)
    end)
end)


