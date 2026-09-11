-- xray_seriesmanager.lua - STANDALONE series-specific logic for KOReader X-Ray
local ok, lfs = pcall(require, "libs/libkoreader-lfs")
if not ok or type(lfs) ~= "table" then
    ok, lfs = pcall(require, "lfs")
end
if not ok or type(lfs) ~= "table" then
    lfs = nil
end
local logger = require("logger")
local DataStorage = require("datastorage")

local SeriesManager = {}

function SeriesManager:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    pcall(function() o:migrateLegacySeriesCache() end)
    return o
end

function SeriesManager:makeSlug(name)
    if not name then return "" end
    -- Lowercase and replace non-alphanumeric characters with underscores
    local slug = name:lower():gsub("[%s%p]+", "_")
    -- Strip leading/trailing underscores
    slug = slug:gsub("^_+", ""):gsub("_+$", "")
    return slug
end

local function makeSlug(name)
    return SeriesManager:makeSlug(name)
end

local WORD_NUMBERS = {
    one = 1, two = 2, three = 3, four = 4, five = 5,
    six = 6, seven = 7, eight = 8, nine = 9, ten = 10,
    eleven = 11, twelve = 12, thirteen = 13, fourteen = 14, fifteen = 15,
    sixteen = 16, seventeen = 17, eighteen = 18, nineteen = 19, twenty = 20,
    first = 1, second = 2, third = 3, fourth = 4, fifth = 5,
    sixth = 6, seventh = 7, eighth = 8, ninth = 9, tenth = 10
}

local ROMAN_MAP = {
    i = 1, ii = 2, iii = 3, iv = 4, v = 5,
    vi = 6, vii = 7, viii = 8, ix = 9, x = 10,
    xi = 11, xii = 12, xiii = 13, xiv = 14, xv = 15,
    xvi = 16, xvii = 17, xviii = 18, xix = 19, xx = 20
}

-- Extract series book index from title string
function SeriesManager:extractIndexFromTitle(title, series_name)
    if not title or title == "" then return nil end
    local lower_title = title:lower()

    -- 1. Try matching series_name followed by index if series_name is known
    if series_name and series_name ~= "" then
        local s_clean = series_name:lower():gsub("[%-%^%$%(%)%%%.%[%]%*%+%?]", "%%%1")
        local s_idx = lower_title:match(s_clean .. "%s*[,:%-]?%s*#?%s*0*(%d+)")
        if s_idx and tonumber(s_idx) then
            return tonumber(s_idx)
        end
    end

    -- 2. Explicit numeric patterns
    local patterns = {
        "book%s*0*(%d+)",
        "volume%s*0*(%d+)",
        "vol%s*%.?%s*0*(%d+)",
        "bk%s*%.?%s*0*(%d+)",
        "part%s*0*(%d+)",
        "no%s*%.?%s*0*(%d+)",
        "nr%s*%.?%s*0*(%d+)",
        "#%s*0*(%d+)",
    }
    for _, pat in ipairs(patterns) do
        local match = lower_title:match(pat)
        if match and tonumber(match) then
            return tonumber(match)
        end
    end

    -- 3. Word numbers and Roman numerals
    local word_patterns = {
        "book%s+([%a]+)",
        "volume%s+([%a]+)",
        "vol%s*%.?%s+([%a]+)",
        "part%s+([%a]+)",
        "bk%s*%.?%s+([%a]+)",
    }
    for _, pat in ipairs(word_patterns) do
        local match = lower_title:match(pat)
        if match then
            if WORD_NUMBERS[match] then
                return WORD_NUMBERS[match]
            end
            if ROMAN_MAP[match] then
                return ROMAN_MAP[match]
            end
        end
    end

    return nil
end

