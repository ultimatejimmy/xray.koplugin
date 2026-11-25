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

local CURRENT_CACHE_VERSION = "6.1"
local SUPPORTED_CACHE_VERSIONS = {
    ["6.0"] = true,
    ["6.1"] = true,
}
local SUPPORTED_SCHEMA_VERSIONS = {
    ["1.0"] = true,
}
local MAX_JSON_CACHE_BYTES = 5 * 1024 * 1024 -- 5MB safety guard for low-RAM e-ink devices

local function getJsonModule()
    local ok_j, mod = pcall(require, "json")
    if ok_j and type(mod) == "table" and type(mod.decode) == "function" then
        return mod
    end
    local ok_rj, rmod = pcall(require, "rapidjson")
    if ok_rj and type(rmod) == "table" and type(rmod.decode) == "function" then
        return rmod
    end
    return nil
end

local CacheManager = {
    CURRENT_CACHE_VERSION = CURRENT_CACHE_VERSION,
    SUPPORTED_CACHE_VERSIONS = SUPPORTED_CACHE_VERSIONS,
    SUPPORTED_SCHEMA_VERSIONS = SUPPORTED_SCHEMA_VERSIONS,
    MAX_JSON_CACHE_BYTES = MAX_JSON_CACHE_BYTES,
    _active_by_file = {},
    _pending_by_file = {},
}

local function atomicRename(temp_file, cache_file)
    local ren_ok, ren_err = os.rename(temp_file, cache_file)
    if not ren_ok then
        -- Fallback for platforms where os.rename cannot overwrite an existing destination (e.g. Windows CRT)
        pcall(os.remove, cache_file)
        ren_ok, ren_err = os.rename(temp_file, cache_file)
    end
    return ren_ok, ren_err
end

function CacheManager:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    o._active_saves = {}
    return o
end

function CacheManager:cancelAsyncSaves(flush)
    if flush then
        return self:flushAsyncSaves()
    end
    if CacheManager._active_by_file then
        for cache_file, entry in pairs(CacheManager._active_by_file) do
            entry.cancelled = true
            if entry.file then
                pcall(function() entry.file:close() end)
                entry.file = nil
            end
            if entry.path then
                pcall(os.remove, entry.path)
            end
            if entry.callbacks then
                for _, cb in ipairs(entry.callbacks) do
                    pcall(cb, false)
                end
            end
        end
        CacheManager._active_by_file = {}
    end
    if CacheManager._pending_by_file then
        for _, entry in pairs(CacheManager._pending_by_file) do
            if entry.callbacks then
                for _, cb in ipairs(entry.callbacks) do
                    pcall(cb, false)
                end
            end
        end
        CacheManager._pending_by_file = {}
    end
    self._active_saves = {}
end

function CacheManager:flushAsyncSaves()
    local to_save = {}

    if CacheManager._pending_by_file then
        for cache_file, entry in pairs(CacheManager._pending_by_file) do
            to_save[cache_file] = {
                book_path = entry.book_path,
                data = entry.data,
                callbacks = entry.callbacks or {}
            }
        end
        CacheManager._pending_by_file = {}
    end

    if CacheManager._active_by_file then
        for cache_file, entry in pairs(CacheManager._active_by_file) do
            entry.cancelled = true
            if entry.file then
                pcall(function() entry.file:close() end)
                entry.file = nil
            end
            if entry.path then
                pcall(os.remove, entry.path)
            end
            if not to_save[cache_file] then
                to_save[cache_file] = {
                    book_path = entry.book_path,
                    data = entry.data,
                    callbacks = entry.callbacks or {}
                }
            else
                if entry.callbacks then
                    for _, cb in ipairs(entry.callbacks) do
                        table.insert(to_save[cache_file].callbacks, cb)
                    end
                end
            end
        end
        CacheManager._active_by_file = {}
    end

    self._active_saves = {}

    for _, item in pairs(to_save) do
        local ok = self:saveCache(item.book_path, item.data)
        for _, cb in ipairs(item.callbacks) do
            pcall(cb, ok)
        end
    end
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

-- Get external JSON cache file path for a book (read-only by X-Ray)
function CacheManager:getJsonCachePath(book_path)
    if not book_path then
        return nil
    end
    local cache_dir = DocSettings:getSidecarDir(book_path)
    if not cache_dir then
        return nil
    end
    return cache_dir .. "/xray_cache.json"
