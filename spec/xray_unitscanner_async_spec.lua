-- spec/xray_unitscanner_async_spec.lua
require("spec/spec_helper")

describe("xray_unitscanner async and background execution", function()
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
                -- restart scan as fn may have scheduled new tasks
                i = 1
            else
                i = i + 1
            end
        end
    end

    before_each(function()
        orig_ffiutil = package.loaded["ffi/util"]
        _G.XRAY_DISABLE_UNIT_SUBPROCESS = false
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
                -- Run child logic inline for deterministic testing
                child_fn(9999, "fake_write_fd")
                return 9999, "fake_read_fd"
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

        pcall(os.execute, "mkdir -p /tmp/test_book.epub.sdr")
        pcall(os.remove, "/tmp/test_book.epub.sdr/xray_unit_cache_to_imperial.cache")
        pcall(os.remove, "/tmp/test_book.epub.sdr/xray_unit_cache_to_metric.cache")

        plugin = createMockPlugin()
        local xray_unitscanner = require("xray_unitscanner")
        for k, v in pairs(xray_unitscanner) do
            plugin[k] = v
        end
        plugin.path = "xray.koplugin"
        plugin.ui.document.file = "/tmp/test_book.epub"

        plugin.ai_helper = {
            settings = {
                unit_converter_enabled = true,
                unit_underline_enabled = true,
                unit_conversion_direction = "to_imperial",
                unit_auto_scan_enabled = true,
            }
        }

        local mock_hits = {
            {
                matched_text = "meters",
                start = "xp1",
                ["end"] = "xp2",
                prev_text = "he walked five ",
                next_text = " today."
            }
        }
        plugin.ui.document.findAllText = function(self_doc, pat, regex, contextWords, maxResults, returnXPointers)
            if pat:find("met") then
                return mock_hits
            end
            return {}
        end
        plugin.ui.document.getPrevVisibleWordStart = function(self_doc, cand)
            if cand == "xp1" then return "xp_five" end
            return cand
        end
        plugin.ui.document.getTextFromXPointers = function(self_doc, cand, unit_end)
            if cand == "xp_five" and unit_end == "xp2" then return "five meters" end
            if cand == "xp_five" then return "five" end
            return ""
        end
    end)

    after_each(function()
        _G.XRAY_DISABLE_UNIT_SUBPROCESS = true
        package.loaded["ffi/util"] = orig_ffiutil
        local UIManager = require("ui/uimanager")
        UIManager.scheduleIn = original_scheduleIn
        pcall(os.remove, "/tmp/test_book.epub.sdr/xray_unit_cache_to_imperial.cache")
        pcall(os.remove, "/tmp/test_book.epub.sdr/xray_unit_cache_to_metric.cache")
    end)

    it("runs scan via subprocess on auto scan and repaints without toast", function()
        local last_notif = nil
        local orig_notif_new = package.loaded["ui/widget/notification"].new
        package.loaded["ui/widget/notification"].new = function(self_cls, args)
            last_notif = args
            return orig_notif_new(self_cls, args)
        end

        plugin:scanBookForUnits()
        advance_time(1)

        assert.is_true(child_ran)
        assert.is_not_nil(plugin.unit_xp_matches)
        assert.are.equal(1, #plugin.unit_xp_matches)
        assert.are.equal("five meters", plugin.unit_xp_matches[1].original)
        -- Auto scan must NOT show completion toast
        assert.is_nil(last_notif)

        package.loaded["ui/widget/notification"].new = orig_notif_new
    end)

    it("shows modal progress dialog and completion toast on manual rescan", function()
        local shown_dialog = nil
        local last_notif = nil
        local orig_notif_new = package.loaded["ui/widget/notification"].new
        package.loaded["ui/widget/notification"].new = function(self_cls, args)
            last_notif = args
            return orig_notif_new(self_cls, args)
        end

        plugin:scanBookForUnits(true)
        advance_time(1)

        assert.is_true(child_ran)
        assert.is_not_nil(plugin.unit_xp_matches)
        assert.are.equal(1, #plugin.unit_xp_matches)
        assert.is_not_nil(last_notif)
        assert.truthy(last_notif.text:find("unit conversions found"))

        package.loaded["ui/widget/notification"].new = orig_notif_new
    end)

    it("terminates subprocess cleanly when user cancels/dismisses dialog", function()
        is_done_flag = false -- simulate child still working
        fake_ffiutil.runInSubProcess = function(child_fn, with_pipe)
            -- Does not finish immediately
            return 9999, "fake_read_fd"
        end

        plugin:scanBookForUnits(true)

        assert.are.equal(9999, plugin._unit_scan_pid)
        assert.is_true(plugin._unit_scan_in_progress)
        assert.is_not_nil(plugin._unit_scan_dialog)

        -- Trigger dismiss
        plugin._unit_scan_dialog.dismiss_callback()

        assert.are.equal(9999, terminated_pid)
        assert.is_nil(plugin._unit_scan_pid)
        assert.is_false(plugin._unit_scan_in_progress)
    end)

    it("skips silently on auto scan when fork fails without blocking main thread", function()
        fail_fork = true
        plugin:scanBookForUnits()

        assert.is_nil(plugin.unit_xp_matches)
        assert.is_false(plugin._unit_scan_in_progress)
    end)

    it("falls back to in-process scan when fork fails on manual rescan", function()
        fail_fork = true
        plugin:scanBookForUnits(true)
        advance_time(1)

        assert.is_not_nil(plugin.unit_xp_matches)
        assert.are.equal(1, #plugin.unit_xp_matches)
        assert.is_false(plugin._unit_scan_in_progress)
    end)

    it("defers unit scan when AI fetch child is active without cancelling AI process", function()
        plugin.ai_helper._async_child_pid = 7777
        local ai_cancelled = false
        plugin.ai_helper.cancelAsyncChild = function()
            ai_cancelled = true
        end

        plugin:scanBookForUnits(true)

        assert.is_false(ai_cancelled)
        assert.are.equal(1, plugin._unit_scan_fetch_retries)
        assert.is_false(child_ran)
    end)

    it("cancels subprocess on timeout", function()
        is_done_flag = false
        fake_ffiutil.runInSubProcess = function(child_fn, with_pipe)
            return 8888, "fake_read_fd"
        end

        plugin:scanBookForUnits(true)
        assert.are.equal(8888, plugin._unit_scan_pid)

        -- Advance time past timeout
        plugin._unit_scan_started_at = os.time() - 400
        -- Manually invoke the poll callback
        plugin._unit_scan_poll_fn()

        assert.are.equal(8888, terminated_pid)
        assert.is_nil(plugin._unit_scan_pid)
        assert.is_false(plugin._unit_scan_in_progress)
    end)

    it("skips scan for page-based documents", function()
        plugin.ui.paging = {}
        plugin.ui.rolling = nil
        plugin.ui.document.isReflowable = function() return false end

        plugin:scanBookForUnits(true)

        assert.is_false(child_ran)
        assert.is_nil(plugin.unit_xp_matches)
    end)
end)