-- Detect if book is part of a series
function SeriesManager:detectSeries(props, title, author, ai_helper)
    props = props or {}
    local series_name = props.series or props.Series
    local series_index = props.series_index or props.seriesindex or props.SeriesIndex
    
    logger.info("XRayPlugin: Series: detectSeries: title=" .. tostring(title) .. ", author=" .. tostring(author))
    logger.info("XRayPlugin: Series: detectSeries: Metadata check - props.series=" .. tostring(series_name) .. ", props.series_index=" .. tostring(series_index))

    -- 1. Try metadata first
    if series_name and series_name ~= "" then
        local index = tonumber(series_index)
        local index_source = index and "metadata" or nil
        if not index then
            -- Fallback 1a: Try title parsing
            index = self:extractIndexFromTitle(title, series_name)
            if index then
                index_source = "title_parse"
                logger.info("XRayPlugin: Series: detectSeries: Metadata index missing, extracted from title. index=" .. tostring(index))
            end
        end

        if not index and ai_helper then
            -- Fallback 1b: Try AI detection for index
            logger.info("XRayPlugin: Series: detectSeries: Metadata index missing and title parse yielded no index. Querying AI for book index.")
            local prompt = ai_helper:createPrompt(title, author, nil, "series_detect")
            local result, err_code, err_msg = ai_helper:executeUnifiedRequest(prompt)
            if result and result.is_series and result.book_index then
                index = tonumber(result.book_index)
                if index then
                    index_source = "ai_detect"
                    logger.info("XRayPlugin: Series: detectSeries: AI resolved book index=" .. tostring(index))
                end
            else
                logger.info("XRayPlugin: Series: detectSeries: AI call for index failed: err_code=" .. tostring(err_code) .. ", err_msg=" .. tostring(err_msg))
            end
        end

        local has_explicit_index = (index_source ~= nil)
        index = index or 1
        index_source = index_source or "default"
        logger.info("XRayPlugin: Series: detectSeries: Series detected (" .. index_source .. "). Name=" .. tostring(series_name) .. ", index=" .. tostring(index))
        return {
            name = series_name,
            index = index,
            slug = makeSlug(series_name),
            has_explicit_index = has_explicit_index
        }
    end
    
    -- 2. Fallback to AI (when series_name itself is missing from metadata)
    if not ai_helper then
        logger.info("XRayPlugin: Series: detectSeries: Metadata fallback to AI skipped because ai_helper is nil")
        return nil
    end
    
    logger.info("XRayPlugin: Series: detectSeries: Metadata fallback to AI starting. Sending detection prompt.")
    local prompt = ai_helper:createPrompt(title, author, nil, "series_detect")
    local result, err_code, err_msg = ai_helper:executeUnifiedRequest(prompt)
    if result and result.is_series then
        local name = result.series_name
        local index = tonumber(result.book_index)
        if not index then
            index = self:extractIndexFromTitle(title, name)
        end
        index = index or 1
        logger.info("XRayPlugin: Series: detectSeries: AI returned: is_series=" .. tostring(result.is_series) .. ", series_name=" .. tostring(name) .. ", book_index=" .. tostring(index))
        if name and name ~= "" then
            return {
                name = name,
                index = index,
                slug = makeSlug(name)
            }
        end
    else
        logger.info("XRayPlugin: Series: detectSeries: AI call failed or not a series. err_code=" .. tostring(err_code) .. ", err_msg=" .. tostring(err_msg))
    end
    
    logger.info("XRayPlugin: Series: detectSeries: Not part of a series.")
    return nil
end