end

-- Returns true if the cache data requests protection against background AI overwrites
function CacheManager:isOverwriteProtected(data)
    if type(data) ~= "table" then return false end
    if data.read_only == true or data.prevent_overwrite == true then
        return true
    end
    if type(data.external_source) == "table" then
        return data.external_source.prevent_overwrite ~= false
    end
    return false
end

-- Returns true if the cache data is strictly read-only (blocks local saves)
function CacheManager:isReadOnly(data)
    if type(data) ~= "table" then return false end
    if data.read_only == true then return true end
    if type(data.external_source) == "table" and data.external_source.read_only == true then
        return true
    end
    return false
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
    if self:isReadOnly(data) then
        logger.info("CacheManager: Cache is marked read_only, skipping save")
        AIHelper:log("CacheManager: Cache is marked read_only, skipping save")
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

    -- Cancel any active or pending async save on this file before synchronous write
    if CacheManager._active_by_file and CacheManager._active_by_file[cache_file] then
        local active = CacheManager._active_by_file[cache_file]
        active.cancelled = true
        if active.file then
            pcall(function() active.file:close() end)
            active.file = nil
        end
        if active.path then
            pcall(os.remove, active.path)
        end
        if active.callbacks then
            for _, cb in ipairs(active.callbacks) do
                pcall(cb, false)
            end
        end
        CacheManager._active_by_file[cache_file] = nil
        if self._active_saves then
            for idx, entry in ipairs(self._active_saves) do
                if entry == active then
                    table.remove(self._active_saves, idx)
                    break
                end
            end
        end
    end

    if CacheManager._pending_by_file and CacheManager._pending_by_file[cache_file] then
        local pending = CacheManager._pending_by_file[cache_file]
        if pending.callbacks then
            for _, cb in ipairs(pending.callbacks) do
                pcall(cb, false)
            end
        end
        CacheManager._pending_by_file[cache_file] = nil
    end
    
    -- Add timestamp
    data.cached_at = os.time()
    data.cache_version = CURRENT_CACHE_VERSION
    
    local temp_file = cache_file .. ".tmp"
    local success, err = pcall(function()
        local f, open_err = io.open(temp_file, "w")
        
        if not f then
            logger.warn("CacheManager: Cannot open file for writing:", temp_file)
            logger.warn("CacheManager: Error:", open_err or "unknown")
            return false
        end
        
        f:write("-- X-Ray Cache v" .. CURRENT_CACHE_VERSION .. "\n")
        f:write("-- Generated: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n\n")
        f:write("return ")
        
        local ok2, write_err = pcall(function()
            self:serializeToFile(f, data, "")
        end)
        
        f:write("\n")
        f:close()
        
        if not ok2 then
            pcall(os.remove, temp_file)
            logger.warn("CacheManager: Serialization error:", write_err or "unknown")
            AIHelper:log("CacheManager: Serialization error: " .. tostring(write_err or "unknown"))
            return false
        end
        
        local ren_ok, ren_err = atomicRename(temp_file, cache_file)
        if not ren_ok then
            pcall(os.remove, temp_file)
            logger.warn("CacheManager: Failed to rename temp file to cache file:", ren_err or "unknown")
            AIHelper:log("CacheManager: Failed to rename temp file: " .. tostring(ren_err or "unknown"))
            return false
        end
        logger.info("CacheManager: Saved cache to:", cache_file)
        AIHelper:log("CacheManager: Saved cache to: " .. tostring(cache_file))
        return true
    end)
    
    if not success then
        pcall(os.remove, temp_file)
        logger.warn("CacheManager: Failed to save cache:", err or "unknown error")
        AIHelper:log("CacheManager: Failed to save cache: " .. tostring(err or "unknown error"))
        return false
    end
    
    return success
end

function CacheManager:_triggerPendingSave(cache_file)
    local pending = CacheManager._pending_by_file and CacheManager._pending_by_file[cache_file]
    if pending then
        CacheManager._pending_by_file[cache_file] = nil
        local cm = pending.cm or self
        cm:_startAsyncSave(cache_file, pending.book_path, pending.data, pending.callbacks)
    end
