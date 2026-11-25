require("spec/spec_helper")

describe("XRayLogViewer", function()
    local LogViewerMod
    local Blitbuffer
    local tmp_dir
    local saved_loaded

    local function makeFakeLoc()
        return {
            t = function(_, key)
                local map = {
                    menu_view_log = "View Log",
                    log_empty = "Log is empty.",
                    close = "Close",
                    logs_cleared = "Logs cleared!",
                }
                return map[key]
            end,
        }
    end

    local function makeSizedWidgetMock(wtype, w, h)
        return {
            new = function(a, b)
                return {
                    type = wtype,
                    args = b or a,
                    getSize = function() return { w = w, h = h } end,
                }
            end,
        }
    end

    before_each(function()
        _G.Blitbuffer = nil
        _G.ui_tracker.shown = {}
        _G.ui_tracker.last_shown = nil
        _G.ui_tracker.closed = {}

        saved_loaded = {
            ["ui/widget/horizontalgroup"] = package.loaded["ui/widget/horizontalgroup"],
            ["ui/widget/textboxwidget"] = package.loaded["ui/widget/textboxwidget"],
            ["ui/widget/linewidget"] = package.loaded["ui/widget/linewidget"],
            ["ui/widget/button"] = package.loaded["ui/widget/button"],
            ["xray_logger"] = package.loaded["xray_logger"],
            ["xray_log_viewer"] = package.loaded["xray_log_viewer"],
        }

        package.loaded["ui/widget/horizontalgroup"] = makeSizedWidgetMock("HorizontalGroup", 200, 30)
        package.loaded["ui/widget/textboxwidget"] = makeSizedWidgetMock("TextBoxWidget", 400, 24)
        package.loaded["ui/widget/linewidget"] = makeSizedWidgetMock("LineWidget", 400, 2)
        package.loaded["ui/widget/button"] = makeSizedWidgetMock("Button", 80, 30)

        Blitbuffer = require("ffi/blitbuffer")
        package.loaded["xray_log_viewer"] = nil
        LogViewerMod = require("xray_log_viewer")

        tmp_dir = "/tmp/xray_log_viewer_test_" .. tostring(os.time()) .. "_" .. tostring(math.random(100000))
        os.execute("mkdir -p " .. tmp_dir)
    end)

    after_each(function()
        if saved_loaded then
            for k, v in pairs(saved_loaded) do
                package.loaded[k] = v
            end
            saved_loaded = nil
        end
        if tmp_dir then
            os.execute("rm -rf " .. tmp_dir)
            tmp_dir = nil
        end
    end)

    it("renders XRayLogViewer without relying on global Blitbuffer", function()
        assert.is_nil(_G.Blitbuffer)
        local viewer = LogViewerMod.XRayLogViewer:new{
            pages = { "Line 1\nLine 2", "Line 3\nLine 4" },
            current_page = 2,
            close_label = "Close",
            ui_instance = { loc = makeFakeLoc() },
        }

        assert.is_not_nil(viewer)
        assert.is_not_nil(viewer.frame)
        local frame_bg = (viewer.frame.args and viewer.frame.args.background) or viewer.frame.background
        assert.are.equal(Blitbuffer.COLOR_WHITE, frame_bg)
        assert.are.equal(2, viewer.current_page)
    end)

    it("navigates pages with onPrevPage and onNextPage without error", function()
        local viewer = LogViewerMod.XRayLogViewer:new{
            pages = { "Page 1 content", "Page 2 content", "Page 3 content" },
            current_page = 3,
            close_label = "Close",
            ui_instance = { loc = makeFakeLoc() },
        }

        assert.is_true(viewer:onPrevPage())
        assert.are.equal(2, viewer.current_page)

        assert.is_true(viewer:onPrevPage())
        assert.are.equal(1, viewer.current_page)

        -- Clamped at page 1
        assert.is_true(viewer:onPrevPage())
        assert.are.equal(1, viewer.current_page)

        assert.is_true(viewer:onNextPage())
        assert.are.equal(2, viewer.current_page)
    end)

    it("opens on the latest page via viewLog and handles reload", function()
        local log_file = tmp_dir .. "/xray.log"
        local lines = {}
        for i = 1, 35 do
            table.insert(lines, "2026-11-25 12:00:00 Entry " .. tostring(i))
        end
        local f = io.open(log_file, "w")
        assert.is_not_nil(f)
        f:write(table.concat(lines, "\n") .. "\n")
        f:close()

        package.loaded["xray_logger"] = { path = tmp_dir, clear = function() end }

        local host = {
            loc = makeFakeLoc(),
            viewLog = LogViewerMod.viewLog,
        }
        host:viewLog()

        assert.is_not_nil(host.log_viewer)
        assert.are.equal(2, #host.log_viewer.pages)
        assert.are.equal(2, host.log_viewer.current_page)
        assert.are.equal(host.log_viewer, _G.ui_tracker.last_shown)

        -- Reload from disk should succeed cleanly
        assert.is_true(host.log_viewer:onReload())
        assert.are.equal(2, host.log_viewer.current_page)
    end)

    it("shows InfoMessage when log file is missing or empty", function()
        package.loaded["xray_logger"] = { path = tmp_dir, clear = function() end }

        local host = {
            loc = makeFakeLoc(),
            viewLog = LogViewerMod.viewLog,
        }
        host:viewLog()

        assert.is_nil(host.log_viewer)
        assert.is_not_nil(_G.ui_tracker.last_shown)
        local shown_text = (_G.ui_tracker.last_shown.args and _G.ui_tracker.last_shown.args.text) or _G.ui_tracker.last_shown.text
        assert.are.equal("Log is empty.", shown_text)
    end)
end)
