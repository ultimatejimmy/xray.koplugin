-- xray_updater_spec.lua
require("spec/spec_helper")

describe("xray_updater", function()
    local updater
    local Device
    local UIManager

    setup(function()
        Device = require("device")
        UIManager = require("ui/uimanager")
        updater = require("xray_updater")
    end)

    before_each(function()
        _G.ui_tracker.shown = {}
        _G.ui_tracker.last_shown = nil
        _G.ui_tracker.closed = {}
        Device.screen.getHeight = function() return 800 end
        Device.screen.getWidth = function() return 600 end
    end)

    describe("_cleanReleaseNotes", function()
        it("should strip markdown links to plain text", function()
            local raw = "Fixed bug in ([115](https://github.com/ultimatejimmy/xray.koplugin/issues/115))."
            local cleaned = updater._cleanReleaseNotes(raw)
            assert.are.equal("Fixed bug in (115).", cleaned)
        end)

        it("should strip headers, bold, italics, and backticks", function()
            local raw = "## What's New\n**Feature:** `fast_mode` enabled *now*."
            local cleaned = updater._cleanReleaseNotes(raw)
            assert.are.equal("What's New\nFeature: fast_mode enabled now.", cleaned)
        end)

        it("should collapse multiple consecutive newlines", function()
            local raw = "Line 1\n\n\n\n\nLine 2"
            local cleaned = updater._cleanReleaseNotes(raw)
            assert.are.equal("Line 1\n\nLine 2", cleaned)
        end)
    end)

    describe("_formatInlineNotes", function()
        it("should return nil and false when notes are nil or empty", function()
            local preview, has_more = updater._formatInlineNotes(nil, 800)
            assert.is_nil(preview)
            assert.is_false(has_more)

            local preview2, has_more2 = updater._formatInlineNotes("", 800)
            assert.is_nil(preview2)
            assert.is_false(has_more2)
        end)

        it("should strip redundant What's New title line", function()
            local raw = "What's New:\n- Feature 1\n- Feature 2"
            local preview, has_more = updater._formatInlineNotes(raw, 800)
            assert.is_false(has_more)
            assert.are.equal("- Feature 1\n- Feature 2", preview)
        end)

        it("should truncate long multi-line notes on 600px screen height", function()
            local raw = "- Point 1: Added a long description here\n" ..
                        "- Point 2: Another detailed change description\n" ..
                        "- Point 3: A third feature was added\n" ..
                        "- Point 4: Fourth change\n" ..
                        "- Point 5: Fifth change"
            local preview, has_more = updater._formatInlineNotes(raw, 600)
            assert.is_true(has_more)
            -- On 600px screen, max_lines is 3 and max_chars is 140
            local line_count = 0
            for _ in preview:gmatch("([^\n]+)") do
                line_count = line_count + 1
            end
            assert.is_true(line_count <= 4)
            assert.is_true(preview:find("%.%.%.$") ~= nil)
        end)

        it("should keep short notes intact without truncation", function()
            local raw = "- Fix dictionary crash"
            local preview, has_more = updater._formatInlineNotes(raw, 800)
            assert.is_false(has_more)
            assert.are.equal("- Fix dictionary crash", preview)
        end)
    end)

    describe("_showUpdateDialog", function()
        it("should show up to date toast and not show update dialog if version is up to date", function()
            updater._showUpdateDialog({ version = "1.0.0" }, "1.0.0")
            local last = _G.ui_tracker.last_shown
            assert.is_not_nil(last)
            assert.are.equal("InfoMessage", last.type)
        end)

        it("should display a ButtonDialog with 1 button row when notes are short", function()
            local release = {
                version = "2.0.0",
                download_url = "https://example.com/download.zip",
                notes = "- Bug fix",
            }
            updater._showUpdateDialog(release, "1.0.0")
            local dlg = _G.ui_tracker.last_shown
            assert.are.equal("ButtonDialog", dlg.type)
            -- 1 row of buttons: Cancel, Download
            assert.are.equal(1, #dlg.buttons)
            assert.are.equal(2, #dlg.buttons[1])
            assert.are.equal("updater_btn_cancel", dlg.buttons[1][1].text)
            assert.are.equal("updater_btn_download", dlg.buttons[1][2].text)
            assert.is_true(dlg.buttons[1][2].is_enter_default)
        end)

        it("should display a ButtonDialog with 2 button rows when notes are long", function()
            local long_notes = ""
            for i = 1, 10 do
                long_notes = long_notes .. "- Long bullet item number " .. i .. " describing an update\n"
            end
            local release = {
                version = "2.0.0",
                download_url = "https://example.com/download.zip",
                notes = long_notes,
            }
            updater._showUpdateDialog(release, "1.0.0")
            local dlg = _G.ui_tracker.last_shown
            assert.are.equal("ButtonDialog", dlg.type)
            -- Row 1: View full release notes
            -- Row 2: Cancel, Download
            assert.are.equal(2, #dlg.buttons)
            assert.are.equal(1, #dlg.buttons[1])
            assert.are.equal("View full release notes", dlg.buttons[1][1].text)
            assert.are.equal(2, #dlg.buttons[2])
            assert.are.equal("updater_btn_cancel", dlg.buttons[2][1].text)
            assert.are.equal("updater_btn_download", dlg.buttons[2][2].text)

            -- Clicking 'View full release notes' should open a TextViewer
            dlg.buttons[1][1].callback()
            local viewer = _G.ui_tracker.last_shown
            assert.are.equal("TextViewer", viewer.type)
            assert.are.equal(long_notes, viewer.args.text)
            -- TextViewer has Back and Download buttons
            assert.are.equal(1, #viewer.args.buttons_table)
            assert.are.equal(2, #viewer.args.buttons_table[1])
            assert.are.equal("Back", viewer.args.buttons_table[1][1].text)
            assert.are.equal("updater_btn_download", viewer.args.buttons_table[1][2].text)
        end)

        it("should configure no_asset_dlg with view notes and open browser when download_url is missing", function()
            local long_notes = ""
            for i = 1, 10 do
                long_notes = long_notes .. "- Long bullet item number " .. i .. "\n"
            end
            local release = {
                version = "2.0.0",
                download_url = nil,
                notes = long_notes,
                html_url = "https://github.com/ultimatejimmy/xray.koplugin/releases/tag/2.0.0",
            }
            updater._showUpdateDialog(release, "1.0.0")
            local dlg = _G.ui_tracker.last_shown
            assert.are.equal("ButtonDialog", dlg.type)
            assert.are.equal(2, #dlg.buttons)
            assert.are.equal("View full release notes", dlg.buttons[1][1].text)
            assert.are.equal("updater_btn_cancel", dlg.buttons[2][1].text)
            assert.are.equal("updater_btn_open_browser", dlg.buttons[2][2].text)
        end)

        it("should set compact info_face on small/landscape screen height (< 700)", function()
            Device.screen.getHeight = function() return 600 end
            local release = {
                version = "2.0.0",
                download_url = "https://example.com/download.zip",
                notes = "- Bug fix",
            }
            updater._showUpdateDialog(release, "1.0.0")
            local dlg = _G.ui_tracker.last_shown
            assert.are.equal("ButtonDialog", dlg.type)
            assert.is_not_nil(dlg.info_face)
        end)
    end)

    describe("checkSilentForUpdates", function()
        local orig_ffiutil, orig_datastorage
        local scheduled = {}
        local orig_schedule

        before_each(function()
            scheduled = {}
            orig_schedule = UIManager.scheduleIn
            UIManager.scheduleIn = function(_, delay, cb)
                table.insert(scheduled, { delay = delay, cb = cb })
            end
        end)

        after_each(function()
            UIManager.scheduleIn = orig_schedule
            package.loaded["ffi/util"] = orig_ffiutil
        end)

        it("forks subprocess when ffiutil.runInSubProcess is available and shows dialog on update", function()
            local pid_started = 12345
            local pipe_read_fd = 99
            local sub_done = false
            local terminated = false

            package.loaded["ffi/util"] = {
                runInSubProcess = function(child_fn, with_pipe)
                    assert.is_true(with_pipe)
                    return pid_started, pipe_read_fd
                end,
                isSubProcessDone = function(pid)
                    return sub_done
                end,
                getNonBlockingReadSize = function(fd)
                    return sub_done and 50 or 0
                end,
                readAllFromFD = function(fd)
                    return '{"version": "99.0.0", "download_url": "https://example.com/dl.zip", "notes": "New version"}'
                end,
                terminateSubProcess = function(pid)
                    terminated = true
                end
            }

            local status_reported = nil
            updater.checkSilentForUpdates(nil, false, {
                on_done = function(status)
                    status_reported = status
                end
            })

            -- Poller scheduled
            assert.are.equal(1, #scheduled)
            assert.is_nil(status_reported)

            -- Simulate subprocess completing
            sub_done = true
            scheduled[1].cb()

            assert.are.equal("shown", status_reported)
            local last = _G.ui_tracker.last_shown
            assert.is_not_nil(last)
            assert.are.equal("ButtonDialog", last.type)
        end)

        it("suppresses dialog when should_show returns false", function()
            package.loaded["ffi/util"] = {
                runInSubProcess = function(child_fn, with_pipe)
                    return 12345, 99
                end,
                isSubProcessDone = function(pid) return true end,
                getNonBlockingReadSize = function(fd) return 50 end,
                readAllFromFD = function(fd)
                    return '{"version": "99.0.0", "download_url": "https://example.com/dl.zip"}'
                end,
                terminateSubProcess = function() end
            }

            local status_reported = nil
            updater.checkSilentForUpdates(nil, false, {
                should_show = function() return false end,
                on_done = function(status) status_reported = status end
            })

            assert.are.equal(1, #scheduled)
            scheduled[1].cb()

            assert.are.equal("suppressed_update", status_reported)
            assert.is_nil(_G.ui_tracker.last_shown)
        end)

        it("reports error and terminates subprocess on timeout", function()
            local terminated = false
            package.loaded["ffi/util"] = {
                runInSubProcess = function(child_fn, with_pipe)
                    return 12345, 99
                end,
                isSubProcessDone = function(pid) return false end,
                getNonBlockingReadSize = function(fd) return 0 end,
                readAllFromFD = function() end,
                terminateSubProcess = function() terminated = true end
            }

            local status_reported = nil
            updater.checkSilentForUpdates(nil, false, {
                on_done = function(status) status_reported = status end
            })

            -- Step through 90 poll loops
            for i = 1, 90 do
                local next_item = table.remove(scheduled, 1)
                assert.is_not_nil(next_item)
                next_item.cb()
            end

            assert.is_true(terminated)
            assert.are.equal("error", status_reported)
        end)
    end)
end)
