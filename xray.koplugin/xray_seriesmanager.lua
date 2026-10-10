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
        local has_explicit_index = (index ~= nil)
        index = index or 1
        logger.info("XRayPlugin: Series: detectSeries: AI returned: is_series=" .. tostring(result.is_series) .. ", series_name=" .. tostring(name) .. ", book_index=" .. tostring(index))
        if name and name ~= "" then
            return {
                name = name,
                index = index,
                slug = makeSlug(name),
                has_explicit_index = has_explicit_index
            }
        end
    else
        logger.info("XRayPlugin: Series: detectSeries: AI call failed or not a series. err_code=" .. tostring(err_code) .. ", err_msg=" .. tostring(err_msg))
    end
    
    logger.info("XRayPlugin: Series: detectSeries: Not part of a series.")
    return nil
end

-- Series indices are not always whole numbers: novellas and split volumes are
-- commonly numbered 1.5, 2.5, 5.33, etc. Prior books are therefore tracked by
-- their actual index values instead of by counting 1..index-1.

-- Format an index for display/prompts: 3 -> "3", 2.5 -> "2.5"
function SeriesManager.formatIndex(index)
    local n = tonumber(index)
    if not n then return tostring(index) end
    if n == math.floor(n) then return string.format("%d", n) end
    return tostring(n)
end

-- Whole-numbered books that must precede `index` (4 -> {1,2,3}, 2.5 -> {1,2})
function SeriesManager.wholeIndicesBefore(index)
    local list = {}
    local n = tonumber(index) or 1
    for i = 1, math.ceil(n) - 1 do
        table.insert(list, i)
    end
    return list
end

-- Sorted numeric keys of `books` (a SeriesCache books table) that precede `index`
function SeriesManager.priorIndicesIn(books, index)
    local list = {}
    local n = tonumber(index)
    if not n or type(books) ~= "table" then return list end
    for k in pairs(books) do
        if type(k) == "number" and k < n then
            table.insert(list, k)
        end
    end
    table.sort(list)
    return list
end

-- Books on the device whose metadata places them before the current book in this series
function SeriesManager:findLocalPriorBooks(series_info, current_book_path)
    local list = {}
    if not current_book_path or current_book_path == "" or not series_info or not series_info.slug then
        return list
    end
    for _, b in ipairs(self:scanFolderForEpubs(current_book_path)) do
        if b.path ~= current_book_path and b.series and b.series_index
                and makeSlug(b.series) == series_info.slug and b.series_index < series_info.index then
            table.insert(list, { index = b.series_index, title = b.title, author = b.author, path = b.path })
        end
    end
    return list
end

-- Indices to check for prior books: every whole-numbered book before the
-- current one, plus fractional entries already in the SeriesCache (`books`)
-- or found on the device.
function SeriesManager:getExpectedPriorIndices(series_info, books, current_book_path)
    local seen, list = {}, {}
    local function add(i)
        if not seen[i] then
            seen[i] = true
            table.insert(list, i)
        end
    end
    for _, i in ipairs(SeriesManager.wholeIndicesBefore(series_info.index)) do add(i) end
    for _, i in ipairs(SeriesManager.priorIndicesIn(books, series_info.index)) do add(i) end
    for _, b in ipairs(self:findLocalPriorBooks(series_info, current_book_path)) do add(b.index) end
    table.sort(list)
    return list
end