end

-- Save book data to cache asynchronously using a cooperative coroutine-based recursive serializer.
-- Writing is executed in the background by yielding to KOReader's UIManager loop periodically,
-- ensuring that all database tables (characters, terms, locations, etc.) are saved incrementally
-- without blocking the UI thread. Concurrent saves to the same book cache are serialized and coalesced.
function CacheManager:asyncSaveCache(book_path, data, on_done_cb)
    if not book_path or not data then
        logger.warn("CacheManager: Cannot save cache async - invalid parameters")
        if on_done_cb then on_done_cb(false) end
        return false
    end
    if self:isReadOnly(data) then
        logger.info("CacheManager: Cache is marked read_only, skipping async save")
        AIHelper:log("CacheManager: Cache is marked read_only, skipping async save")
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
    data.cache_version = CURRENT_CACHE_VERSION

    -- Check if an active save is already in progress for this cache file
    if CacheManager._active_by_file and CacheManager._active_by_file[cache_file] then
        local pending = CacheManager._pending_by_file[cache_file]
        if pending then
            pending.data = data
            pending.book_path = book_path
            if on_done_cb then
                table.insert(pending.callbacks, on_done_cb)
            end
        else
            CacheManager._pending_by_file[cache_file] = {
                book_path = book_path,
                data = data,
                callbacks = on_done_cb and { on_done_cb } or {},
                cm = self
            }
        end
        logger.info("CacheManager: Queued/coalesced async save for:", cache_file)
        return true
    end

    return self:_startAsyncSave(cache_file, book_path, data, on_done_cb and { on_done_cb } or {})
end

function CacheManager:_startAsyncSave(cache_file, book_path, data, callbacks)
    callbacks = callbacks or {}

    -- ── UIManager cooperative coroutine path (primary) ──────────────────────
    local temp_file = cache_file .. ".tmp"
    local ok_ui, UIManager = pcall(require, "ui/uimanager")
    if ok_ui and UIManager then
        local f, open_err = io.open(temp_file, "w")
        if not f then
            logger.warn("CacheManager: Cannot open cache file for async write:", open_err or "unknown")
            for _, cb in ipairs(callbacks) do pcall(cb, false) end
            self:_triggerPendingSave(cache_file)
            return false
        end

        f:write("-- X-Ray Cache v" .. CURRENT_CACHE_VERSION .. "\n")
        f:write("-- Generated: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n\n")
        f:write("return ")

        self._active_saves = self._active_saves or {}
        local save_entry = {
            cancelled = false,
            file = f,
            path = temp_file,
            cache_file = cache_file,
            book_path = book_path,
            data = data,
            callbacks = callbacks
        }
        table.insert(self._active_saves, save_entry)
        CacheManager._active_by_file[cache_file] = save_entry

        local function cleanupSave()
            if self._active_saves then
                for idx, entry in ipairs(self._active_saves) do
                    if entry == save_entry then
                        table.remove(self._active_saves, idx)
                        break
                    end
                end
            end
            if CacheManager._active_by_file[cache_file] == save_entry then
                CacheManager._active_by_file[cache_file] = nil
            end
        end

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
                    if type(v) ~= "function" and type(v) ~= "userdata" and type(v) ~= "thread" and (type(k) ~= "string" or k:sub(1, 1) ~= "_") then
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
                        if write_count >= 100 then
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
            if save_entry.cancelled then
                pcall(function() f:close() end)
                pcall(os.remove, temp_file)
                cleanupSave()
                for _, cb in ipairs(save_entry.callbacks) do pcall(cb, false) end
                self:_triggerPendingSave(cache_file)
                return
            end

            local ok, err = coroutine.resume(co)
            if not ok then
                logger.warn("CacheManager: Error during async serialization:", err or "unknown")
                pcall(function() f:close() end)
                pcall(os.remove, temp_file)
                cleanupSave()
                for _, cb in ipairs(save_entry.callbacks) do pcall(cb, false) end
                self:_triggerPendingSave(cache_file)
                return
            end

            if coroutine.status(co) == "dead" then
                pcall(function() f:close() end)
                local ren_ok, ren_err = atomicRename(temp_file, cache_file)
                cleanupSave()
                if not ren_ok then
                    logger.warn("CacheManager: Failed to rename temp file to cache file:", ren_err or "unknown")
                    AIHelper:log("CacheManager: Failed to rename temp file: " .. tostring(ren_err or "unknown"))
                    pcall(os.remove, temp_file)
                    for _, cb in ipairs(save_entry.callbacks) do pcall(cb, false) end
                else
                    logger.info("CacheManager: Saved cache asynchronously (cooperative) to:", cache_file)
                    AIHelper:log("CacheManager: Saved cache asynchronously (cooperative) to: " .. tostring(cache_file))
                    for _, cb in ipairs(save_entry.callbacks) do pcall(cb, true) end
                end
                self:_triggerPendingSave(cache_file)
            else
                if not save_entry.cancelled then
                    UIManager:scheduleIn(0.05, resumeCoroutine)
                else
                    pcall(function() f:close() end)
                    pcall(os.remove, temp_file)
                    cleanupSave()
                    for _, cb in ipairs(save_entry.callbacks) do pcall(cb, false) end
                    self:_triggerPendingSave(cache_file)
                end
            end
        end

        UIManager:scheduleIn(0.05, resumeCoroutine)
        logger.info("CacheManager: Started cooperative async save to:", cache_file)
        return true
    end

    -- ── Fork-based fallback (rarely reached in practice) ─────────────────────
    local ok_ffi, ffiutil = pcall(require, "ffi/util")
    if not ok_ffi then
        ok_ffi, ffiutil = pcall(require, "ffiutil")
    end

    local function child_logic(pid, write_fd)
        local header = "-- X-Ray Cache v" .. CURRENT_CACHE_VERSION .. "\n-- Generated: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n\nreturn "
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
            for _, cb in ipairs(callbacks) do pcall(cb, true) end
            self:_triggerPendingSave(cache_file)
            return true
        end
    end

    -- ── Final fallback: synchronous ───────────────────────────────────────────
    logger.info("CacheManager: Async save unavailable, using synchronous save")
    local success = self:saveCache(book_path, data)
    for _, cb in ipairs(callbacks) do pcall(cb, success) end
    self:_triggerPendingSave(cache_file)
    return success
