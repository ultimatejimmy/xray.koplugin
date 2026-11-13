-- X-Ray Series UI and Management
local UIManager       = require("ui/uimanager")
local InfoMessage     = require("ui/widget/infomessage")
local ButtonDialog    = require("ui/widget/buttondialog")
local Screen          = require("device").screen
local Geom            = require("ui/geometry")
local CenterContainer = require("ui/widget/container/centercontainer")
local ImageWidget     = require("ui/widget/imagewidget")

local plugin_path = ((...) or ""):match("(.-)[^%.]+$") or ""
local utils = require(plugin_path .. "xray_utils")
local SeriesManager = require(plugin_path .. "xray_seriesmanager")

local _asset_path_cache = {}
local function getAssetPath(filename)
    if _asset_path_cache[filename] then
        return _asset_path_cache[filename]
    end
    local info = debug.getinfo(1, "S")
    local file_dir = (info and info.source and info.source:match("^@?(.*[/\\])")) or ""
    local candidates = {
        file_dir .. "assets/" .. filename,
        file_dir .. "../assets/" .. filename,
        "plugins/xray.koplugin/assets/" .. filename,
        "./plugins/xray.koplugin/assets/" .. filename,
    }
    for _, path in ipairs(candidates) do
        local f = io.open(path, "r")
        if f then
            f:close()
            _asset_path_cache[filename] = path
            return path
        end
    end
    local fallback = "plugins/xray.koplugin/assets/" .. filename
    _asset_path_cache[filename] = fallback
    return fallback
end

local function makeMenuIcon(icon_file, icon_sz, container_w)
    local sz = icon_sz or (Screen.scaleBySize and Screen:scaleBySize(18) or 18)
    local w = container_w or (Screen.scaleBySize and Screen:scaleBySize(28) or 28)
    return CenterContainer:new{
        dimen = Geom:new{ w = w, h = Screen.scaleBySize and Screen:scaleBySize(36) or 36 },
        ImageWidget:new{
            file = getAssetPath(icon_file),
            width = sz,
            height = sz,
            scale_factor = 0,
            is_icon = true,
            alpha = true,
        }
    }
end

