-- CacheManager - X-Ray data caching system
local ok, lfs = pcall(require, "libs/libkoreader-lfs")
if not ok or type(lfs) ~= "table" then
    ok, lfs = pcall(require, "lfs")
end
if not ok or type(lfs) ~= "table" then
    lfs = nil
end
local logger = require("logger")
local DocSettings = require("docsettings")
local plugin_path = ((...) or ""):match("(.-)[^%.]+$") or ""
local AIHelper = require(plugin_path .. "xray_aihelper")

local CacheManager = {}

function CacheManager:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    o._active_saves = {}
    return o
end

function CacheManager:cancelAsyncSaves()
    local pending = {}
    for _, job in ipairs(self._active_saves or {}) do pending[#pending + 1] = job end
    for _, job in ipairs(pending) do job.cancel() end
end

-- Get cache file path for a book
function CacheManager:getCachePath(book_path)
    if not book_path then
        return nil
    end
    
    -- Use KOReader's sidecar directory
    local cache_dir = DocSettings:getSidecarDir(book_path)
    local cache_file = cache_dir .. "/xray_cache.lua"
    
    logger.info("CacheManager: Cache path:", cache_file)
    AIHelper:log("CacheManager: Cache path: " .. tostring(cache_file))
    return cache_file
end

-- Ensure directory exists
function CacheManager:ensureDirectory(path)
    if not lfs then return true end -- Assume it exists if we can't check
    local dir = path:match("(.+)/[^/]+$")
    if not dir then
        return false
    end
    
    if not lfs then return true end
    local attr = lfs.attributes(dir)
    if attr and attr.mode == "directory" then
        return true
    end

    
    logger.info("CacheManager: Creating directory:", dir)
    local success, err = lfs.mkdir(dir)
    
    if not success then
        logger.warn("CacheManager: Failed to create directory:", err or "unknown error")
        return false
    end
    
    return true
end

-- One writer per destination, including callers using different manager instances.
local writers = {}
local save_sequence = 0
local utils = require(plugin_path .. "xray_utils")

function CacheManager:_queueSave(book_path, data, on_done_cb)
    local path = book_path and self:getCachePath(book_path)
    if not path or not data or not self:ensureDirectory(path) then
        if on_done_cb then on_done_cb(false) end
        return nil
    end
    local snapshot = utils:copyTable(data)
    snapshot.cached_at = os.time()
    snapshot.cache_version = "6.0"
    save_sequence = save_sequence + 1
    local job = { path = path, temp = path .. ".tmp-" .. tostring(save_sequence) }
    local queue = writers[path] or {}
    writers[path] = queue
    queue[#queue + 1] = job
    self._active_saves = self._active_saves or {}
    self._active_saves[#self._active_saves + 1] = job
    local ok_ui, UIManager = pcall(require, "ui/uimanager")

    local function schedule()
        if ok_ui and UIManager.scheduleIn then
            UIManager:scheduleIn(0.05, job.step)
        else
            while not job.done do job.step() end
        end
    end
    local function finish(success)
        if job.done then return end
        job.done, job.success = true, success
        if job.file then pcall(function() job.file:close() end); job.file = nil end
        os.remove(job.temp)
        for i, entry in ipairs(self._active_saves) do
            if entry == job then table.remove(self._active_saves, i); break end
        end
        for i, entry in ipairs(queue) do
            if entry == job then table.remove(queue, i); break end
        end
        if #queue == 0 then writers[path] = nil end
        if on_done_cb then
            local ok, err = pcall(on_done_cb, success)
            if not ok then logger.warn("CacheManager: Save callback failed:", tostring(err)) end
        end
        if queue[1] then queue[1].schedule() end
    end
    job.cancel = function() finish(false) end
    job.schedule = schedule
    job.step = function()
        if job.done or queue[1] ~= job then return end
        if not job.co then
            job.co = coroutine.create(function()
                job.file = assert(io.open(job.temp, "w"))
                local writes = 0
                local sink = { write = function(_, ...)
                    assert(job.file:write(...))
                    writes = writes + 1
                    if writes % 100 == 0 then coroutine.yield() end
                end }
                sink:write("-- X-Ray Cache v6.0\nreturn ")
                self:serializeToFile(sink, snapshot, "")
                sink:write("\n")
                assert(job.file:flush())
                assert(job.file:close())
                job.file = nil
                assert(os.rename(job.temp, path))
            end)
        end
        local ok, err = coroutine.resume(job.co)
        if not ok then
            logger.warn("CacheManager: Atomic cache save failed:", tostring(err))
            finish(false)
        elseif coroutine.status(job.co) == "dead" then
            finish(true)
        else
            schedule()
        end
    end
    return job
end

-- Synchronous saves drain older snapshots first, so they cannot overwrite this one later.
function CacheManager:saveCache(book_path, data)
    local job = self:_queueSave(book_path, data)
    if not job then return false end
    while not job.done do
        local queue = writers[job.path]
        if queue and queue[1] then queue[1].step() end
    end
    return job.success
end

-- The return value reports acceptance; the callback reports the completed atomic rename.
function CacheManager:asyncSaveCache(book_path, data, on_done_cb)
    local job = self:_queueSave(book_path, data, on_done_cb)
    if not job then return false end
    if writers[job.path] and writers[job.path][1] == job then job.schedule() end
    return true, job.cancel
end

-- Load book data from cache
function CacheManager:loadCache(book_path)
    if not book_path then
        return nil
    end
    
    local cache_file = self:getCachePath(book_path)
    if not cache_file then
        logger.warn("CacheManager: Cannot determine cache path")
        AIHelper:log("CacheManager: Cannot determine cache path")
        return nil
    end
    
    -- Check if cache file exists
    if lfs then
        local attr = lfs.attributes(cache_file)
        if not attr then
            logger.info("CacheManager: No cache file found")
            AIHelper:log("CacheManager: No cache file found for " .. tostring(book_path))
            return nil
        end
    else
        -- If no lfs, try to open the file directly to see if it exists
        local f = io.open(cache_file, "r")
        if f then
            f:close()
        else
            return nil
        end
    end
    
    -- Load cache
    local success, data = pcall(function()
        return dofile(cache_file)
    end)
    
    if not success or not data then
        logger.warn("CacheManager: Failed to load cache:", data or "unknown error")
        AIHelper:log("CacheManager: Failed to load cache: " .. tostring(data or "unknown error"))
        return nil
    end
    
    -- Check cache version
    if data.cache_version ~= "6.0" then
        logger.warn("CacheManager: Cache version mismatch, ignoring")
        AIHelper:log("CacheManager: Cache version mismatch (found " .. tostring(data.cache_version) .. ", expected 6.0)")
        return nil
    end
    
    -- Cache age check removed - cache is now permanent
    -- Cache will stay valid forever unless manually cleared
    
    logger.info("CacheManager: Loaded cache from:", cache_file)
    AIHelper:log("CacheManager: Loaded cache from " .. tostring(cache_file))
    if data.cached_at then
        local cache_age_days = math.floor((os.time() - data.cached_at) / 86400)
        logger.info("CacheManager: Cache age:", cache_age_days, "days (no expiration)")
        AIHelper:log("CacheManager: Cache age: " .. tostring(cache_age_days) .. " days")
    end
    
    return data
end

-- Serialize a Lua value by writing tokens directly to an open file handle.
-- This avoids ever holding the full serialized text in RAM at once —
-- the OS file buffer absorbs each small write transparently.
function CacheManager:serializeToFile(f, obj, indent, seen)
    seen = seen or {}
    local t = type(obj)

    if t == "table" then
        if seen[obj] then
            f:write("{--[[circular reference]]}")
            return
        end
        seen[obj] = true

        f:write("{\n")
        local child_indent = indent .. "  "
        for k, v in pairs(obj) do
            if type(v) ~= "function" and type(v) ~= "userdata" and type(v) ~= "thread" then
                f:write(child_indent)
                if type(k) == "string" then
                    if k:match("^[%a_][%w_]*$") then
                        f:write(k)
                        f:write(" = ")
                    else
                        f:write("[")
                        f:write(string.format("%q", k))
                        f:write("] = ")
                    end
                else
                    f:write("[")
                    f:write(tostring(k))
                    f:write("] = ")
                end
                self:serializeToFile(f, v, child_indent, seen)
                f:write(",\n")
            end
        end
        f:write(indent)
        f:write("}")

    elseif t == "string" then
        f:write(string.format("%q", obj))
    elseif t == "number" or t == "boolean" then
        f:write(tostring(obj))
    else
        f:write("nil")
    end
end

-- Legacy serialize() retained for any external callers.
-- Internally, saveCache now uses serializeToFile instead.
function CacheManager:serialize(obj, indent, seen)
    indent = indent or ""
    seen = seen or {}
    local t = type(obj)
    if t == "table" then
        if seen[obj] then return "{--[[circular reference]]}" end
        seen[obj] = true
        local parts = {}
        for k, v in pairs(obj) do
            if type(v) ~= "function" and type(v) ~= "userdata" and type(v) ~= "thread" then
                local key
                if type(k) == "string" and k:match("^[%a_][%w_]*$") then
                    key = k .. " = "
                elseif type(k) == "string" then
                    key = "[" .. string.format("%q", k) .. "] = "
                else
                    key = "[" .. tostring(k) .. "] = "
                end
                table.insert(parts, indent .. "  " .. key .. self:serialize(v, indent .. "  ", seen) .. ",")
            end
        end
        return "{\n" .. table.concat(parts, "\n") .. "\n" .. indent .. "}"
    elseif t == "string" then
        return string.format("%q", obj)
    elseif t == "number" or t == "boolean" then
        return tostring(obj)
    else
        return "nil"
    end
end

-- Clear cache for a book
function CacheManager:clearCache(book_path)
    local cache_file = self:getCachePath(book_path)
    if cache_file then
        local success, err = os.remove(cache_file)
        if success then
            logger.info("CacheManager: Cleared cache:", cache_file)
            return true
        else
            logger.warn("CacheManager: Failed to clear cache:", err or "unknown")
            return false
        end
    end
    return false
end

return CacheManager