-- Get list of prior books in the series
function SeriesManager:getPriorBookList(series_info, author, ai_helper)
    if not series_info or not series_info.name or not series_info.index or series_info.index <= 1 then
        logger.info("XRayPlugin: Series: getPriorBookList: invalid series_info or index <= 1, returning empty list")
        return {}
    end
    
    logger.info("XRayPlugin: Series: getPriorBookList starting for: " .. tostring(series_info.name) .. ", index=" .. tostring(series_info.index))

    if ai_helper then
        logger.info("XRayPlugin: Series: getPriorBookList: Sending AI prior book list prompt.")
        local context = {
            series_name = series_info.name,
            index = series_info.index
        }
        local prompt = ai_helper:createPrompt(nil, author, context, "prior_book_list")
        local result, err_code, err_msg = ai_helper:executeUnifiedRequest(prompt)
        if result and result.prior_books then
            logger.info("XRayPlugin: Series: getPriorBookList: AI returned " .. tostring(#result.prior_books) .. " prior books.")
            return result.prior_books
        else
            logger.info("XRayPlugin: Series: getPriorBookList: AI call failed or returned no list (err_code=" .. tostring(err_code) .. ", err_msg=" .. tostring(err_msg) .. "). Using local fallback.")
        end
    else
        logger.info("XRayPlugin: Series: getPriorBookList: ai_helper is nil, skipping AI prompt and using local fallback.")
    end
    
    -- Minimal local fallback if AI fails/is missing: generate placeholders
    logger.info("XRayPlugin: Series: getPriorBookList: Generating local fallback list of " .. tostring(series_info.index - 1) .. " placeholder books.")
    local fallback_list = {}
    for i = 1, series_info.index - 1 do
        table.insert(fallback_list, {
            index = i,
            title = string.format("%s (Book %d)", series_info.name, i),
            author = author or "Unknown Author"
        })
    end
    return fallback_list
end

-- Cache path for a series slug
function SeriesManager:getSeriesCachePath(slug)
    if not slug or slug == "" then return nil end
    return DataStorage:getSettingsDir() .. "/xray/series/" .. slug .. ".lua"
end

-- Ensure directory path exists
function SeriesManager:ensureDirectory(path)
    if not lfs then return true end
    local dir = path:match("(.+)/[^/]+$")
    if not dir then return false end
    
    local attr = lfs and lfs.attributes(dir)
    if attr and attr.mode == "directory" then
        return true
    end
    
    -- Use recursive mkdir (os.execute) so parent dirs are created too
    logger.info("SeriesManager: Creating directory:", dir)
    local escaped = dir:gsub("'", "'\\''")
    local rc = os.execute("mkdir -p '" .. escaped .. "'")
    if rc == 0 or rc == true then
        return true
    end

    -- Fallback: try lfs.mkdir (non-recursive, may fail if parent missing)
    if lfs then
        local success, err = lfs.mkdir(dir)
        if success then return true end
        logger.warn("SeriesManager: Failed to create directory:", err or "unknown error")
    end
    return false
end

-- Save series context to global cache
function SeriesManager:saveSeriesCache(slug, data)
    if not slug or not data then
        return false
    end
    
    local cache_file = self:getSeriesCachePath(slug)
    if not cache_file then return false end
    
    if not self:ensureDirectory(cache_file) then
        return false
    end
    
    data.cached_at = os.time()
    data.cache_version = "6.0"
    
    local success, err = pcall(function()
        local f, open_err = io.open(cache_file, "w")
        if not f then
            logger.warn("SeriesManager: Cannot open file for writing:", cache_file)
            return false
        end
        
        f:write("-- X-Ray Series Cache v6.0\n")
        f:write("return ")
        self:serializeToFile(f, data, "")
        f:write("\n")
        f:close()
        logger.info("SeriesManager: Saved series cache to:", cache_file)
        return true
    end)
    
    return success
end

-- Load series context from global cache
function SeriesManager:loadSeriesCache(slug)
    if not slug or slug == "" then return nil end
    local cache_file = self:getSeriesCachePath(slug)
    if not cache_file then return nil end
    
    if lfs then
        local attr = lfs.attributes(cache_file)
        if not attr then return nil end
    else
        local f = io.open(cache_file, "r")
        if f then f:close() else return nil end
    end
    
    local success, data = pcall(dofile, cache_file)
    if success and type(data) == "table" and data.cache_version == "6.0" then
        return data
    end
    return nil
end

-- Resolve series information from book_data or document metadata
function SeriesManager:getSeriesInfo(book_data, props, title, author)
    -- 1. Check book_data if already populated with a valid series slug
    if book_data and book_data.series_slug and book_data.series_slug ~= "" and book_data.series_slug ~= "series" then
        return {
            name = book_data.series or book_data.series_slug,
            slug = book_data.series_slug,
            index = tonumber(book_data.series_index) or 1,
            has_explicit_index = book_data.series_index ~= nil,
        }
    end

    -- 2. Detect series from document props, title, and author (metadata check only, no AI)
    local detected = self:detectSeries(props, title, author, nil)
    if detected and detected.slug and detected.slug ~= "" and detected.slug ~= "series" then
        return detected
    end

    return nil
end

-- Migrate any images trapped in legacy 'series.lua' to their proper series cache
function SeriesManager:migrateLegacySeriesCache()
    local legacy_file = self:getSeriesCachePath("series")
    if not legacy_file then return end

    if lfs then
        local attr = lfs.attributes(legacy_file)
        if not attr then return end
    else
        local f = io.open(legacy_file, "r")
        if f then f:close() else return end
    end

    local success, legacy_data = pcall(dofile, legacy_file)
    if success and type(legacy_data) == "table" and legacy_data.images and #legacy_data.images > 0 then
        for _, img in ipairs(legacy_data.images) do
            local target_slug = nil
            local path_str = tostring(img.cached_file or ""):lower()
            if path_str:find("hobbit") or path_str:find("tolkien") or path_str:find("middle") then
                target_slug = "middle_earth"
            elseif path_str:find("cormoran") or path_str:find("strike") then
                target_slug = "cormoran_strike"
            elseif img.source_book_title and img.source_book_title ~= "Book" then
                target_slug = self:makeSlug(img.source_book_title)
            end

            if target_slug and target_slug ~= "series" then
                self:saveSeriesImage(target_slug, img)
                logger.info("SeriesManager: Migrated image '" .. tostring(img.title) .. "' from series.lua to " .. target_slug)
            end
        end
    end

    pcall(function() os.remove(legacy_file) end)
end

-- Save a map / diagram to series-level cache
function SeriesManager:saveSeriesImage(slug, image_data)
    if not slug or slug == "" or slug == "series" or not image_data then return false end
    local data = self:loadSeriesCache(slug) or {
        series_slug = slug,
        images = {},
    }
    data.images = data.images or {}
    
    -- Check if image already exists in series (update or insert)
    local found = false
    local img_id = image_data.id or image_data.href
    for i, existing in ipairs(data.images) do
        local same_id = img_id and existing.id and (existing.id == img_id)
        local same_href = image_data.href and existing.href and (existing.href == image_data.href)
        if same_id or same_href then
            data.images[i] = image_data
            found = true
            break
        end
    end
    if not found then
        table.insert(data.images, image_data)
    end
    
    return self:saveSeriesCache(slug, data)
end

-- Retrieve series-level images up to max_book_index to avoid future book spoilers
function SeriesManager:getSeriesImages(slug, max_book_index)
    if not slug or slug == "" or slug == "series" then
        return {}
    end

    local results = {}
    local seen = {}

    local function addImages(data, enforce_filter)
        if not data or not data.images then return end
        for _, img in ipairs(data.images) do
            local uid = img.id or img.href or (img.title and (img.title .. tostring(img.page)))
            if uid and not seen[uid] then
                local b_idx = tonumber(img.source_book_index) or 1
                if not enforce_filter or not max_book_index or b_idx <= tonumber(max_book_index) then
                    seen[uid] = true
                    table.insert(results, img)
                end
            end
        end
    end

    -- Load primary series cache ONLY for the specified series slug
    local data = self:loadSeriesCache(slug)
    if data then
        addImages(data, true)
    end

    return results
end

-- Remove a map / diagram from series cache
function SeriesManager:removeSeriesImage(slug, image_id)
    if not slug or slug == "" or slug == "series" or not image_id then return false end
    local data = self:loadSeriesCache(slug)
    if not data or not data.images then return false end
    
    for i, img in ipairs(data.images) do
        if img.id == image_id then
            table.remove(data.images, i)
            return self:saveSeriesCache(slug, data)
        end
    end
    return false
end

local function filterCurrentOnly(tbl)
    local res = {}
    for _, item in ipairs(tbl or {}) do
        if item and item.source ~= "series_prior" then
            table.insert(res, item)
        end
    end
    return res
end

-- Synchronize clean book data into SeriesCache for a specific book index
function SeriesManager:syncBookToSeriesCache(slug, index, book_data, book_path)
    if not slug or slug == "" or slug == "series" or not index or not book_data then
        return false
    end
    index = tonumber(index)
    if not index then return false end

    local cache_data = self:loadSeriesCache(slug) or {
        series_slug = slug,
        books = {},
        book_paths = {},
    }
    cache_data.books = cache_data.books or {}
    cache_data.book_paths = cache_data.book_paths or {}

    local title = book_data.title or book_data.book_title
    local author = book_data.author or book_data.book_author or book_data.authors

    cache_data.books[index] = {
        title = title,
        author = author,
        characters = filterCurrentOnly(book_data.characters),
        locations = filterCurrentOnly(book_data.locations),
        terms = filterCurrentOnly(book_data.terms),
        timeline = filterCurrentOnly(book_data.timeline),
        source = "local_xray",
    }
    if book_path and book_path ~= "" then
        for other_idx, other_path in pairs(cache_data.book_paths) do
            if tonumber(other_idx) ~= index and other_path == book_path then
                cache_data.book_paths[other_idx] = nil
                cache_data.books[other_idx] = nil
            end
        end
        cache_data.book_paths[index] = book_path
    end

    if title and title ~= "" then
        for other_idx, other_book in pairs(cache_data.books) do
            if tonumber(other_idx) ~= index and other_book and other_book.title and other_book.title:lower() == title:lower() then
                cache_data.book_paths[other_idx] = nil
                cache_data.books[other_idx] = nil
            end
        end
    end

    logger.info("SeriesManager: Synced Book " .. tostring(index) .. " to series cache for slug '" .. tostring(slug) .. "'")
    return self:saveSeriesCache(slug, cache_data)
end

-- Safely read a Lua cache file returning a table or nil
local function safeLoadCacheFile(file_path)
    if not file_path then return nil end
    local f = io.open(file_path, "r")
    if not f then return nil end
    f:close()
    local success, data = pcall(dofile, file_path)
    if success and type(data) == "table" then
        return data
    end
    return nil
end

-- Search local device storage for previous book X-Ray data
function SeriesManager:findLocalBookXRay(series_info, target_index, current_book_path, target_title, cache_manager)
    if not series_info or not series_info.slug or not target_index then
        return nil
    end
    target_index = tonumber(target_index)
    if not target_index then return nil end

    local slug = series_info.slug

    -- Priority 1: Check existing SeriesCache for an entry marked as local_xray
    local cache_data = self:loadSeriesCache(slug)
    if cache_data and cache_data.books and cache_data.books[target_index] then
        local entry = cache_data.books[target_index]
        if entry.source == "local_xray" then
            logger.info("SeriesManager: Found local_xray entry in SeriesCache for book index " .. tostring(target_index))
            return entry
        end
    end

    -- Priority 2: Check tracked book paths from prior sessions
    if cache_data and cache_data.book_paths and cache_data.book_paths[target_index] then
        local tracked_path = cache_data.book_paths[target_index]
        local loaded = nil
        if cache_manager and cache_manager.loadCache then
            loaded = cache_manager:loadCache(tracked_path)
        end
        if not loaded then
            local sdr_file = tracked_path:gsub("[/\\][^/\\]+$", "") .. "/" .. tracked_path:match("([^/\\]+)$") .. ".sdr/xray_cache.lua"
            loaded = safeLoadCacheFile(sdr_file)
        end
        if loaded and (loaded.characters or loaded.timeline) then
            self:syncBookToSeriesCache(slug, target_index, loaded, tracked_path)
            local updated = self:loadSeriesCache(slug)
            return updated and updated.books and updated.books[target_index]
        end
    end

    if not current_book_path or current_book_path == "" then
        return nil
    end

    local sep = current_book_path:find("\\") and "\\" or "/"
    local current_dir = current_book_path:match("^(.*)[/\\][^/\\]+$")
    if not current_dir then return nil end

    local function checkCandidateData(loaded, candidate_name, candidate_file)
        if not loaded or type(loaded) ~= "table" then return false end
        -- Verify series slug
        local c_slug = loaded.series_slug
        local c_name = loaded.series or loaded.series_name or (loaded.props and (loaded.props.series or loaded.props.Series))
        local slug_matches = false
        if c_slug and c_slug ~= "" and c_slug == slug then
            slug_matches = true
        elseif c_name and c_name ~= "" and makeSlug(c_name) == slug then
            slug_matches = true
        end
        if not slug_matches then return false end

        -- Verify book index
        local c_idx = tonumber(loaded.series_index or (loaded.props and (loaded.props.series_index or loaded.props.seriesindex or loaded.props.SeriesIndex)))
        if not c_idx and (loaded.title or loaded.book_title) then
            c_idx = self:extractIndexFromTitle(loaded.title or loaded.book_title, series_info.name)
        end
        if not c_idx and candidate_name then
            c_idx = self:extractIndexFromTitle(candidate_name, series_info.name)
        end

        local index_matches = (c_idx == target_index)
        if not index_matches and target_title and target_title ~= "" then
            local t = loaded.title or loaded.book_title
            if t and t:lower():find(target_title:lower(), 1, true) then
                index_matches = true
            end
        end

        if index_matches and ((loaded.characters and #loaded.characters > 0) or (loaded.timeline and #loaded.timeline > 0)) then
            logger.info("SeriesManager: Discovered local X-Ray cache for Book " .. tostring(target_index) .. " at: " .. tostring(candidate_file))
            self:syncBookToSeriesCache(slug, target_index, loaded, candidate_file)
            local updated = self:loadSeriesCache(slug)
            return updated and updated.books and updated.books[target_index]
        end
        return nil
    end

    -- Priority 3: Scan current_dir for matching .sdr directories and ebook sidecars
    if lfs and lfs.dir then
        local pcall_ok = pcall(function()
            for entry in lfs.dir(current_dir) do
                if entry ~= "." and entry ~= ".." then
                    local entry_path = current_dir .. sep .. entry
                    local matched = nil
                    if entry:match("%.sdr$") then
                        local cache_file = entry_path .. sep .. "xray_cache.lua"
                        local loaded = safeLoadCacheFile(cache_file)
                        matched = checkCandidateData(loaded, entry, entry_path:gsub("%.sdr$", ""))
                    elseif entry:match("%.epub$") or entry:match("%.kepub%.epub$") or entry:match("%.mobi$") or entry:match("%.azw3$") or entry:match("%.fb2$") or entry:match("%.pdf$") then
                        if entry_path ~= current_book_path then
                            local cache_file = entry_path .. ".sdr" .. sep .. "xray_cache.lua"
                            local loaded = safeLoadCacheFile(cache_file)
                            matched = checkCandidateData(loaded, entry, entry_path)
                        end
                    end
                    if matched then
                        return matched
                    end
                end
            end
        end)
        -- Reload series cache in case matched in loop
        local refreshed = self:loadSeriesCache(slug)
        if refreshed and refreshed.books and refreshed.books[target_index] and refreshed.books[target_index].source == "local_xray" then
            return refreshed.books[target_index]
        end

        -- Priority 4: Scan sibling directories in parent directory (Calibre author folder structure)
        local parent_dir = current_dir:match("^(.*)[/\\][^/\\]+$")
        if parent_dir and parent_dir ~= "" then
            pcall(function()
                local dir_count = 0
                for sub in lfs.dir(parent_dir) do
                    if sub ~= "." and sub ~= ".." then
                        dir_count = dir_count + 1
                        if dir_count > 50 then break end -- Limit scan to keep fast
                        local sub_path = parent_dir .. sep .. sub
                        if sub_path ~= current_dir then
                            local attr = lfs.attributes and lfs.attributes(sub_path)
                            if attr and attr.mode == "directory" then
                                for sub_entry in lfs.dir(sub_path) do
                                    if sub_entry ~= "." and sub_entry ~= ".." then
                                        local sub_entry_path = sub_path .. sep .. sub_entry
                                        local matched = nil
                                        if sub_entry:match("%.sdr$") then
                                            local cache_file = sub_entry_path .. sep .. "xray_cache.lua"
                                            local loaded = safeLoadCacheFile(cache_file)
                                            matched = checkCandidateData(loaded, sub_entry, sub_entry_path:gsub("%.sdr$", ""))
                                        elseif sub_entry:match("%.epub$") or sub_entry:match("%.kepub%.epub$") or sub_entry:match("%.mobi$") or sub_entry:match("%.azw3$") or sub_entry:match("%.fb2$") or sub_entry:match("%.pdf$") then
                                            local cache_file = sub_entry_path .. ".sdr" .. sep .. "xray_cache.lua"
                                            local loaded = safeLoadCacheFile(cache_file)
                                            matched = checkCandidateData(loaded, sub_entry, sub_entry_path)
                                        end
                                        if matched then
                                            return matched
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end)
            local refreshed_p = self:loadSeriesCache(slug)
            if refreshed_p and refreshed_p.books and refreshed_p.books[target_index] and refreshed_p.books[target_index].source == "local_xray" then
                return refreshed_p.books[target_index]
            end
        end
    end

    return nil
end

-- Stream-serialize to file
function SeriesManager:serializeToFile(f, obj, indent, seen)
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

return SeriesManager