local function bookHasEntities(b, sm)
    if not b or type(b) ~= "table" then return false end
    if sm and sm.hasBookEntities then return sm.hasBookEntities(b) end
    if SeriesManager and SeriesManager.hasBookEntities then return SeriesManager.hasBookEntities(b) end
    return ((b.characters and #b.characters > 0) or
            (b.locations and #b.locations > 0) or
            (b.terms and #b.terms > 0) or
            (b.timeline and #b.timeline > 0)) and true or false
end

local M = {}

function M:toggleSeriesContextEnabled()
    if not self.ai_helper or not self.ai_helper.settings then return end
    local current = not not self.ai_helper.settings.series_context_enabled
    self.ai_helper.settings.series_context_enabled = not current
    self.ai_helper:saveSettings({ series_context_enabled = not current })
    UIManager:setDirty(nil, "ui")
end

function M:manualFetchSeriesContext()
    local ButtonDialog = require("ui/widget/buttondialog")
    local cancel_ref = { cancelled = false }
    local wait_dialog
    wait_dialog = ButtonDialog:new{
        title = self.loc:t("fetching_series_info") or "Identifying series books…",
        buttons = {{{
            text = self.loc:t("cancel") or "Cancel",
            callback = function()
                cancel_ref.cancelled = true
                self:log("XRayPlugin: Series: User cancelled series fetch before launch.")
                UIManager:close(wait_dialog)
            end
        }}}
    }
    UIManager:show(wait_dialog)
    UIManager:nextTick(function()
        if cancel_ref.cancelled then
            self:log("XRayPlugin: Series: nextTick fired after user already cancelled fetch.")
            return
        end
        self:fetchSeriesContext(false, wait_dialog, cancel_ref)
    end)
end

-- Indices of prior books to look for (handles fractional indices like 2.5)
function M:getExpectedPriorIndices(series_info, books, doc_file)
    if self.series_manager and self.series_manager.getExpectedPriorIndices then
        return self.series_manager:getExpectedPriorIndices(series_info, books, doc_file)
    end
    return SeriesManager.wholeIndicesBefore(series_info.index)
end

function M:showSeriesContextPrompt(series_info)
    if self.destroyed then return end
    self:log("XRayPlugin: Series: showSeriesContextPrompt: Series detected: " .. series_info.name .. ", index=" .. tostring(series_info.index) .. ". Showing prompt dialog.")

    local doc_file = self.ui and self.ui.document and self.ui.document.file
    local cache_data = series_info.slug and self.series_manager and self.series_manager.loadSeriesCache and self.series_manager:loadSeriesCache(series_info.slug)
    local prior_count = #self:getExpectedPriorIndices(series_info, cache_data and cache_data.books, doc_file)
    -- The translations format the book number with %d (or %1$d), which shows
    -- 2.5 as "2"; swap that placeholder for %s so fractional indices survive.
    local body_text
    local tmpl = self.loc.translations and self.loc.translations["series_context_prompt_text"]
    if tmpl and tmpl ~= "" and self.loc.format then
        if tmpl:find("%%1%$d") then
            tmpl = tmpl:gsub("%%1%$d", "%%1$s")
        else
            tmpl = tmpl:gsub("%%d", "%%s", 1)
        end
        body_text = self.loc:format(tmpl, "series_context_prompt_text", SeriesManager.formatIndex(series_info.index), series_info.name, prior_count)
    else
        body_text = self.loc:t(
            "series_context_prompt_text",
            series_info.index,
            series_info.name,
            prior_count
        )
    end

    local confirm
    confirm = ButtonDialog:new{
        title = (self.loc:t("series_context_prompt_title") or "Series Detected") .. "\n\n" .. body_text,
        buttons = {
            {
                {
                    text = self.loc:t("yes") or "Yes",
                    is_enter_default = true,
                    callback = function()
                        self:log("XRayPlugin: Series: User chose YES on series context prompt.")
                        UIManager:close(confirm)
                        
                        local cancel_ref = { cancelled = false }
                        local wait_dialog
                        wait_dialog = ButtonDialog:new{
                            title = self.loc:t("fetching_series_info") or "Identifying series books…",
                            buttons = {{{
                                text = self.loc:t("cancel") or "Cancel",
                                callback = function()
                                    cancel_ref.cancelled = true
                                    self:log("XRayPlugin: Series: User cancelled series fetch before launch.")
                                    UIManager:close(wait_dialog)
                                end
                            }}}
                        }
                        UIManager:show(wait_dialog)
                        
                        UIManager:nextTick(function()
                            if cancel_ref.cancelled then
                                self:log("XRayPlugin: Series: nextTick fired after user already cancelled fetch.")
                                return
                            end
                            self:fetchSeriesContext(false, wait_dialog, cancel_ref)
                        end)
                    end,
                },
                {
                    text = self.loc:t("later") or "Later",
                    callback = function()
                        self:log("XRayPlugin: Series: User chose LATER on series context prompt.")
                        UIManager:close(confirm)
                        local ask_later_msg = self.loc:t("series_ask_later_msg") or "Series recap postponed. We will ask again when you open/resume this book."
                        UIManager:show(InfoMessage:new{
                            text = ask_later_msg,
                            timeout = 5
                        })
                    end,
                },
                {
                    text = self.loc:t("dont_ask_again") or "Don't ask again",
                    callback = function()
                        self:log("XRayPlugin: Series: User chose DONT_ASK_AGAIN on series context prompt.")
                        UIManager:close(confirm)
                        local doc_file = self.ui and self.ui.document and self.ui.document.file
                        if not self.cache_manager then
                            self.cache_manager = require(plugin_path .. "xray_cachemanager"):new()
                        end
                        if not self.book_data then
                            self.book_data = (doc_file and self.cache_manager:loadCache(doc_file)) or {}
                        end
                        local cache = self.book_data
                        cache.series_context_dismissed = true
                        if doc_file and self.cache_manager then
                            self.cache_manager:asyncSaveCache(doc_file, cache)
                        end
                        local disabled_msg = self.loc:t("series_disabled_msg") or "Auto-prompt disabled for this book. You can manually fetch recap from X-Ray menu."
                        UIManager:show(InfoMessage:new{
                            text = disabled_msg,
                            timeout = 5
                        })
                    end,
                }
            }
        }
    }
    UIManager:show(confirm)
end

function M:checkSeriesContext()
    if self.flushSeriesSync then
        self:flushSeriesSync()
    end
    self:log("XRayPlugin: Series: checkSeriesContext starting")
    if self.destroyed then
        self:log("XRayPlugin: Series: checkSeriesContext: plugin destroyed, skipping")
        return
    end
    if self._unit_scan_in_progress then
        self:log("XRayPlugin: Series: checkSeriesContext: unit scan in progress, deferring series check")
        UIManager:scheduleIn(5, function()
            if self.destroyed or not self.ui or not self.ui.document then return end
            self:checkSeriesContext()
        end)
        return
    end
    if not self.ui or not self.ui.document then
        self:log("XRayPlugin: Series: checkSeriesContext: document/ui not available, skipping")
        return
    end

    if not self.ai_helper or not self.ai_helper.settings or not self.ai_helper.settings.series_context_enabled then
        self:log("XRayPlugin: Series: checkSeriesContext: series_context_enabled setting is false/nil, skipping")
        return
    end

    if self.book_data and (self.book_data.series_context_loaded or self.book_data.series_context_dismissed) then
        self:log("XRayPlugin: Series: checkSeriesContext: series context is already loaded or dismissed, skipping")
        return
    end

    local props = self.ui.document:getProps() or {}
    local function sanitizeMetadata(val)
        if type(val) == "string" then return val
        elseif type(val) == "table" then return table.concat(val, ", ")
        else return "Unknown" end
    end
    local title = sanitizeMetadata(props.title)
    local author = sanitizeMetadata(props.authors)

    self:log("XRayPlugin: Series: checkSeriesContext: checking book title=" .. tostring(title) .. ", author=" .. tostring(author))

    local function saveSeriesChecked()
        self:log("XRayPlugin: Series: Saving series check outcome (dismissed=true) to cache")
        local doc_file = self.ui and self.ui.document and self.ui.document.file
        if not self.cache_manager then
            self.cache_manager = require(plugin_path .. "xray_cachemanager"):new()
        end
        if not self.book_data then
            self.book_data = (doc_file and self.cache_manager:loadCache(doc_file)) or {}
        end
        self.book_data.series_context_dismissed = true
        if doc_file and self.cache_manager then
            self.cache_manager:asyncSaveCache(doc_file, self.book_data)
        end
    end

    -- 1. Try metadata check first (without AI, passes nil for ai_helper)
    local series_info = self.series_manager and (self.series_manager.getSeriesInfo and self.series_manager:getSeriesInfo(self.book_data, props, title, author, nil) or (self.series_manager.detectSeries and self.series_manager:detectSeries(props, title, author, nil)))
    local has_explicit_metadata_index = props and (props.series_index or props.seriesindex or props.SeriesIndex)
    local has_title_index = series_info and self.series_manager and self.series_manager.extractIndexFromTitle and self.series_manager:extractIndexFromTitle(title, series_info.name)

    if series_info and series_info.name and series_info.index then
        if series_info.index > 1 then
            self:log("XRayPlugin: Series: Metadata/title check found series: " .. series_info.name .. ", index=" .. tostring(series_info.index))
            
            -- Check if all prior books are already in local SeriesCache or on local disk
            local slug = series_info.slug or (self.series_manager and self.series_manager.makeSlug and self.series_manager:makeSlug(series_info.name))
            local cache_data = slug and self.series_manager and self.series_manager.loadSeriesCache and self.series_manager:loadSeriesCache(slug) or { series_slug = slug, books = {} }
            cache_data.books = cache_data.books or {}

            -- Try to discover any missing prior books on local disk first
            local doc_file = self.ui and self.ui.document and self.ui.document.file
            local prior_indices = self:getExpectedPriorIndices(series_info, cache_data.books, doc_file)
            for _, p_idx in ipairs(prior_indices) do
                local cached_b = cache_data.books[p_idx]
                local has_entities = bookHasEntities(cached_b, self.series_manager)
                if not cached_b or not has_entities or cached_b.source ~= "local_xray" then
                    local check_path = (cache_data.book_paths and cache_data.book_paths[p_idx]) or doc_file
                    local local_book = self.series_manager and self.series_manager.findLocalBookXRay and self.series_manager:findLocalBookXRay(series_info, p_idx, check_path, nil, self.cache_manager)
                    if bookHasEntities(local_book, self.series_manager) then
                        cache_data.books[p_idx] = local_book
                    end
                end
            end

            local all_priors_cached = true
            for _, p_idx in ipairs(prior_indices) do
                local cached_b = cache_data.books[p_idx]
                if not bookHasEntities(cached_b, self.series_manager) then
                    all_priors_cached = false
                    break
                end
            end

            if all_priors_cached then
                self:log("XRayPlugin: Series: All prior books resolved locally. Merging series context automatically.")
                self:mergeSeriesContext(cache_data, series_info)
                return
            end

            if not utils:isSilentNetworkAvailable() then
                self:log("XRayPlugin: Series: Prior books missing from cache and device is offline, skipping silently.")
                return
            end

            self:showSeriesContextPrompt(series_info)
            return
        elseif series_info.has_explicit_index or has_explicit_metadata_index or has_title_index or not (props and (props.series or props.Series)) then
            self:log("XRayPlugin: Series: Metadata/title check confirmed first book in series: " .. series_info.name .. ", index=" .. tostring(series_info.index) .. ". Caching check outcome.")
            saveSeriesChecked()
            return
        else
            self:log("XRayPlugin: Series: Series name found in metadata (" .. series_info.name .. "), but index unknown. Falling through to async AI check.")
        end
    end

    -- 2. Fallback to AI (performed asynchronously to prevent UI freeze, requires network)
    if not utils:isSilentNetworkAvailable() then
        self:log("XRayPlugin: Series: Device is offline, skipping async AI series check silently.")
        return
    end

    self:log("XRayPlugin: Series: Metadata check didn't conclusively resolve series/index. Initiating asynchronous AI check.")
    local prompt = self.ai_helper:createPrompt(title, author, nil, "series_detect")
    local req_params = self.ai_helper:buildComprehensiveRequest(nil, nil, nil, prompt)
    if not req_params then
        self:log("XRayPlugin: Series: Failed to build AI request for series check")
        return
    end

    local DataStorage = require("datastorage")
    local result_file = DataStorage:getSettingsDir() .. "/xray/bg_series_detect_" .. tostring(os.time()) .. ".json"
    
    local request_pid = self.ai_helper:makeRequestAsync(req_params, result_file)
    if not request_pid then
        self:log("XRayPlugin: Series: Async check not supported/failed (e.g. on Windows). Skipping automatic AI fallback.")
        return
    end

    local poll_count = 0
    local max_polls = 150 -- 5 minutes at 2s intervals
    local function pollDetect()
        if self.destroyed or not self.ui or not self.ui.document then
            pcall(function() os.remove(result_file) end)
            return
        end
        poll_count = poll_count + 1
        local result, p_err_code, p_err_msg = self.ai_helper:checkAsyncResult(result_file, request_pid)
        if result == nil then
            if poll_count < max_polls then
                UIManager:scheduleIn(2, pollDetect)
            else
                self:log("XRayPlugin: Series: Async series check timed out")
            end
        elseif result == false then
            self:log("XRayPlugin: Series: Async series check failed: " .. tostring(p_err_msg))
        else
            -- AI returned a valid result!
            self:log("XRayPlugin: Series: Async series check result received")
            if result.is_series then
                local name = result.series_name or (series_info and series_info.name) or (props and (props.series or props.Series))
                local title_idx = self.series_manager and self.series_manager.extractIndexFromTitle and self.series_manager:extractIndexFromTitle(title, name)
                local index = tonumber(result.book_index) or title_idx or 1
                if name and name ~= "" then
                    local make_slug_fn = self.series_manager and self.series_manager.makeSlug
                    local slug = make_slug_fn and self.series_manager:makeSlug(name) or name:lower():gsub("[%s%p]+", "_"):gsub("^_+", ""):gsub("_+$", "")
                    local ai_series_info = {
                        name = name,
                        index = index,
                        slug = slug
                    }
                    self:log("XRayPlugin: Series: Async check detected series=" .. tostring(name) .. ", index=" .. tostring(index))
                    if index > 1 then
                        local cache_data = slug and self.series_manager and self.series_manager.loadSeriesCache and self.series_manager:loadSeriesCache(slug) or { series_slug = slug, books = {} }
                        cache_data.books = cache_data.books or {}

                        local doc_file = self.ui and self.ui.document and self.ui.document.file
                        local prior_indices = self:getExpectedPriorIndices(ai_series_info, cache_data.books, doc_file)
                        for _, p_idx in ipairs(prior_indices) do
                            local cached_b = cache_data.books[p_idx]
                            local has_entities = bookHasEntities(cached_b, self.series_manager)
                            if not cached_b or not has_entities or cached_b.source ~= "local_xray" then
                                local check_path = (cache_data.book_paths and cache_data.book_paths[p_idx]) or doc_file
                                local local_book = self.series_manager and self.series_manager.findLocalBookXRay and self.series_manager:findLocalBookXRay(ai_series_info, p_idx, check_path, nil, self.cache_manager)
                                if bookHasEntities(local_book, self.series_manager) then
                                    cache_data.books[p_idx] = local_book
                                end
                            end
                        end

                        local all_priors_cached = true
                        for _, p_idx in ipairs(prior_indices) do
                            local cached_b = cache_data.books[p_idx]
                            if not bookHasEntities(cached_b, self.series_manager) then
                                all_priors_cached = false
                                break
                            end
                        end

                        if all_priors_cached then
                            self:log("XRayPlugin: Series: All prior books resolved locally. Merging series context automatically.")
                            self:mergeSeriesContext(cache_data, ai_series_info)
                        else
                            self:showSeriesContextPrompt(ai_series_info)
                        end
                    else
                        self:log("XRayPlugin: Series: Book is first in series (index=" .. tostring(index) .. "), skipping prompt. Caching check outcome.")
                        saveSeriesChecked()
                    end
                else
                    self:log("XRayPlugin: Series: Async check detected series, but name is invalid. Caching check outcome.")
                    saveSeriesChecked()
                end
            else
                self:log("XRayPlugin: Series: Async check determined book is not part of a series. Caching check outcome.")
                saveSeriesChecked()
            end
        end
    end
    UIManager:scheduleIn(2, pollDetect)
end

-- Horizon state resolution and evolution extracted to xray_horizon.lua



function M:getCurrentSeriesInfo()
    if not self.series_manager then
        local SeriesManager = require(plugin_path .. "xray_seriesmanager")
        self.series_manager = SeriesManager:new()
    end

    local props = self.ui and self.ui.document and self.ui.document.getProps and self.ui.document:getProps() or {}
    local function sanitizeMetadata(val)
        if type(val) == "string" then return val
        elseif type(val) == "table" then return table.concat(val, ", ")
        else return nil end
    end
    local title = sanitizeMetadata(props.title)
    local author = sanitizeMetadata(props.authors)

    local info = self.series_manager:getSeriesInfo(self.book_data, props, title, author)
    if info and self.book_data then
        self.book_data.series_slug = info.slug
        self.book_data.series = info.name
        self.book_data.series_index = info.index
        if not self.book_data.title and title then
            self.book_data.title = title
        end
    end
    return info
end

-- Manage Series UI: View, edit series name, assign/change volume numbers, add/remove books, and persist to sidecar metadata
function M:showManageSeriesDialog()
    if self.flushSeriesSync then
        self:flushSeriesSync()
    end
    if not self.series_manager then
        local SeriesManager = require(plugin_path .. "xray_seriesmanager")
        self.series_manager = SeriesManager:new()
    end

    local doc_file = self.ui and self.ui.document and self.ui.document.file
    local props = self.ui and self.ui.document and self.ui.document.getProps and self.ui.document:getProps() or {}

    local roster_data = self.series_manager:buildSeriesRoster(self.book_data, props, doc_file)
    local series_name = roster_data.series_name or ""
    local books_roster = roster_data.books or {}

    local function sortRoster()
        table.sort(books_roster, function(a, b)
            if (a.index or 0) ~= (b.index or 0) then
                return (a.index or 0) < (b.index or 0)
            end
            return (a.title or "") < (b.title or "")
        end)
    end
    sortRoster()

    local active_series_menu = nil
    local active_picker_menu = nil
    local active_edit_menu = nil

    local function closePickerMenu()
        if active_picker_menu then
            local pm = active_picker_menu
            active_picker_menu = nil
            UIManager:close(pm)
        end
    end

    local function closeEditMenu()
        if active_edit_menu then
            local em = active_edit_menu
            active_edit_menu = nil
            UIManager:close(em)
        end
    end

    local function showIndexPicker(current_idx, callback)
        closePickerMenu()

        local options = {}
        for i = 1, 50 do
            table.insert(options, {
                text = string.format("Book %d", i),
                index = i,
                checked = (i == current_idx),
            })
        end
        table.insert(options, {
            text = self.loc:t("manage_series_custom_index") or "Custom number…",
            is_custom = true,
        })

        local state_w = Screen.scaleBySize and Screen:scaleBySize(28) or 28
        local item_table = {}
        for _, opt in ipairs(options) do
            local o = opt
            table.insert(item_table, {
                state = o.checked and makeMenuIcon("check.svg") or nil,
                text = o.text,
                keep_menu_open = false,
                callback = function()
                    if o.is_custom then
                        local InputDialog = require("ui/widget/inputdialog")
                        local num_dialog
                        num_dialog = InputDialog:new{
                            title = self.loc:t("manage_series_enter_index") or "Enter Volume Number",
                            input = tostring(current_idx or 1),
                            input_type = "number",
                            buttons = {{{
                                text = self.loc:t("cancel") or "Cancel",
                                callback = function() UIManager:close(num_dialog) end,
                            }, {
                                text = self.loc:t("ok") or "OK",
                                is_enter_default = true,
                                callback = function()
                                    local val = tonumber(num_dialog:getInputText())
                                    UIManager:close(num_dialog)
                                    if val and val > 0 then
                                        closePickerMenu()
                                        callback(val)
                                    end
                                end,
                            }}}
                        }
                        UIManager:show(num_dialog)
                    else
                        closePickerMenu()
                        callback(o.index)
                    end
                end,
            })
        end

        active_picker_menu = self:newMenu("series_index_picker", {
            title = self.loc:t("manage_series_pick_index") or "Select Volume #",
            item_table = item_table,
            state_w = state_w,
            is_borderless = true,
            width = Screen:getWidth(),
            height = Screen:getHeight(),
            on_close_callback = function()
                active_picker_menu = nil
            end,
        })
        UIManager:show(active_picker_menu)
    end

    local function editBookEntry(book_item, on_done)
        closeEditMenu()

        local state_w = Screen.scaleBySize and Screen:scaleBySize(28) or 28
        local edit_items = {
            {
                state = makeMenuIcon("edit.svg"),
                text = string.format("%s: %s", self.loc:t("manage_series_volume_label") or "Volume #", tostring(book_item.index or 1)),
                keep_menu_open = false,
                callback = function()
                    closeEditMenu()
                    showIndexPicker(book_item.index, function(new_idx)
                        book_item.index = new_idx
                        sortRoster()
                        if on_done then on_done() end
                    end)
                end,
            },
            {
                state = makeMenuIcon("edit.svg"),
                text = string.format("%s: %s", self.loc:t("manage_series_title_label") or "Title", tostring(book_item.title or "")),
                keep_menu_open = false,
                callback = function()
                    local InputDialog = require("ui/widget/inputdialog")
                    local title_dlg
                    title_dlg = InputDialog:new{
                        title = self.loc:t("manage_series_edit_title") or "Edit Book Title",
                        input = book_item.title or "",
                        buttons = {{{
                            text = self.loc:t("cancel") or "Cancel",
                            callback = function() UIManager:close(title_dlg) end,
                        }, {
                            text = self.loc:t("save") or "Save",
                            is_enter_default = true,
                            callback = function()
                                local new_title = title_dlg:getInputText()
                                UIManager:close(title_dlg)
                                if new_title and #new_title > 0 then
                                    closeEditMenu()
                                    book_item.title = new_title
                                    if on_done then on_done() end
                                end
                            end,
                        }}}
                    }
                    UIManager:show(title_dlg)
                end,
            }
        }

        active_edit_menu = self:newMenu("series_book_edit", {
            title = book_item.title or "Edit Book",
            item_table = edit_items,
            state_w = state_w,
            is_borderless = true,
            width = Screen:getWidth(),
            height = Screen:getHeight(),
            on_close_callback = function()
                active_edit_menu = nil
            end,
        })
        UIManager:show(active_edit_menu)
    end

    local rebuildMenu

    local function openFileChooserToAdd()
        local start_dir = doc_file and (doc_file:match("^(.*)[/\\][^/\\]+$") or doc_file) or "/sdcard/Books"
        if start_dir:match("%.sdr$") then
            start_dir = start_dir:gsub("[/\\]+[^/\\]+%.sdr$", "")
        end

        local ok_bp, XRayBookPicker = pcall(require, plugin_path .. "xray_book_picker")
        if not ok_bp or not XRayBookPicker then
            ok_bp, XRayBookPicker = pcall(require, "xray_book_picker")
        end

        -- In Calibre and folder-per-book setups, if start_dir contains only the current book
        -- and no subfolders, start at the parent author directory so sibling books/folders
        -- in the series are visible immediately.
        if ok_bp and XRayBookPicker and XRayBookPicker.scanDirectory and XRayBookPicker.getParentPath then
            local subdirs, books = XRayBookPicker.scanDirectory(start_dir)
            if #subdirs == 0 and #books <= 1 then
                local parent = XRayBookPicker.getParentPath(start_dir)
                if parent then
                    local p_subdirs, p_books = XRayBookPicker.scanDirectory(parent)
                    if #p_subdirs > 0 or #p_books > 1 then
                        start_dir = parent
                    end
                end
            end
        end

        local function normStr(s)
            if not s then return "" end
            return s:lower():gsub("[%s%-_%.,%:%'\"%(%)%[%]]+", " "):match("^%s*(.-)%s*$") or ""
        end
        local function normPath(p)
            if not p then return "" end
            return p:gsub("\\", "/"):gsub("/+", "/"):lower():match("^%s*(.-)%s*$") or ""
        end

        local function isBookInRoster(check_path)
            if not check_path or check_path == "" then return false end
            local n_path = normPath(check_path)
            local fn = check_path:match("([^/\\]+)$"):gsub("%.[^%.]+$", "")
            local n_fn = normStr(fn)
            local meta = self.series_manager and self.series_manager.readBookMetadata and self.series_manager:readBookMetadata(check_path)
            local n_title = normStr(meta and meta.title or fn)

            for _, b in ipairs(books_roster) do
                local bp = normPath(b.path)
                local bt = normStr(b.title)
                if bp ~= "" and bp == n_path then
                    return true, b
                elseif bt ~= "" and (bt == n_title or bt == n_fn) then
                    return true, b
                elseif bt ~= "" and n_title ~= "" and (#bt >= 6 and #n_title >= 6) and (bt:find(n_title, 1, true) or n_title:find(bt, 1, true)) then
                    return true, b
                elseif bt ~= "" and n_fn ~= "" and (#bt >= 6 and #n_fn >= 6) and (bt:find(n_fn, 1, true) or n_fn:find(bt, 1, true)) then
                    return true, b
                end
            end
            return false
        end

        local handleBookChosen = function(chosen_path)
            if not chosen_path or chosen_path == "" then return end
            local already_added = isBookInRoster(chosen_path)
            if already_added then
                UIManager:show(InfoMessage:new{
                    text = self.loc:t("manage_series_already_added") or "This book is already in the series roster.",
                    timeout = 3
                })
                return
            end

            local meta = self.series_manager:readBookMetadata(chosen_path)
            local suggested_index = meta and meta.series_index or (#books_roster + 1)

            showIndexPicker(suggested_index, function(assigned_index)
                table.insert(books_roster, {
                    index = assigned_index,
                    title = meta and meta.title or chosen_path:match("([^/\\]+)$"):gsub("%.[^%.]+$", ""),
                    author = meta and meta.author,
                    path = chosen_path,
                    source = "manual"
                })
                sortRoster()
                rebuildMenu()
            end)
        end

        if ok_bp and XRayBookPicker and XRayBookPicker.show then
            XRayBookPicker.show{
                initial_path = start_dir,
                loc = self.loc,
                is_book_in_roster = isBookInRoster,
                on_confirm = handleBookChosen,
            }
            return
        end

        -- Fallback to PathChooser if XRayBookPicker failed to load
        local ok_pc, PathChooser = pcall(require, "ui/widget/pathchooser")
        if not ok_pc or not PathChooser then
            UIManager:show(InfoMessage:new{
                text = self.loc:t("series_link_no_chooser") or "File picker is not available on this device.",
                timeout = 4
            })
            return
        end

        UIManager:show(PathChooser:new{
            title = self.loc:t("manage_series_choose_book") or "Choose Book to Add",
            path = start_dir,
            select_directory = false,
            file_filter = function(filename)
                filename = tostring(filename or ""):lower()
                return filename:match("%.epub$") or filename:match("%.kepub%.epub$")
                    or filename:match("%.mobi$") or filename:match("%.azw3$")
                    or filename:match("%.fb2$") or filename:match("%.pdf$")
            end,
            onConfirm = handleBookChosen,
        })
    end

    local function saveChanges()
        if not series_name or series_name == "" then
            UIManager:show(InfoMessage:new{
                text = self.loc:t("manage_series_name_required") or "Please specify a series name before saving.",
                timeout = 3
            })
            return
        end

        local slug = self.series_manager:makeSlug(series_name)
        if not slug or slug == "" then slug = "series" end

        -- 0. Prune removed books from series cache
        local current_roster_indices = {}
        for _, b in ipairs(books_roster) do
            if b.index then
                current_roster_indices[b.index] = true
            end
        end
        local existing_series_cache = self.series_manager and self.series_manager.loadSeriesCache and self.series_manager:loadSeriesCache(slug)
        if existing_series_cache and existing_series_cache.books then
            local modified = false
            for idx in pairs(existing_series_cache.books) do
                if not current_roster_indices[idx] then
                    existing_series_cache.books[idx] = nil
                    if existing_series_cache.book_paths then
                        existing_series_cache.book_paths[idx] = nil
                    end
                    modified = true
                end
            end
            if modified and self.series_manager.saveSeriesCache then
                self.series_manager:saveSeriesCache(slug, existing_series_cache)
            end
        end

        -- 1. Sync all books to series cache
        for _, b in ipairs(books_roster) do
            if b.index then
                local real_data = nil
                if b.path then
                    if self.cache_manager and self.cache_manager.loadCache then
                        real_data = self.cache_manager:loadCache(b.path)
                    end
                    if (not real_data or not bookHasEntities(real_data, self.series_manager)) and self.series_manager and self.series_manager.getCandidateSidecarDirs then
                        local cand_dirs = self.series_manager:getCandidateSidecarDirs(b.path)
                        for _, sdr_dir in ipairs(cand_dirs) do
                            local cache_file = sdr_dir .. "/xray_cache.lua"
                            local ok_c, loaded = pcall(dofile, cache_file)
                            if ok_c and type(loaded) == "table" and bookHasEntities(loaded, self.series_manager) then
                                real_data = loaded
                                break
                            end
                        end
                    end
                end

                local has_entities = bookHasEntities(real_data, self.series_manager)
                local book_to_sync = has_entities and real_data or {
                    title = b.title,
                    author = b.author,
                    characters = {},
                    locations = {},
                    terms = {},
                    timeline = {},
                    source = "roster",
                }
                local source = has_entities and (real_data.source or "local_xray") or "roster"
                self.series_manager:syncBookToSeriesCache(slug, b.index, book_to_sync, b.path, source)

                -- 2. Write metadata to KOReader sidecar
                if b.path then
                    self.series_manager:writeDocMetadata(b.path, series_name, b.index)
                end
            end
        end

        -- 3. Update current book data and cache
        if self.book_data then
            self.book_data.series = series_name
            self.book_data.series_slug = slug
            for _, b in ipairs(books_roster) do
                if b.is_current or (doc_file and b.path == doc_file) then
                    self.book_data.series_index = b.index
                end
            end
            self.book_data.series_context_loaded = nil
            self.book_data.series_context_dismissed = nil
            if self.cache_manager and doc_file then
                self.cache_manager:asyncSaveCache(doc_file, self.book_data)
            end
        end

        closePickerMenu()
        closeEditMenu()
        if active_series_menu then
            UIManager:close(active_series_menu)
            active_series_menu = nil
        end

        UIManager:show(InfoMessage:new{
            text = self.loc:t("manage_series_saved") or "Series saved.",
            timeout = 3
        })
    end

    rebuildMenu = function()
        closePickerMenu()
        closeEditMenu()
        if active_series_menu then
            UIManager:close(active_series_menu)
            active_series_menu = nil
        end

        local state_w = Screen.scaleBySize and Screen:scaleBySize(28) or 28
        local items = {}

        -- Row 1: Series Name Header / Editor
        local display_name = (series_name and series_name ~= "") and series_name or (self.loc:t("manage_series_unnamed") or "(Tap to name series)")
        table.insert(items, {
            state = makeMenuIcon("star.svg"),
            text = string.format("%s: %s", self.loc:t("manage_series_series_name") or "Series Name", display_name),
            keep_menu_open = true,
            separator = true,
            callback = function()
                local InputDialog = require("ui/widget/inputdialog")
                local name_dlg
                name_dlg = InputDialog:new{
                    title = self.loc:t("manage_series_series_name") or "Series Name",
                    input = series_name or "",
                    buttons = {{{
                        text = self.loc:t("cancel") or "Cancel",
                        callback = function() UIManager:close(name_dlg) end,
                    }, {
                        text = self.loc:t("save") or "Save",
                        is_enter_default = true,
                        callback = function()
                            local val = name_dlg:getInputText()
                            UIManager:close(name_dlg)
                            if val then
                                series_name = val:gsub("^%s+", ""):gsub("%s+$", "")
                                rebuildMenu()
                            end
                        end,
                    }}}
                }
                UIManager:show(name_dlg)
            end,
        })

        -- Row 2: Add Book action button
        table.insert(items, {
            state = makeMenuIcon("plus.svg"),
            text = self.loc:t("manage_series_add_book") or "Add Book…",
            keep_menu_open = true,
            separator = true,
            callback = function()
                UIManager:nextTick(function()
                    openFileChooserToAdd()
                end)
            end,
        })

        -- Book roster rows
        for i, b in ipairs(books_roster) do
            local idx_str = "#" .. SeriesManager.formatIndex(b.index or 0)
            local current_badge = (b.is_current or (doc_file and b.path == doc_file)) and ("  " .. (self.loc:t("manage_series_current_book") or "(Current Book)")) or ""
            local book_label = string.format("%-4s %s%s", idx_str, b.title or "Untitled", current_badge)

            local captured_item = b
            local captured_idx = i

            table.insert(items, {
                state = makeMenuIcon("book.svg"),
                text = book_label,
                keep_menu_open = false,
                sub_item_table = {
                    {
                        state = makeMenuIcon("edit.svg"),
                        text = self.loc:t("manage_series_edit_entry") or "Edit Volume # & Title",
                        keep_menu_open = false,
                        callback = function()
                            editBookEntry(captured_item, function() rebuildMenu() end)
                        end,
                    },
                    {
                        state = makeMenuIcon("trash-2.svg"),
                        text = self.loc:t("manage_series_remove_entry") or "Remove from Series",
                        keep_menu_open = false,
                        callback = function()
                            table.remove(books_roster, captured_idx)
                            sortRoster()
                            rebuildMenu()
                        end,
                    }
                }
            })
        end

        -- Save / Done button at bottom
        table.insert(items, {
            state = makeMenuIcon("check.svg"),
            text = self.loc:t("save") or "Save Series",
            separator = true,
            keep_menu_open = false,
            callback = function()
                saveChanges()
            end,
        })

        active_series_menu = self:newMenu("manage_series_menu", {
            title = self.loc:t("menu_manage_series") or "Manage Series",
            item_table = items,
            state_w = state_w,
            is_borderless = true,
            width = Screen:getWidth(),
            height = Screen:getHeight(),
            on_close_callback = function()
                closePickerMenu()
                closeEditMenu()
                active_series_menu = nil
            end,
        })
        UIManager:show(active_series_menu)
    end

    rebuildMenu()
end

-- Images UI extracted to xray_images_ui.lua



return M
