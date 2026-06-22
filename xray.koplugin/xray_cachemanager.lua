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
    return o
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

-- Save book data to cache.
-- Writes the serialized data directly to the file handle token-by-token so
-- that no large string ever exists in RAM. Peak memory is just the recursion
-- stack plus the OS file buffer, not the full serialized text.
function CacheManager:saveCache(book_path, data)
    if not book_path or not data then
        logger.warn("CacheManager: Cannot save cache - invalid parameters")
        return false
    end
    
    local cache_file = self:getCachePath(book_path)
    if not cache_file then
        logger.warn("CacheManager: Cannot determine cache path")
        return false
    end
    
    -- Ensure directory exists
    if not self:ensureDirectory(cache_file) then
        logger.warn("CacheManager: Cannot create cache directory")
        return false
    end
    
    -- Add timestamp
    data.cached_at = os.time()
    data.cache_version = "6.0"
    
    local success, err = pcall(function()
        local f, open_err = io.open(cache_file, "w")
        
        if not f then
            logger.warn("CacheManager: Cannot open file for writing:", cache_file)
            logger.warn("CacheManager: Error:", open_err or "unknown")
            return false
        end
        
        f:write("-- X-Ray Cache v6.0\n")
        f:write("-- Generated: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n\n")
        f:write("return ")
        
        local ok2, write_err = pcall(function()
            self:serializeToFile(f, data, "")
        end)
        
        f:write("\n")
        f:close()
        
        if not ok2 then
            logger.warn("CacheManager: Serialization error:", write_err or "unknown")
            AIHelper:log("CacheManager: Serialization error: " .. tostring(write_err or "unknown"))
            return false
        end
        
        logger.info("CacheManager: Saved cache to:", cache_file)
        AIHelper:log("CacheManager: Saved cache to: " .. tostring(cache_file))
        return true
    end)
    
    if not success then
        logger.warn("CacheManager: Failed to save cache:", err or "unknown error")
        AIHelper:log("CacheManager: Failed to save cache: " .. tostring(err or "unknown error"))
        return false
    end
    
    return success
end

-- Save book data to cache asynchronously using a cooperative coroutine-based recursive serializer.
-- Writing is executed in the background by yielding to KOReader's UIManager loop every 15 entries,
-- ensuring that all database tables (characters, terms, locations, etc.) are saved incrementally
-- without blocking the UI thread.
function CacheManager:asyncSaveCache(book_path, data, on_done_cb)
    if not book_path or not data then
        logger.warn("CacheManager: Cannot save cache async - invalid parameters")
        if on_done_cb then on_done_cb(false) end
        return false
    end

    local cache_file = self:getCachePath(book_path)
    if not cache_file then
        logger.warn("CacheManager: Cannot determine cache path for async save")
        if on_done_cb then on_done_cb(false) end
        return false
    end

    if not self:ensureDirectory(cache_file) then
        logger.warn("CacheManager: Cannot create cache directory for async save")
        if on_done_cb then on_done_cb(false) end
        return false
    end

    data.cached_at = os.time()
    data.cache_version = "6.0"

    -- ── UIManager cooperative coroutine path (primary) ──────────────────────
    local ok_ui, UIManager = pcall(require, "ui/uimanager")
    if ok_ui and UIManager then
        local f, open_err = io.open(cache_file, "w")
        if not f then
            logger.warn("CacheManager: Cannot open cache file for async write:", open_err or "unknown")
            if on_done_cb then on_done_cb(false) end
            return false
        end

        f:write("-- X-Ray Cache v6.0\n")
        f:write("-- Generated: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n\n")
        f:write("return ")

        local write_count = 0
        local serializeCo
        serializeCo = function(obj, indent, seen)
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
                        if type(k) == "number" then
                            f:write("[" .. k .. "] = ")
                        elseif type(k) == "string" and k:match("^[%a_][%w_]*$") then
                            f:write(k .. " = ")
                        else
                            f:write("[" .. string.format("%q", tostring(k)) .. "] = ")
                        end
                        serializeCo(v, child_indent, seen)
                        f:write(",\n")

                        -- Yield control back to UIManager loop periodically
                        write_count = write_count + 1
                        if write_count >= 20 then
                            write_count = 0
                            coroutine.yield()
                        end
                    end
                end
                f:write(indent .. "}")
            elseif t == "string" then
                f:write(string.format("%q", obj))
            elseif t == "number" or t == "boolean" then
                f:write(tostring(obj))
            else
                f:write("nil")
            end
        end

        local co = coroutine.create(function()
            serializeCo(data, "")
            f:write("\n")
        end)

        local function resumeCoroutine()
            local ok, err = coroutine.resume(co)
            if not ok then
                logger.warn("CacheManager: Error during async serialization:", err or "unknown")
                f:close()
                if on_done_cb then on_done_cb(false) end
                return
            end

            if coroutine.status(co) == "dead" then
                f:close()
                logger.info("CacheManager: Saved cache asynchronously (cooperative) to:", cache_file)
                AIHelper:log("CacheManager: Saved cache asynchronously (cooperative) to: " .. tostring(cache_file))
                if on_done_cb then on_done_cb(true) end
            else
                UIManager:scheduleIn(0.02, resumeCoroutine)
            end
        end

        UIManager:scheduleIn(0.02, resumeCoroutine)
        logger.info("CacheManager: Started cooperative async save to:", cache_file)
        return true
    end

    -- ── Fork-based fallback (rarely reached in practice) ─────────────────────
    local ok_ffi, ffiutil = pcall(require, "ffi/util")
    if not ok_ffi then
        ok_ffi, ffiutil = pcall(require, "ffiutil")
    end

    local function child_logic(pid, write_fd)
        local header = "-- X-Ray Cache v6.0\n-- Generated: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n\nreturn "
        local serialized_str = header .. self:serialize(data, "") .. "\n"
        pcall(function()
            local f = io.open(cache_file, "w")
            if f then
                f:write(serialized_str)
                f:close()
            end
        end)
        if write_fd and write_fd > 0 then
            pcall(function()
                local ffi = require("ffi")
                ffi.cdef[[ int close(int fd); ]]
                ffi.C.close(write_fd)
            end)
        end
        local ffi_ok, ffi = pcall(require, "ffi")
        if ffi_ok then
            pcall(function()
                ffi.cdef[[ void _exit(int status); ]]
                ffi.C._exit(0)
            end)
        end
        local posix_ok, posix = pcall(require, "posix.unistd")
        if posix_ok and posix and posix._exit then
            posix._exit(0)
        else
            os.exit(0)
        end
    end

    if ok_ffi and ffiutil and ffiutil.runInSubProcess then
        local pid, read_fd = ffiutil.runInSubProcess(child_logic, true)
        if pid and pid > 0 then
            if read_fd and read_fd > 0 then
                pcall(function()
                    local ffi = require("ffi")
                    ffi.cdef[[ int close(int fd); ]]
                    ffi.C.close(read_fd)
                end)
            end
            logger.info("CacheManager: Saved cache asynchronously (fork PID " .. tostring(pid) .. ") to:", cache_file)
            if on_done_cb then on_done_cb(true) end
            return true
        end
    end

    -- ── Final fallback: synchronous ───────────────────────────────────────────
    logger.info("CacheManager: Async save unavailable, using synchronous save")
    local success = self:saveCache(book_path, data)
    if on_done_cb then on_done_cb(success) end
    return success
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