-- Get list of prior books in the series
function SeriesManager:getPriorBookList(series_info, author, ai_helper, current_book_path)
    if not series_info or not series_info.name or not series_info.index or series_info.index <= 1 then
        logger.info("XRayPlugin: Series: getPriorBookList: invalid series_info or index <= 1, returning empty list")
        return {}
    end
    
    logger.info("XRayPlugin: Series: getPriorBookList starting for: " .. tostring(series_info.name) .. ", index=" .. tostring(series_info.index))

    -- Collect prior books keyed by index. Books found on the device take
    -- precedence, since their indices come from the user's own metadata; AI
    -- results fill in the rest. Entries at or after the current index, and
    -- titles already listed under another index, are dropped.
    local by_index, seen_titles = {}, {}
    local function addBook(book)
        local idx = book and tonumber(book.index)
        if not idx or idx >= series_info.index or by_index[idx] then return end
        local title_slug = book.title and makeSlug(book.title)
        if title_slug and title_slug ~= "" then
            if seen_titles[title_slug] then return end
            seen_titles[title_slug] = true
        end
        by_index[idx] = { index = idx, title = book.title, author = book.author or author, path = book.path }
    end

    local local_books = self:findLocalPriorBooks(series_info, current_book_path)
    for _, b in ipairs(local_books) do addBook(b) end
    if #local_books > 0 then
        logger.info("XRayPlugin: Series: getPriorBookList: Found " .. tostring(#local_books) .. " prior books on device.")
    end

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
            for _, b in ipairs(result.prior_books) do addBook(b) end
        else
            logger.info("XRayPlugin: Series: getPriorBookList: AI call failed or returned no list (err_code=" .. tostring(err_code) .. ", err_msg=" .. tostring(err_msg) .. ").")
        end
    else
        logger.info("XRayPlugin: Series: getPriorBookList: ai_helper is nil, skipping AI prompt.")
    end
    
    local list = {}
    for _, idx in ipairs(SeriesManager.priorIndicesIn(by_index, series_info.index)) do
        table.insert(list, by_index[idx])
    end
    if #list > 0 then
        return list
    end

    -- Minimal local fallback if nothing was found: generate placeholders
    local whole = SeriesManager.wholeIndicesBefore(series_info.index)
    logger.info("XRayPlugin: Series: getPriorBookList: Generating local fallback list of " .. tostring(#whole) .. " placeholder books.")
    local fallback_list = {}
    for _, i in ipairs(whole) do
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
    
    local temp_file = cache_file .. ".tmp"
    local success, result = pcall(function()
        local f, open_err = io.open(temp_file, "w")
        if not f then
            logger.warn("SeriesManager: Cannot open file for writing:", temp_file)
            return false
        end
        
        f:write("-- X-Ray Series Cache v6.0\n")
        f:write("return ")
        local ok2, write_err = pcall(function()
            self:serializeToFile(f, data, "")
        end)
        f:write("\n")
        f:close()

        if not ok2 then
            pcall(os.remove, temp_file)
            logger.warn("SeriesManager: Serialization error:", write_err or "unknown")
            return false
        end

        pcall(os.remove, cache_file)
        local ok_ren, ren_err = os.rename(temp_file, cache_file)
        if not ok_ren then
            pcall(os.remove, temp_file)
            logger.warn("SeriesManager: Failed to rename temp file to cache file:", ren_err or "unknown")
            return false
        end

        logger.info("SeriesManager: Saved series cache to:", cache_file)
        return true
    end)
    
    if not success or result ~= true then
        pcall(os.remove, temp_file)
        if not success then
            logger.warn("SeriesManager: Failed to save series cache:", result or "unknown error")
        end
        return false
    end

    return true
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
function SeriesManager:getSeriesInfo(book_data, props, title, author, ai_helper)
    -- 1. Check book_data if already populated with a valid series slug
    if book_data and book_data.series_slug and book_data.series_slug ~= "" and book_data.series_slug ~= "series" then
        local raw_index = tonumber(book_data.series_index)
        local has_explicit_index = (raw_index ~= nil)
        local index = raw_index
        local name = book_data.series

        if not index then
            local detected = self:detectSeries(props, title, author, ai_helper)
            if detected and detected.has_explicit_index then
                index = detected.index
                has_explicit_index = true
                name = name or detected.name
            else
                local meta_index = props and tonumber(props.series_index or props.seriesindex or props.SeriesIndex)
                if meta_index then
                    index = meta_index
                    has_explicit_index = true
                elseif title then
                    local title_idx = self:extractIndexFromTitle(title, name or book_data.series_slug)
                    if title_idx then
                        index = title_idx
                        has_explicit_index = true
                    end
                end
            end
            if has_explicit_index and index then
                book_data.series_index = index
            end
            if name and not book_data.series then
                book_data.series = name
            end
        end

        return {
            name = name or book_data.series or book_data.series_slug,
            slug = book_data.series_slug,
            index = index or 1,
            has_explicit_index = has_explicit_index,
        }
    end

    -- 2. Detect series from document props, title, and author (metadata check only, no AI unless ai_helper passed)
    local detected = self:detectSeries(props, title, author, ai_helper)
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

local function cleanItem(item, seen)
    if type(item) ~= "table" then return item end
    seen = seen or {}
    if seen[item] then return seen[item] end
    local clean = {}
    seen[item] = clean
    for k, v in pairs(item) do
        if type(k) ~= "string" or k:sub(1, 1) ~= "_" then
            if type(v) == "table" then
                clean[k] = cleanItem(v, seen)
            else
                clean[k] = v
            end
        end
    end
    return clean
end

local function filterCurrentOnly(tbl)
    local res = {}
    for _, item in ipairs(tbl or {}) do
        if item and item.source ~= "series_prior" then
            table.insert(res, cleanItem(item))
        end
    end
    return res
end

local function deepEqual(a, b, visited)
    if a == b then return true end
    local type_a = type(a)
    local type_b = type(b)
    if type_a ~= type_b then return false end
    if type_a ~= "table" then return false end

    visited = visited or {}
    if visited[a] and visited[a] == b then return true end
    visited[a] = b

    for k, v in pairs(a) do
        if type(k) ~= "string" or k:sub(1, 1) ~= "_" then
            if not deepEqual(v, b[k], visited) then
                return false
            end
        end
    end
    for k, _ in pairs(b) do
        if type(k) ~= "string" or k:sub(1, 1) ~= "_" then
            if a[k] == nil then
                return false
            end
        end
    end
    return true
end

-- Synchronize clean book data into SeriesCache for a specific book index
function SeriesManager:syncBookToSeriesCache(slug, index, book_data, book_path, is_explicit)
    if not slug or slug == "" or slug == "series" or not index or not book_data then
        return false
    end
    index = tonumber(index)
    if not index then return false end

    local loaded_cache = self:loadSeriesCache(slug)
    local is_new_cache = (loaded_cache == nil)
    local cache_data = loaded_cache or {
        series_slug = slug,
        books = {},
        book_paths = {},
    }
    cache_data.series_slug = cache_data.series_slug or slug
    cache_data.books = cache_data.books or {}
    cache_data.book_paths = cache_data.book_paths or {}

    local title = book_data.title or book_data.book_title
    local author = book_data.author or book_data.book_author or book_data.authors

    -- Guard when index is only an implicit/fallback default:
    if is_explicit == false then
        local existing_book = cache_data.books[index]
        local existing_path = cache_data.book_paths[index]
        -- 1. Refuse to overwrite an occupied slot if it belongs to a different book
        if existing_book and existing_book.title and title and existing_book.title:lower() ~= title:lower() then
            logger.info("SeriesManager: Skipping sync of Book " .. tostring(index) .. " to series cache '" .. tostring(slug) .. "': slot occupied by '" .. tostring(existing_book.title) .. "' and index is non-explicit")
            return false
        end
        if existing_path and book_path and existing_path ~= book_path then
            logger.info("SeriesManager: Skipping sync of Book " .. tostring(index) .. " to series cache '" .. tostring(slug) .. "': slot occupied by different path and index is non-explicit")
            return false
        end
        -- 2. Refuse to move a book that is already tracked in a different slot
        for other_idx, other_book in pairs(cache_data.books) do
            if tonumber(other_idx) ~= index and other_book and other_book.title and title and other_book.title:lower() == title:lower() then
                logger.info("SeriesManager: Skipping sync of Book " .. tostring(index) .. " to series cache '" .. tostring(slug) .. "': book already recorded at slot " .. tostring(other_idx) .. " and index is non-explicit")
                return false
            end
        end
        for other_idx, other_path in pairs(cache_data.book_paths) do
            if tonumber(other_idx) ~= index and other_path and book_path and other_path == book_path then
                logger.info("SeriesManager: Skipping sync of Book " .. tostring(index) .. " to series cache '" .. tostring(slug) .. "': book path already recorded at slot " .. tostring(other_idx) .. " and index is non-explicit")
                return false
            end
        end
    end

    local changed = is_new_cache

    local new_entry = {
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
                changed = true
            end
        end
        if cache_data.book_paths[index] ~= book_path then
            cache_data.book_paths[index] = book_path
            changed = true
        end
    end

    if title and title ~= "" then
        for other_idx, other_book in pairs(cache_data.books) do
            if tonumber(other_idx) ~= index and other_book and other_book.title and other_book.title:lower() == title:lower() then
                cache_data.book_paths[other_idx] = nil
                cache_data.books[other_idx] = nil
                changed = true
            end
        end
    end

    local existing_entry = cache_data.books[index]
    if not existing_entry or not deepEqual(existing_entry, new_entry) then
        cache_data.books[index] = new_entry
        changed = true
    end

    if not changed then
        logger.info("SeriesManager: Book " .. tostring(index) .. " already up-to-date in series cache for slug '" .. tostring(slug) .. "' (skipping save)")
        return true
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

-- Write or update series metadata into the book's KOReader sidecar (metadata.epub.lua or docsettings)
function SeriesManager:writeDocMetadata(epub_path, series_name, series_index)
    if not epub_path or epub_path == "" then return false end
    series_index = tonumber(series_index)

    -- Attempt 1: Via DocSettings if available in KOReader runtime
    local ok_ds, DocSettings = pcall(require, "docsettings")
    if ok_ds and DocSettings and DocSettings.open then
        local ok_save = pcall(function()
            local ds = DocSettings:open(epub_path)
            if ds then
                local props = ds:readSetting("doc_props") or {}
                if series_name and series_name ~= "" then
                    props.series = series_name
                end
                if series_index then
                    props.series_index = series_index
                end
                ds:saveSetting("doc_props", props)
                if ds.flush then ds:flush() end
                logger.info("SeriesManager: Saved series metadata via DocSettings for: " .. tostring(epub_path))
                return true
            end
            return false
        end)
        if ok_save then return true end
    end

    -- Attempt 2: Fallback direct write into <file>.sdr/metadata.epub.lua
    local sep = epub_path:find("\\") and "\\" or "/"
    local sdr_dir = epub_path .. ".sdr"
    local sidecar_path = sdr_dir .. sep .. "metadata.epub.lua"

    local ok_direct = pcall(function()
        local escaped_dir = sdr_dir:gsub("'", "'\\''")
        os.execute("mkdir -p '" .. escaped_dir .. "'")
        local loaded = safeLoadCacheFile(sidecar_path) or {}
        loaded.doc_props = loaded.doc_props or {}
        if series_name and series_name ~= "" then
            loaded.doc_props.series = series_name
        end
        if series_index then
            loaded.doc_props.series_index = series_index
        end

        local f = io.open(sidecar_path, "w")
        if not f then return false end
        f:write("-- KOReader Document Metadata Sidecar\nreturn ")
        self:serializeToFile(f, loaded, "")
        f:write("\n")
        f:close()
        logger.info("SeriesManager: Saved series metadata via direct file write to: " .. tostring(sidecar_path))
        return true
    end)

    return ok_direct
end

-- Read metadata from an ebook sidecar or xray cache
function SeriesManager:readBookMetadata(book_path)
    if not book_path or book_path == "" then return nil end
    local sep = book_path:find("\\") and "\\" or "/"
    local sdr_dir = book_path .. ".sdr"
    local sidecar_path = sdr_dir .. sep .. "metadata.epub.lua"
    local xray_cache_path = sdr_dir .. sep .. "xray_cache.lua"

    local title, author, series_name, series_index

    local sidecar = safeLoadCacheFile(sidecar_path)
    if sidecar and sidecar.doc_props then
        local dp = sidecar.doc_props
        title = dp.title
        author = dp.authors or dp.author
        series_name = dp.series or dp.Series
        series_index = tonumber(dp.series_index or dp.seriesindex or dp.SeriesIndex)
    end

    local xray_cache = safeLoadCacheFile(xray_cache_path)
    if xray_cache then
        title = title or xray_cache.title or xray_cache.book_title
        author = author or xray_cache.author or xray_cache.book_author or xray_cache.authors
        series_name = series_name or xray_cache.series or xray_cache.series_name
        series_index = series_index or tonumber(xray_cache.series_index)
    end

    -- Books never opened in KOReader have no sidecar; fall back to the metadata
    -- CoverBrowser's BookInfoManager has already extracted from the file.
    if not series_index then
        local ok_bim, BookInfoManager = pcall(require, "bookinfomanager")
        if ok_bim and BookInfoManager and BookInfoManager.getBookInfo then
            local ok_bi, bi = pcall(BookInfoManager.getBookInfo, BookInfoManager, book_path, false)
            if ok_bi and bi then
                title = title or bi.title
                author = author or bi.authors
                series_name = series_name or bi.series
                series_index = tonumber(bi.series_index)
            end
        end
    end

    if not title then
        local filename = book_path:match("([^/\\]+)$") or book_path
        title = filename:gsub("%.[^%.]+$", "")
    end

    if not series_index and title then
        series_index = self:extractIndexFromTitle(title, series_name)
    end

    return {
        path = book_path,
        title = title,
        author = author,
        series = series_name,
        series_index = series_index,
    }
end

-- Scan directory (and sibling Calibre directories) for supported ebook files
function SeriesManager:scanFolderForEpubs(current_book_path)
    if not current_book_path or current_book_path == "" or not lfs then return {} end
    local sep = current_book_path:find("\\") and "\\" or "/"
    local current_dir = current_book_path:match("^(.*)[/\\][^/\\]+$")
    if not current_dir then return {} end

    local results = {}
    local seen_paths = {}

    local function isEbook(filename)
        if not filename then return false end
        local fn = filename:lower()
        return fn:match("%.epub$") or fn:match("%.kepub%.epub$")
            or fn:match("%.mobi$") or fn:match("%.azw3$")
            or fn:match("%.fb2$") or fn:match("%.pdf$")
    end

    local function scanDir(dir)
        if not dir or not lfs or not lfs.dir then return end
        pcall(function()
            for entry in lfs.dir(dir) do
                if entry ~= "." and entry ~= ".." then
                    local entry_path = dir .. sep .. entry
                    if isEbook(entry) and not seen_paths[entry_path] then
                        seen_paths[entry_path] = true
                        local meta = self:readBookMetadata(entry_path)
                        if meta then
                            table.insert(results, meta)
                        end
                    end
                end
            end
        end)
    end

    -- 1. Scan current directory
    scanDir(current_dir)

    -- 2. Scan sibling directories under parent (Calibre author structure)
    local parent_dir = current_dir:match("^(.*)[/\\][^/\\]+$")
    if parent_dir and parent_dir ~= "" then
        pcall(function()
            local dir_count = 0
            for sub in lfs.dir(parent_dir) do
                if sub ~= "." and sub ~= ".." then
                    dir_count = dir_count + 1
                    if dir_count > 50 then break end
                    local sub_path = parent_dir .. sep .. sub
                    if sub_path ~= current_dir then
                        local attr = lfs.attributes and lfs.attributes(sub_path)
                        if attr and attr.mode == "directory" then
                            scanDir(sub_path)
                        end
                    end
                end
            end
        end)
    end

    return results
end

-- Merge series cache, current book metadata, and folder scan into a consolidated series roster
function SeriesManager:buildSeriesRoster(book_data, props, current_book_path)
    props = props or {}
    local current_title = (book_data and (book_data.title or book_data.book_title))
        or (props.title and (type(props.title) == "table" and table.concat(props.title, ", ") or tostring(props.title)))
        or (current_book_path and current_book_path:match("([^/\\]+)$"):gsub("%.[^%.]+$", ""))
        or "Current Book"

    local current_author = (book_data and (book_data.author or book_data.book_author or book_data.authors))
        or (props.authors and (type(props.authors) == "table" and table.concat(props.authors, ", ") or tostring(props.authors)))

    local series_name = (book_data and book_data.series)
        or props.series or props.Series

    local current_index = tonumber(book_data and book_data.series_index)
        or tonumber(props.series_index or props.seriesindex or props.SeriesIndex)
        or self:extractIndexFromTitle(current_title, series_name)

    local slug = (book_data and book_data.series_slug) or (series_name and makeSlug(series_name))

    local roster = {}
    local indexed_roster = {}

    -- 1. Load from series cache if slug available
    local cache_data = slug and self:loadSeriesCache(slug)
    if cache_data and cache_data.books then
        for idx, b in pairs(cache_data.books) do
            local num_idx = tonumber(idx)
            if num_idx and b then
                local b_path = cache_data.book_paths and cache_data.book_paths[num_idx]
                local item = {
                    index = num_idx,
                    title = b.title or string.format("Book %s", SeriesManager.formatIndex(num_idx)),
                    author = b.author,
                    path = b_path,
                    source = "cache"
                }
                roster[num_idx] = item
                indexed_roster[num_idx] = item
            end
        end
    end

    -- 2. Include current book
    local cur_item = {
        index = current_index or 1,
        title = current_title,
        author = current_author,
        path = current_book_path,
        is_current = true,
        source = "current"
    }
    roster[cur_item.index] = cur_item
    indexed_roster[cur_item.index] = cur_item

    -- 3. Scan folder for nearby ebooks sharing this series name
    if current_book_path and lfs then
        local scanned = self:scanFolderForEpubs(current_book_path)
        for _, b in ipairs(scanned) do
            if b.path ~= current_book_path then
                local matches_series = false
                if series_name and series_name ~= "" and b.series and b.series ~= "" then
                    if makeSlug(b.series) == makeSlug(series_name) then
                        matches_series = true
                    end
                end

                if matches_series and b.series_index then
                    local target_idx = b.series_index
                    if not roster[target_idx] then
                        roster[target_idx] = {
                            index = target_idx,
                            title = b.title,
                            author = b.author,
                            path = b.path,
                            source = "scanned"
                        }
                    end
                end
            end
        end
    end

    -- Convert roster map to array sorted by index
    local sorted_list = {}
    for _, item in pairs(roster) do
        table.insert(sorted_list, item)
    end
    table.sort(sorted_list, function(a, b)
        if a.index ~= b.index then
            return (a.index or 0) < (b.index or 0)
        end
        return (a.title or "") < (b.title or "")
    end)

    return {
        series_name = series_name or "",
        slug = slug or "",
        books = sorted_list,
        current_index = current_index,
    }
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

return SeriesManager
