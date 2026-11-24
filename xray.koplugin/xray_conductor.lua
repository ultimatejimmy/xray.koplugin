-- xray_conductor.lua
-- Zero-hard-dependency facade for Storefront's Memory Conductor API (storefront_conductor).
-- Coordinates background tasks, pre-fork heap stabilization, and cross-plugin cache eviction.

local plugin_path = ((...) or ""):match("(.-)[^%.]+$") or ""
local ok_log, logger = pcall(require, "logger")
if not ok_log or not logger then
    logger = { info = function() end, warn = function() end, error = function() end, dbg = function() end }
end

local M = {}

local function _log(plugin, msg)
    if plugin and plugin.log then
        pcall(function() plugin:log(msg) end)
    elseif logger and logger.info then
        logger.info(msg)
    end
end

--- Safely loads Storefront's Memory Conductor module if installed.
--- @return table|nil
function M.get()
    local ok, mod = pcall(require, "storefront_conductor")
    if ok and type(mod) == "table" then
        return mod
    end
    return nil
end

--- Returns true when Storefront Memory Conductor is available with requestSlot.
--- @return boolean
function M.isAvailable()
    local c = M.get()
    return c ~= nil and type(c.requestSlot) == "function"
end

--- Registers X-Ray with Storefront's Memory Conductor for targeted reclaim and cancellation.
--- Safe no-op if Storefront is not installed.
--- @param plugin table XRayPlugin instance
--- @return boolean registered
function M.register(plugin)
    local c = M.get()
    if not c or type(c.registerPlugin) ~= "function" or not plugin then
        return false
    end
    local ok, err = pcall(function()
        c.registerPlugin({
            plugin = "xray",
            is_foreground = function()
                if plugin.destroyed then return false end
                if plugin.isXRayForegroundOpen then
                    return plugin:isXRayForegroundOpen() == true
                end
                return false
            end,
            on_reclaim = function(level)
                if plugin.destroyed then return end
                if plugin.reclaimMemory then
                    plugin:reclaimMemory(level)
                elseif plugin.onLowMemory and level == "critical" then
                    plugin:onLowMemory()
                end
            end,
            on_cancel_bg = function()
                if plugin.destroyed then return end
                if plugin.cancelBackgroundWork then
                    plugin:cancelBackgroundWork("conductor_cancel_bg")
                end
            end,
        })
    end)
    if not ok then
        _log(plugin, "XRayConductor: registerPlugin failed: " .. tostring(err))
        return false
    end
    _log(plugin, "XRayConductor: Registered plugin 'xray' with Storefront Memory Conductor")
    return true
end

--- Executes or queues a task under Conductor supervision if available,
--- or runs it immediately with a one-shot done() callback when standalone.
---
--- Supported opts:
---   task        (string)   Descriptive task name
---   priority    (string)   "foreground" | "interactive_bg" | "idle_bg" (default "idle_bg")
---   min_free_kb (number)   Optional RAM floor in KB
---   subprocess  (boolean)  True if task calls runInSubProcess / makeRequestAsync
---   sync        (boolean)  True if task is synchronous
---   document    (table)    Optional document reference for stale-document guard
---   run         (function) function(done) ... end (Required)
---   cancel      (function) Optional preemption/abort callback
---   on_rejected (function) Optional function(reason) callback
---
--- @param plugin table|nil XRayPlugin instance
--- @param opts table
--- @return any slot_handle
function M.runSlot(plugin, opts)
    if type(opts) ~= "table" or type(opts.run) ~= "function" then
        return nil
    end

    local expected_doc = opts.document
    local function isStale()
        if plugin then
            if plugin.destroyed then return true end
            if expected_doc ~= nil then
                local cur_doc = plugin.ui and plugin.ui.document
                if cur_doc ~= expected_doc then
                    return true
                end
            end
        end
        return false
    end

    local c = M.get()
    if c and type(c.requestSlot) == "function" then
        local wrapped_done = nil
        local function makeOneShot(raw_done)
            local called = false
            return function()
                if called then return end
                called = true
                if type(raw_done) == "function" then
                    pcall(raw_done)
                end
            end
        end

        return c.requestSlot({
            plugin = "xray",
            task = opts.task or "task",
            priority = opts.priority or "idle_bg",
            min_free_kb = opts.min_free_kb,
            lease_s = opts.lease_s,
            dedupe_key = opts.dedupe_key,
            subprocess = opts.subprocess == true,
            sync = opts.sync == true,
            run = function(raw_done)
                local safe_done = makeOneShot(raw_done)
                wrapped_done = safe_done
                if isStale() then
                    safe_done()
                    return
                end
                opts.run(safe_done)
            end,
            cancel = function()
                if opts.cancel then
                    pcall(opts.cancel)
                end
                if wrapped_done then
                    wrapped_done()
                end
            end,
            on_rejected = function(reason)
                _log(plugin, string.format("XRayConductor: Task '%s' rejected (%s)", tostring(opts.task or "task"), tostring(reason)))
                if opts.on_rejected then
                    opts.on_rejected(reason)
                end
            end,
        })
    end

    -- Standalone fallback when Storefront is not installed
    local standalone_called = false
    local function standaloneDone()
        if standalone_called then return end
        standalone_called = true
    end
    if isStale() then
        standaloneDone()
        return nil
    end
    opts.run(standaloneDone)
    return nil
end

--- Triggers cross-plugin memory reclaim if Storefront Conductor is available.
--- @param level string|nil "soft" or "critical" (default "soft")
--- @param exclude_plugin string|nil Plugin name to exclude (default "xray")
--- @return boolean invoked
function M.reclaimMemory(level, exclude_plugin)
    local c = M.get()
    if c and type(c.reclaimMemory) == "function" then
        local ok = pcall(c.reclaimMemory, level or "soft", exclude_plugin or "xray")
        return ok
    end
    return false
end

--- Returns diagnostic memory status from Storefront Conductor if available.
--- @return table|nil
function M.getMemoryStatus()
    local c = M.get()
    if c and type(c.getMemoryStatus) == "function" then
        local ok, status = pcall(c.getMemoryStatus)
        if ok and type(status) == "table" then
            return status
        end
    end
    return nil
end

--- Returns lightweight session intervention counters from Storefront Conductor if available.
--- @return table|nil
function M.getStats()
    local c = M.get()
    if c and type(c.getStats) == "function" then
        local ok, stats = pcall(c.getStats)
        if ok and type(stats) == "table" then
            return stats
        end
    end
    return nil
end

return M