end


-- Load book data from an external JSON cache file (read-only)
function CacheManager:loadJsonCache(json_file)
    if not json_file then return nil end

    local max_bytes = self.MAX_JSON_CACHE_BYTES or MAX_JSON_CACHE_BYTES
    if lfs then
        local attr = lfs.attributes(json_file)
        if not attr or attr.mode ~= "file" then
            return nil
        end
        if attr.size and attr.size > max_bytes then
            logger.warn("CacheManager: JSON cache exceeds size limit, ignoring:", json_file, attr.size)
            AIHelper:log("CacheManager: JSON cache exceeds size limit (" .. tostring(attr.size) .. " bytes)")
            return nil
        end
    end

    local f = io.open(json_file, "r")
    if not f then
        return nil
    end
    local raw = f:read("*all")
    f:close()

    if not raw or raw == "" then
        return nil
    end
    if #raw > max_bytes then
        raw = nil
        logger.warn("CacheManager: JSON cache exceeds size limit, ignoring:", json_file)
        return nil
    end

    local json = getJsonModule()
    if not json then
        raw = nil
        logger.warn("CacheManager: No JSON decoder available to load:", json_file)
        return nil
    end

    local ok_dec, data = pcall(json.decode, raw)
    raw = nil -- Release raw buffer immediately for low-RAM devices

    if not ok_dec or type(data) ~= "table" then
        logger.warn("CacheManager: Failed to decode JSON cache:", tostring(data or "unknown error"))
        AIHelper:log("CacheManager: Failed to decode JSON cache: " .. tostring(data or "unknown error"))
        return nil
    end

    local valid_schema = data.schema_version ~= nil and SUPPORTED_SCHEMA_VERSIONS[tostring(data.schema_version)]
    local valid_cache = data.cache_version ~= nil and SUPPORTED_CACHE_VERSIONS[tostring(data.cache_version)]
    if not valid_schema and not valid_cache then
        logger.warn("CacheManager: JSON cache version mismatch, ignoring")
        AIHelper:log("CacheManager: JSON cache version mismatch (schema_version=" .. tostring(data.schema_version) .. ", cache_version=" .. tostring(data.cache_version) .. ")")
        return nil
    end

    data.cache_version = data.cache_version or CURRENT_CACHE_VERSION

    -- Normalize expected entity lists and default imported entries to source="external"
    local list_keys = { "characters", "locations", "terms", "historical_figures", "timeline" }
    for _, key in ipairs(list_keys) do
        if type(data[key]) ~= "table" then
            data[key] = {}
        else
            for _, entry in ipairs(data[key]) do
                if type(entry) == "table" and entry.source == nil then
                    entry.source = "external"
                end
            end
        end
    end

    data._loaded_from_json = true
    logger.info("CacheManager: Loaded JSON cache from:", json_file)
    AIHelper:log("CacheManager: Loaded JSON cache from " .. tostring(json_file))
    return data
