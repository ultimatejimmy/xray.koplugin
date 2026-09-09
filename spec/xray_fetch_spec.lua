-- xray_fetch_spec.lua
require("spec.spec_helper")
local fetch = require("xray_fetch")

describe("xray_fetch", function()
    local plugin

    before_each(function()
        plugin = createMockPlugin()
        -- Mix in fetch methods
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
end)

