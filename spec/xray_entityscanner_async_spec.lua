-- spec/xray_entityscanner_async_spec.lua
require("spec/spec_helper")

describe("xray_entityscanner async background scanning & overlay", function()
    local orig_ffiutil
    local fake_ffiutil
    local written_chunks
    local pipe_written
    local fail_fork
    local is_done_flag
    local child_ran
    local terminated_pid
    local read_calls
    local plugin
    local original_scheduleIn
    local scheduled_tasks
    local mock_time

    local function advance_time(seconds)
        mock_time = mock_time + seconds
        local i = 1
        while i <= #scheduled_tasks do
            local task = scheduled_tasks[i]
            if task.target <= mock_time then
                table.remove(scheduled_tasks, i)
                task.fn()
                i = 1
            else
                i = i + 1
            end
        end
    end

    before_each(function()
        orig_ffiutil = package.loaded["ffi/util"]
        _G.XRAY_DISABLE_ENTITY_SUBPROCESS = false
        written_chunks = {}
        pipe_written = ""
        fail_fork = false
        is_done_flag = true
        child_ran = false
        terminated_pid = nil
        read_calls = 0
        scheduled_tasks = {}
        mock_time = 1000

        local UIManager = require("ui/uimanager")
        original_scheduleIn = UIManager.scheduleIn
        UIManager.scheduleIn = function(_, delay, callback)
            local fn = type(delay) == "function" and delay or callback
            local wait = type(delay) == "number" and delay or 0
            table.insert(scheduled_tasks, { target = mock_time + wait, fn = fn })
        end

        fake_ffiutil = {
            runInSubProcess = function(child_fn, with_pipe)
                if fail_fork then
                    return false, "fork failed: out of memory"
                end
                child_ran = true
                child_fn(8888, "fake_write_fd")
                return 8888, "fake_read_fd"
            end,
            writeToFD = function(fd, data, close_after)
                table.insert(written_chunks, data)
                pipe_written = pipe_written .. data
            end,
            isSubProcessDone = function(pid)
                return is_done_flag
            end,
            terminateSubProcess = function(pid)
                terminated_pid = pid
            end,
            readFromFD = function(fd, size)
                return ""
            end,
            readAllFromFD = function(fd)
                read_calls = read_calls + 1
                return pipe_written
            end,
            getNonBlockingReadSize = function(fd)
                return #pipe_written
            end,
        }
        package.loaded["ffi/util"] = fake_ffiutil

        pcall(os.execute, "mkdir -p /tmp/test_entity_book.epub.sdr")
        pcall(os.remove, "/tmp/test_entity_book.epub.sdr/xray_entity_cache.cache")

        plugin = createMockPlugin()
        local xray_entityscanner = require("xray_entityscanner")
        for k, v in pairs(xray_entityscanner) do
            plugin[k] = v
        end
        plugin.path = "xray.koplugin"
        plugin.ui.document.file = "/tmp/test_entity_book.epub"

        plugin.ai_helper = {
            settings = {
                entity_footnotes_enabled = true,
                entity_cat_characters = true,
                entity_cat_historical_figures = true,
                entity_cat_locations = true,
                entity_cat_terms = true,
                entity_mention_mode = "all",
                entity_popup_style = "footnote",
            },
            saveSettings = function(self_ah, new_st)
                for k, v in pairs(new_st) do
                    self_ah.settings[k] = v
                end
            end
        }

        plugin.characters = {
            { name = "Sherlock Holmes", aliases = { "Holmes", "Consulting Detective" }, description = "A brilliant detective." }
        }
        plugin.locations = {
            { name = "221B Baker Street", description = "The famous London residence." }
        }
        plugin.terms = {
            { name = "Scotland Yard", definition = "The headquarters of London police." }
        }
        plugin.historical_figures = {}

        plugin.ui.document.findAllText = function(self_doc, pat, regex, contextWords, maxResults, returnXPointers, flag)
            if pat:find("Holmes") or pat:find("Sherlock") then
                return {
                    { matched_text = "Sherlock Holmes", text = "Sherlock Holmes", start = "xp_start_1", start0 = "xp_start_1", ["end"] = "xp_end_1" },
                    { matched_text = "Holmes", text = "Holmes", start = "xp_start_2", start0 = "xp_start_2", ["end"] = "xp_end_2" },
                }
            end
            return {}
        end

        plugin.ui.document.getPageFromXPointer = function(self_doc, xp)
            if xp == "xp_start_1" or xp == "xp_end_1" then return 1 end
            if xp == "xp_start_2" or xp == "xp_end_2" then return 2 end
            return 1
        end

        plugin.ui.document.getScreenBoxesFromPositions = function(self_doc, start_xp, end_xp, flag)
            if start_xp == "xp_start_1" then
                return { { x = 100, y = 200, w = 120, h = 20 } }
            elseif start_xp == "xp_start_2" then
                return { { x = 100, y = 250, w = 60, h = 20 } }
            end
            return {}
        end
    end)

    after_each(function()
        _G.XRAY_DISABLE_ENTITY_SUBPROCESS = true
        package.loaded["ffi/util"] = orig_ffiutil
        local UIManager = require("ui/uimanager")
        UIManager.scheduleIn = original_scheduleIn
        pcall(os.remove, "/tmp/test_entity_book.epub.sdr/xray_entity_cache.cache")
    end)

    it("verifies SRELL regex character escaping does not escape '-' or '%'", function()
        -- Directly test regex escaping behavior
        local raw_term = "Twenty-One% Special (Class-A)"
        local esc = raw_term:gsub("([%^%$%.%*%+%?%(%)%[%]%{%}|\\])", "\\%1"):gsub("%s+", "\\s+")
        -- '-' and '%' must remain unescaped so SRELL doesn't throw error_escape (102)
        assert.is_nil(esc:find([[\-]], 1, true))
        assert.is_nil(esc:find([[\%]], 1, true))
        assert.is_not_nil(esc:find([[\(]], 1, true))
        assert.is_not_nil(esc:find([[\)]], 1, true))
    end)

    it("runs background entity scan via subprocess and writes atomic v3 cache", function()
        plugin:scanBookForEntities(true)
        assert.is_true(child_ran)

        -- Advance scheduled poll to process completion
        advance_time(1)

        assert.is_not_nil(plugin.entity_xp_matches)
        assert.are.equal(2, #plugin.entity_xp_matches)

        -- Verify page buckets populated directly from background scan
        assert.is_not_nil(plugin.entity_matches_by_page[1])
        assert.are.equal(1, #plugin.entity_matches_by_page[1])
        assert.are.equal("Sherlock Holmes", plugin.entity_matches_by_page[1][1].entity_name)

        assert.is_not_nil(plugin.entity_matches_by_page[2])
        assert.are.equal(1, #plugin.entity_matches_by_page[2])
        assert.are.equal("Holmes", plugin.entity_matches_by_page[2][1].matched_text)

        -- Verify cache was saved to disk
        local f = io.open("/tmp/test_entity_book.epub.sdr/xray_entity_cache.cache", "r")
        assert.is_not_nil(f)
        local sig = f:read("*l")
        assert.is_true(sig:find("^v3|") ~= nil)
        f:close()
    end)

    it("invalidates cache when entity list or categories change", function()
        -- First run and save
        plugin:scanBookForEntities(true)
        advance_time(1)
        assert.are.equal(2, #plugin.entity_xp_matches)

        -- Add new character to trigger signature change
        table.insert(plugin.characters, { name = "John Watson", description = "The loyal doctor." })

        local loaded = plugin:loadEntityCache("/tmp/test_entity_book.epub.sdr")
        -- Should return false because signature changed
        assert.is_false(loaded)
    end)

    it("handles watchdog timeout by cancelling subprocess", function()
        is_done_flag = false -- simulate hung child
        plugin:scanBookForEntities(true)
        assert.are.equal(8888, plugin._entity_scan_pid)

        -- Advance time past timeout
        plugin._entity_scan_started_at = os.time() - 400
        -- Manually invoke the poll callback
        plugin._entity_scan_poll_fn()

        assert.are.equal(8888, terminated_pid)
        assert.is_nil(plugin._entity_scan_pid)
    end)

    it("cancels running scan when document is closed", function()
        is_done_flag = false
        plugin:scanBookForEntities(true)
        assert.are.equal(8888, plugin._entity_scan_pid)

        plugin:_cancelEntityScanChild("document closing")
        assert.are.equal(8888, terminated_pid)
        assert.is_nil(plugin._entity_scan_pid)
    end)

    it("executes in-process fallback when FFI subprocess is disabled", function()
        _G.XRAY_DISABLE_ENTITY_SUBPROCESS = true
        plugin:scanBookForEntities(true)

        -- Advance event loop coroutine steps
        advance_time(0.1)
        advance_time(0.1)

        assert.is_not_nil(plugin.entity_xp_matches)
        assert.are.equal(2, #plugin.entity_xp_matches)
    end)

    it("deduplicates mentions per page when entity_mention_mode is 'first'", function()
        -- Setup 2 mentions of the same character on page 1
        plugin.entity_xp_matches = {
            { start_xp = "xp_start_1", end_xp = "xp_end_1", matched_text = "Sherlock Holmes", entity_name = "Sherlock Holmes", category = "character", page = 1 },
            { start_xp = "xp_start_1", end_xp = "xp_end_1", matched_text = "Holmes", entity_name = "Sherlock Holmes", category = "character", page = 1 },
        }
        plugin.entity_matches_by_page = {
            [1] = plugin.entity_xp_matches
        }
        plugin.last_pageno = 1

        plugin.ai_helper.settings.entity_mention_mode = "first"
        plugin:_resolveEntityHighlightBoxes()

        -- Only 1 box should be kept for Sherlock Holmes on page 1
        assert.are.equal(1, #plugin.entity_boxes)

        -- In "all" mode, both mentions are retained
        plugin.ai_helper.settings.entity_mention_mode = "all"
        plugin._entity_box_cache_sig = nil
        plugin:_resolveEntityHighlightBoxes()
        assert.are.equal(2, #plugin.entity_boxes)
    end)

    it("filters out entities that are not visible at current position (spoiler shield)", function()
        plugin.entity_xp_matches = {
            { start_xp = "xp_start_1", end_xp = "xp_end_1", matched_text = "Sherlock Holmes", entity_name = "Sherlock Holmes", category = "character", page = 1 },
        }
        plugin.entity_matches_by_page = { [1] = plugin.entity_xp_matches }
        plugin.last_pageno = 1

        plugin.isEntityVisibleAtCurrentPosition = function(self_pl, ent)
            return false -- hidden behind spoiler gate
        end

        plugin:_resolveEntityHighlightBoxes()
        assert.are.equal(0, #plugin.entity_boxes)

        plugin.isEntityVisibleAtCurrentPosition = function(self_pl, ent)
            return true -- unlocked
        end
        plugin._entity_box_cache_sig = nil
        plugin:_resolveEntityHighlightBoxes()
        assert.are.equal(1, #plugin.entity_boxes)
    end)

    it("routes tap to handleLookup in footnote mode and EntityTooltip in tooltip mode", function()
        plugin.entity_boxes = {
            { x = 100, y = 200, w = 120, h = 20, entity_name = "Sherlock Holmes", category = "character", matched_text = "Sherlock Holmes" }
        }

        local lookup_called = false
        plugin.lookup_manager = {
            handleLookup = function(self_lm, name)
                lookup_called = (name == "Sherlock Holmes")
            end
        }

        -- Tap inside box (105, 205)
        local handled = plugin:_handleEntityTap({ pos = { x = 105, y = 205 } })
        assert.is_true(handled)
        assert.is_true(lookup_called)

        -- Tap outside box (50, 50)
        local missed = plugin:_handleEntityTap({ pos = { x = 50, y = 50 } })
        assert.is_false(missed)
    end)

    it("generates uppercase and titlecase search variants for entity matching (e.g. HOUSTON)", function()
        plugin.locations = {
            { name = "Houston", description = "Mission Control" }
        }
        plugin.terms = {
            { name = "Atmospheric Regulator", aliases = { "regulator" }, definition = "Life support system" }
        }

        local terms, lookup = plugin._collectEntityTerms(plugin, {
            entity_cat_characters = true,
            entity_cat_historical_figures = true,
            entity_cat_locations = true,
            entity_cat_terms = true,
        })

        local terms_set = {}
        for _, t in ipairs(terms) do terms_set[t] = true end

        -- Capitalized location generates both Title Case and ALL-CAPS
        assert.is_true(terms_set["Houston"])
        assert.is_true(terms_set["HOUSTON"])

        -- Lowercase alias generates lowercase, Title Case, and ALL-CAPS
        assert.is_true(terms_set["regulator"])
        assert.is_true(terms_set["Regulator"])
        assert.is_true(terms_set["REGULATOR"])

        -- Lookup correctly maps lowercase keys to canonical entities
        assert.is_not_nil(lookup["houston"])
        assert.are.equal("Houston", lookup["houston"].canonical)
        assert.are.equal("location", lookup["houston"].category)

        assert.is_not_nil(lookup["regulator"])
        assert.are.equal("Atmospheric Regulator", lookup["regulator"].canonical)
    end)
end)