end

-- Load book data from cache (supports both native xray_cache.lua and external xray_cache.json)
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
    local json_file = self:getJsonCachePath(book_path)

    local lua_exists, json_exists = false, false
    local lua_mtime, json_mtime = 0, 0

    if lfs then
        local lua_attr = lfs.attributes(cache_file)
        if lua_attr then
            lua_exists = true
            lua_mtime = tonumber(lua_attr.modification) or 0
        end
        if json_file then
            local json_attr = lfs.attributes(json_file)
            if json_attr then
                json_exists = true
                json_mtime = tonumber(json_attr.modification) or 0
            end
        end
    else
        local f_lua = io.open(cache_file, "r")
        if f_lua then
            f_lua:close()
            lua_exists = true
        end
        if json_file then
            local f_json = io.open(json_file, "r")
            if f_json then
                f_json:close()
                json_exists = true
            end
        end
    end

    if not lua_exists and not json_exists then
        logger.info("CacheManager: No cache file found")
        AIHelper:log("CacheManager: No cache file found for " .. tostring(book_path))
        return nil
    end

    -- Prefer xray_cache.json when xray_cache.lua is absent or JSON has a newer modification time
    if json_exists and (not lua_exists or json_mtime > lua_mtime) then
        local json_data = self:loadJsonCache(json_file)
        if json_data then
            return json_data
        end
        if not lua_exists then
            return nil
        end
    end

    -- Load native Lua cache
    local success, data = pcall(function()
        return dofile(cache_file)
    end)

    if not success or not data or type(data) ~= "table" then
        logger.warn("CacheManager: Failed to load cache:", tostring(data or "unknown error"))
        AIHelper:log("CacheManager: Failed to load cache: " .. tostring(data or "unknown error"))
        if json_exists then
            return self:loadJsonCache(json_file)
        end
        return nil
    end

    -- Check cache version (support current 6.1 and legacy 6.0)
    if not SUPPORTED_CACHE_VERSIONS[data.cache_version] then
        logger.warn("CacheManager: Cache version mismatch, ignoring")
        AIHelper:log("CacheManager: Cache version mismatch (found " .. tostring(data.cache_version) .. ", expected 6.0 or 6.1)")
        if json_exists then
            return self:loadJsonCache(json_file)
        end
        return nil
    end

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
            if type(v) ~= "function" and type(v) ~= "userdata" and type(v) ~= "thread" and (type(k) ~= "string" or k:sub(1, 1) ~= "_") then
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
            if type(v) ~= "function" and type(v) ~= "userdata" and type(v) ~= "thread" and (type(k) ~= "string" or k:sub(1, 1) ~= "_") then
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

-- Clear cache for a book (removes both native xray_cache.lua and external xray_cache.json)
function CacheManager:clearCache(book_path)
    local removed_any = false
    local cache_file = self:getCachePath(book_path)
    if cache_file then
        local success, err = os.remove(cache_file)
        if success then
            logger.info("CacheManager: Cleared cache:", cache_file)
            removed_any = true
        else
            logger.warn("CacheManager: Failed to clear cache:", err or "unknown")
        end
    end
    local json_file = self:getJsonCachePath(book_path)
    if json_file then
        local ok_j = os.remove(json_file)
        if ok_j then
            logger.info("CacheManager: Cleared JSON cache:", json_file)
            removed_any = true
        end
    end
    return removed_any
end

return CacheManager