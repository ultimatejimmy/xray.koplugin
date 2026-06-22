-- X-Ray AI Fetching and Network Functions

local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local ConfirmBox = require("ui/widget/confirmbox")
local ButtonDialog = require("ui/widget/buttondialog")
local logger = require("logger")
local plugin_path = ((...) or ""):match("(.-)[^%.]+$") or ""
local utils = require(plugin_path .. "xray_utils")

local M = {}

local function sanitizeMetadata(val)
    if type(val) == "string" then return val
    elseif type(val) == "table" then return table.concat(val, ", ")
    else return "Unknown" end
end

function M:fetchFromAI()
    require("ui/network/manager"):runWhenOnline(function() 
        local current_page = self.ui:getCurrentPage()
        local reading_percent = math.floor((current_page / self.ui.document:getPageCount()) * 100)
        local spoiler_setting = self.ai_helper.settings and self.ai_helper.settings.spoiler_setting or "spoiler_free"
        
        if spoiler_setting == "full_book" then
            self:continueWithFetch(100)
        else
            self:continueWithFetch(reading_percent)
        end
    end)
end

function M:updateFromAI()
    require("ui/network/manager"):runWhenOnline(function() 
        local current_page = self.ui:getCurrentPage()
        local reading_percent = math.floor((current_page / self.ui.document:getPageCount()) * 100)
        local spoiler_setting = self.ai_helper.settings and self.ai_helper.settings.spoiler_setting or "spoiler_free"
        
        local last_fetch_page = nil
        if self.book_data and self.book_data.last_fetch_page then
            last_fetch_page = self.book_data.last_fetch_page
        end
        self:log("XRayPlugin: updateFromAI - last_fetch_page=" .. tostring(last_fetch_page))
        
        if spoiler_setting == "full_book" then
            self:continueWithFetch(100, true)
        else
            self:continueWithFetch(reading_percent, true, last_fetch_page)
        end
    end)
end

function M:fetchSingleWord(text, pos0, pos1)
    require("ui/network/manager"):runWhenOnline(function()
        local current_page = self.ui:getCurrentPage()
        local reading_percent = math.floor((current_page / (self.ui.document:getPageCount() or 1)) * 100)
        local spoiler_setting = self.ai_helper.settings and self.ai_helper.settings.spoiler_setting or "spoiler_free"
        
        local limit_percent = reading_percent
        if spoiler_setting == "full_book" then limit_percent = 100 end

        local ButtonDialog = require("ui/widget/buttondialog")
        local is_cancelled = false
        local wait_msg = ButtonDialog:new{
            title = self.loc:t("looking_up_msg", text:sub(1, 30)),
            text = text,
            buttons = {{{
                text = self.loc:t("cancel") or "Cancel",
                callback = function()
                    is_cancelled = true
                    if wait_msg then UIManager:close(wait_msg) end
                end
            }}}
        }
        UIManager:show(wait_msg)

        UIManager:scheduleIn(0.5, function()
            if is_cancelled or self.destroyed then return end
            if not self.chapter_analyzer then self.chapter_analyzer = require(plugin_path .. "xray_chapteranalyzer"):new() end
            
            -- 1. Distributed chapter samples (Start/Mid/End of each chapter up to current)
            -- We use a moderate budget (60k) to balance context depth with fetch speed.
            local samples, chapter_titles = self.chapter_analyzer:getDetailedChapterSamples(self.ui, 100, 60000, limit_percent == 100)
            
            -- 2. Immediate book text (Previous and Current page for maximum context relevance)
            local end_page = current_page + 1
            local book_text = self.chapter_analyzer:getTextFromPageRange(self.ui, math.max(1, current_page - 1), end_page, 25000)
            
            local context_prefix = "SEARCH TARGET: \"" .. text .. "\"\n"
                .. "IMPORTANT: The reader highlighted exactly this text. It IS a meaningful term from this book.\n"
                .. "Even if the exact phrase does not appear in the page samples below, it was highlighted on the reader's current page. Treat it as a valid term and provide its definition.\n\n"
            book_text = context_prefix .. (book_text or "")
            
            -- Always inject a direct reference to ensure the AI validates the term
            if book_text and text then
                book_text = book_text .. "\n\n[TERM HIGHLIGHTED BY READER — MUST DEFINE]: \"" .. text .. "\""
            end
            
            self:log("fetchSingleWord: extracted book_text length: " .. tostring(book_text and #book_text or 0))
            
            local context = {
                reading_percent = limit_percent,
                chapter_samples = samples,
                book_text = book_text
            }

            local result, error_code, error_msg = self.ai_helper:lookupSingleWord(text, context)
            if wait_msg then UIManager:close(wait_msg) end

            if not result then
                local title, text = utils:getFriendlyError(error_code, error_msg, self.loc)
                UIManager:show(ConfirmBox:new{
                    text = title .. "\n\n" .. text,
                    ok_text = self.loc:t("ok") or "OK",
                    cancel_text = nil
                })
                return
            end

            if result.is_valid then
                local item = result.item
                local item_type = result.type
                
                -- Ensure tables exist before trying to merge
                self.characters = self.characters or {}
                self.locations = self.locations or {}
                self.historical_figures = self.historical_figures or {}
                self.terms = self.terms or {}

                -- Merge into our tables
                local target_list
                if item_type == "character" then
                    target_list = self.characters
                elseif item_type == "location" then
                    target_list = self.locations
                elseif item_type == "historical_figure" then
                    target_list = self.historical_figures
                elseif item_type == "term" then
                    target_list = self.terms
                end

                if target_list then
                    -- Resolve current chapter title for history tracking
                    local chapter_title = nil
                    if self.ui and self.ui.document and current_page then
                        local toc = self.ui.document:getToc()
                        if toc then
                            for _, entry in ipairs(toc) do
                                if entry.page and entry.page <= current_page then
                                    chapter_title = entry.title
                                else
                                    break
                                end
                            end
                        end
                    end

                    -- Check if already exists (case-insensitive)
                    local found = false
                    for _, existing in ipairs(target_list) do
                        if (existing.name or ""):lower() == (item.name or ""):lower() then
                            -- Update description/role
                            for k, v in pairs(item) do existing[k] = v end
                            
                            -- Record history for single word lookup
                            local desc_key = item_type == "historical_figure" and "biography" or "description"
                            if existing[desc_key] and existing[desc_key] ~= "" then
                                existing.history = existing.history or {}
                                local dup = false
                                for _, entry in ipairs(existing.history) do
                                    if entry.page == current_page then
                                        entry[desc_key] = existing[desc_key]
                                        entry.chapter = chapter_title or entry.chapter
                                        dup = true; break
                                    end
                                end
                                if not dup then
                                    local hist_entry = { page = current_page, chapter = chapter_title or "" }
                                    hist_entry[desc_key] = existing[desc_key]
                                    table.insert(existing.history, hist_entry)
                                end
                            end
                            found = true
                            break
                        end
                    end
                    if not found then
                        local desc_key = item_type == "historical_figure" and "biography" or "description"
                        if item[desc_key] and item[desc_key] ~= "" then
                            local hist_entry = { page = current_page, chapter = chapter_title or "" }
                            hist_entry[desc_key] = item[desc_key]
                            item.history = { hist_entry }
                        end
                        table.insert(target_list, item)
                    end
                    
                    -- Sort and save cache
                    self:sortDataByFrequency(target_list, book_text, "name")
                    if not self.cache_manager then self.cache_manager = require(plugin_path .. "xray_cachemanager"):new() end
                    
                    if not self.book_data then
                        self.book_data = self.cache_manager:loadCache(self.ui.document.file) or {}
                    end
                    local updated = self.book_data
                    updated.characters = self.characters
                    updated.locations = self.locations
                    updated.historical_figures = self.historical_figures
                    updated.terms = self.terms
                    updated.timeline = self.timeline
                    updated.book_type = self.book_type or updated.book_type
                    updated.author_info = self.author_info or updated.author_info
                    updated.last_fetch_page = updated.last_fetch_page
                    
                    self.cache_manager:asyncSaveCache(self.ui.document.file, updated)
                end
                
                -- Always show result if it's valid, even if it didn't merge into a target_list
                self.lookup_manager:showResult(item, item_type)
            else
                local err = result.error_message or self.loc:t("entity_not_found", text:sub(1, 20))
                UIManager:show(InfoMessage:new{ text = err, timeout = 5 })
            end
        end)
    end)
end

function M:continueWithFetch(reading_percent, is_update, last_fetch_page, is_silent)
    self.bg_fetch_active = true
    if not self.ai_helper then
        local AIHelper = require(plugin_path .. "xray_aihelper")
        self.ai_helper = AIHelper
        self.ai_helper:init(self.path)
    end
    local props = self.ui.document:getProps() or {}
    local title = sanitizeMetadata(props.title)
    local author = sanitizeMetadata(props.authors)

    -- For manual (non-silent) fetches, show a ButtonDialog with a Cancel button.
    -- We use the async path for ALL fetches so we never need Trapper:dismissableRunInSubprocess
    -- (which requires an InfoMessage widget and breaks with ButtonDialog).
    local wait_msg
    local is_cancelled = false

    if not is_silent then
        local ButtonDialog = require("ui/widget/buttondialog")
        local fetch_text = is_update
            and (self.loc:t("updating_ai", self.ai_provider or "AI") or "Updating X-Ray...")
            or  (self.loc:t("fetching_ai",  self.ai_provider or "AI") or "Fetching X-Ray...")
        wait_msg = ButtonDialog:new{
            title = fetch_text,
            text  = title .. "\n\n" .. (self.loc:t("fetching_wait") or "This may take a moment.\nTap Cancel to stop."),
            buttons = {{{
                text = self.loc:t("cancel") or "Cancel",
                callback = function()
                    is_cancelled = true
                    self:log("XRayPlugin: Fetch cancelled by user (button pressed)")
                    if wait_msg then UIManager:close(wait_msg) end
                end
            }}}
        }
        UIManager:show(wait_msg)
    end

    UIManager:scheduleIn(0.5, function()
        if is_cancelled or self.destroyed then self.bg_fetch_active = false; return end
        if not self.chapter_analyzer then self.chapter_analyzer = require(plugin_path .. "xray_chapteranalyzer"):new() end

        local current_page = self.ui:getCurrentPage()
        local first_missing_page = last_fetch_page
        if is_update then
            local toc = self.ui.document:getToc() or {}
            local candidate_chapters = {}
            for i = #toc, 1, -1 do
                local entry = toc[i]
                if entry.page and entry.page <= current_page then
                    if not self:isNonNarrativeChapter(entry.title) then
                        table.insert(candidate_chapters, entry)
                        if #candidate_chapters >= 3 then break end
                    end
                end
            end
            for _, entry in ipairs(candidate_chapters) do
                local norm = self:normalizeChapterName(entry.title)
                local found = false
                for _, ev in ipairs(self.timeline or {}) do
                    if self:normalizeChapterName(ev.chapter or "") == norm then
                        if not ev.page or ev.page == entry.page then found = true; break end
                    end
                end
                if not found then
                    if not first_missing_page or entry.page < first_missing_page then
                        first_missing_page = entry.page
                        self:log("XRayPlugin: Repair mode active: recovering missing chapter '" .. tostring(entry.title) .. "' starting at page " .. tostring(entry.page))
                    end
                end
            end
        end

        local end_page_analysis = current_page
        local spoiler_setting = self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.spoiler_setting or "spoiler_free"
        if spoiler_setting ~= "full_book" then
            end_page_analysis = current_page + 1
        end
        local book_text = self.chapter_analyzer:getTextForAnalysis(self.ui, 20000, nil, end_page_analysis, first_missing_page)
        local known_chapters = {}
        if is_update and self.timeline then
            for _, ev in ipairs(self.timeline) do
                if ev.chapter then known_chapters[self:normalizeChapterName(ev.chapter)] = true end
            end
        end

        UIManager:scheduleIn(0, function()
            if is_cancelled or self.destroyed then self.bg_fetch_active = false; return end
            if not self.ui or not self.ui.document then self.bg_fetch_active = false; return end

            local samples, chapter_titles = self.chapter_analyzer:getDetailedChapterSamples(self.ui, 200, 150000, reading_percent == 100, first_missing_page, known_chapters)
            local annots = self.chapter_analyzer:getAnnotationsForAnalysis(self.ui)

            if (not book_text or #book_text < 10) and not samples then
                if wait_msg then UIManager:close(wait_msg) end
                if not is_silent then UIManager:show(InfoMessage:new{ text = self.loc:t("error_extract_text") or "Error: Could not extract book text.", timeout = 5 }) end
                self:log("XRayPlugin: Text extraction failed" .. (is_silent and " (silent)" or ""))
                self.bg_fetch_active = false
                return
            end

            local context = {
                reading_percent = reading_percent,
                spoiler_free = reading_percent < 100,
                filename = self.ui.document.file:match("([^/\\]+)$"),
                series = props.series or props.Series,
                chapter_samples = samples,
                chapter_titles = chapter_titles,
                annotations = annots,
                book_text = book_text,
                existing_characters = is_update and self.characters or nil,
                existing_locations = is_update and self.locations or nil,
                existing_historical_figures = is_update and self.historical_figures or nil,
                book_type = self.book_type,
            }

            local req_params, err_code, err_msg = self.ai_helper:buildComprehensiveRequest(title, author, context)
            if not req_params then
                if wait_msg then UIManager:close(wait_msg) end
                self:log("XRayPlugin: Failed to build request: " .. tostring(err_msg))
                self.bg_fetch_active = false
                if not is_silent then
                    local title, text = utils:getFriendlyError(err_code, err_msg, self.loc)
                    UIManager:show(ConfirmBox:new{
                        text = title .. "\n\n" .. text,
                        ok_text = self.loc:t("ok") or "OK",
                        cancel_text = nil
                    })
                end
                return
            end

            local DataStorage = require("datastorage")
            local settings_xray_dir = DataStorage:getSettingsDir() .. "/xray"

            -- Clean up any orphaned fetch files from previous cancelled/timed-out fetches in this session
            pcall(function()
                local ok, lfs = pcall(require, "libs/libkoreader-lfs")
                if not ok or type(lfs) ~= "table" then
                    ok, lfs = pcall(require, "lfs")
                end
                if ok and lfs and lfs.dir then
                    for file in lfs.dir(settings_xray_dir) do
                        if file:find("^bg_fetch_.*%.json$") then
                            os.remove(settings_xray_dir .. "/" .. file)
                        end
                    end
                end
            end)

            local result_file = settings_xray_dir .. "/bg_fetch_" .. tostring(os.time()) .. ".json"
            local started = self.ai_helper:makeRequestAsync(req_params, result_file)
            if not started then
                if wait_msg then UIManager:close(wait_msg) end
                self:log("XRayPlugin: Failed to start async fetch")
                self.bg_fetch_active = false
                return
            end

            local poll_count = 0
            local max_polls = 300 -- 10 minutes at 2s intervals
            local function poll()
                if is_cancelled or self.destroyed then
                    pcall(function() os.remove(result_file) end)
                    self.bg_fetch_active = false
                    self:log("XRayPlugin: Fetch cancelled or plugin destroyed")
                    return
                end
                if not self.ui or not self.ui.document then
                    pcall(function() os.remove(result_file) end)
                    self.bg_fetch_active = false
                    return
                end
                poll_count = poll_count + 1
                local data, p_err_code, p_err_msg = self.ai_helper:checkAsyncResult(result_file)
                if data == nil then
                    if poll_count < max_polls then
                        UIManager:scheduleIn(2, poll)
                    else
                        if wait_msg then UIManager:close(wait_msg) end
                        self.bg_fetch_active = false
                        self:log("XRayPlugin: Fetch timed out")
                        if not is_silent then
                            local title, text = utils:getFriendlyError("error_timeout", nil, self.loc)
                            UIManager:show(ConfirmBox:new{
                                text = title .. "\n\n" .. text,
                                ok_text = self.loc:t("ok") or "OK",
                                cancel_text = nil
                            })
                        end
                    end
                elseif data == false then
                    if wait_msg then UIManager:close(wait_msg) end
                    self.bg_fetch_active = false
                    self:log("XRayPlugin: Fetch failed: " .. tostring(p_err_msg))
                    if not is_silent then
                        local title, text = utils:getFriendlyError(p_err_code, p_err_msg, self.loc)
                        UIManager:show(ConfirmBox:new{
                            text = title .. "\n\n" .. text,
                            ok_text = self.loc:t("ok") or "OK",
                            cancel_text = nil
                        })
                    end
                else
                    if wait_msg then UIManager:close(wait_msg) end
                    self.bg_fetch_active = false
                    self:finalizeXRayData(data, title, author, book_text, is_update, is_silent, current_page)
                end
            end
            UIManager:scheduleIn(2, poll)
        end)
    end)
end


function M:finalizeXRayData(final_book_data, title, author, book_text, is_update, is_silent, current_page)
    final_book_data.book_title = title
    final_book_data.author = author

    -- Frequency Sorting
    final_book_data.characters = self:sortDataByFrequency(final_book_data.characters, book_text, "name")
    final_book_data.historical_figures = self:sortDataByFrequency(final_book_data.historical_figures, book_text, "name")
    final_book_data.locations = self:sortDataByFrequency(final_book_data.locations, book_text, "name")
    final_book_data.terms = self:deduplicateByName(final_book_data.terms or {}, "name")
    final_book_data.terms = self:sortDataByFrequency(final_book_data.terms, book_text, "name")

    -- Filter non-narrative timeline entries the AI may have hallucinated
    if final_book_data.timeline then
        local filtered_timeline = {}
        for _, ev in ipairs(final_book_data.timeline) do
            if not self:isNonNarrativeChapter(ev.chapter) then
                table.insert(filtered_timeline, ev)
            else
                self:log("XRayPlugin: Filtered non-narrative timeline entry: " .. tostring(ev.chapter))
            end
        end
        final_book_data.timeline = filtered_timeline
    end

    -- Guard: never overwrite existing data with an all-empty result
    local char_count = #(final_book_data.characters or {})
    local loc_count  = #(final_book_data.locations or {})
    local tl_count   = #(final_book_data.timeline or {})
    local hist_count = #(final_book_data.historical_figures or {})
    local term_count = #(final_book_data.terms or {})

    if char_count == 0 and loc_count == 0 and tl_count == 0 and hist_count == 0 and term_count == 0 then
        self:log("XRayPlugin: AI returned all-empty data — aborting cache write to protect existing data")
        if not is_silent then
            local msg = "The AI returned no data.\n\nThis usually means the book sample was too short. Try reading further into the book, then fetch again."
            UIManager:show(InfoMessage:new{ text = msg, timeout = 8 })
        end
        self.bg_fetch_active = false
        return  -- do NOT touch self.characters / self.locations / cache
    end

    -- Resolve current chapter title for history tracking
    local chapter_title = nil
    if self.ui and self.ui.document and current_page then
        local toc = self.ui.document:getToc()
        if toc then
            for _, entry in ipairs(toc) do
                if entry.page and entry.page <= current_page then
                    chapter_title = entry.title
                else
                    break
                end
            end
        end
    end

    if is_update then
        -- Ensure tables exist before attempting to merge/insert
        self.characters = self.characters or {}
        self.historical_figures = self.historical_figures or {}
        self.locations = self.locations or {}
        self.timeline = self.timeline or {}

        -- Merge characters
        for _, new_char in ipairs(final_book_data.characters or {}) do
            local found = false
            for _, existing_char in ipairs(self.characters) do
                if existing_char.name:lower() == new_char.name:lower() then
                    existing_char.role = new_char.role
                    -- Replace existing description with the AI's rewritten cohesive summary
                    if new_char.description and new_char.description ~= "" then
                        existing_char.description = new_char.description
                        
                        -- Record history
                        existing_char.history = existing_char.history or {}
                        local dup = false
                        for _, entry in ipairs(existing_char.history) do
                            if entry.page == current_page then
                                entry.description = new_char.description
                                entry.chapter = chapter_title or entry.chapter
                                dup = true
                                break
                            end
                        end
                        if not dup then
                            table.insert(existing_char.history, {
                                page = current_page,
                                chapter = chapter_title or "",
                                description = new_char.description
                            })
                        end
                    end
                    found = true
                    break
                end
            end
            if not found then
                if new_char.description and new_char.description ~= "" then
                    new_char.history = {
                        {
                            page = current_page,
                            chapter = chapter_title or "",
                            description = new_char.description
                        }
                    }
                end
                table.insert(self.characters, new_char)
            end
        end
        -- Dedup then re-sort the entire character list by frequency in the current context
        self.characters = self:deduplicateByName(self.characters, "name")
        if book_text and #book_text > 0 then
            self:sortDataByFrequency(self.characters, book_text, "name")
        end
        -- Merge historical figures
        for _, new_fig in ipairs(final_book_data.historical_figures or {}) do
            local found = false
            for _, existing_fig in ipairs(self.historical_figures or {}) do
                if existing_fig.name:lower() == new_fig.name:lower() then
                    if new_fig.biography and new_fig.biography ~= "" then
                        existing_fig.biography = new_fig.biography
                        
                        -- Record history
                        existing_fig.history = existing_fig.history or {}
                        local dup = false
                        for _, entry in ipairs(existing_fig.history) do
                            if entry.page == current_page then
                                entry.biography = new_fig.biography
                                entry.chapter = chapter_title or entry.chapter
                                dup = true
                                break
                            end
                        end
                        if not dup then
                            table.insert(existing_fig.history, {
                                page = current_page,
                                chapter = chapter_title or "",
                                biography = new_fig.biography
                            })
                        end
                    end
                    existing_fig.role = new_fig.role
                    found = true
                    break
                end
            end
            if not found then
                if new_fig.biography and new_fig.biography ~= "" then
                    new_fig.history = {
                        {
                            page = current_page,
                            chapter = chapter_title or "",
                            biography = new_fig.biography
                        }
                    }
                end
                table.insert(self.historical_figures, new_fig)
            end
        end
        self.historical_figures = self:deduplicateByName(self.historical_figures, "name")
        -- Merge locations
        for _, new_loc in ipairs(final_book_data.locations or {}) do
            local found = false
            for _, existing_loc in ipairs(self.locations or {}) do
                if existing_loc.name:lower() == new_loc.name:lower() then
                    if new_loc.description and new_loc.description ~= "" then
                        existing_loc.description = new_loc.description
                        
                        -- Record history
                        existing_loc.history = existing_loc.history or {}
                        local dup = false
                        for _, entry in ipairs(existing_loc.history) do
                            if entry.page == current_page then
                                entry.description = new_loc.description
                                entry.chapter = chapter_title or entry.chapter
                                dup = true
                                break
                            end
                        end
                        if not dup then
                            table.insert(existing_loc.history, {
                                page = current_page,
                                chapter = chapter_title or "",
                                description = new_loc.description
                            })
                        end
                    end
                    found = true
                    break
                end
            end
            if not found then
                if new_loc.description and new_loc.description ~= "" then
                    new_loc.history = {
                        {
                            page = current_page,
                            chapter = chapter_title or "",
                            description = new_loc.description
                        }
                    }
                end
                table.insert(self.locations, new_loc)
            end
        end
        self.locations = self:deduplicateByName(self.locations, "name")
        -- Merge terms
        self.terms = self.terms or {}
        for _, new_term in ipairs(final_book_data.terms or {}) do
            local found = false
            for _, existing in ipairs(self.terms) do
                if existing.name:lower() == new_term.name:lower() then
                    if new_term.definition and new_term.definition ~= "" then
                        existing.definition = new_term.definition
                    end
                    existing.expanded = new_term.expanded
                    existing.aliases = new_term.aliases
                    found = true; break
                end
            end
            if not found then table.insert(self.terms, new_term) end
        end
        self.terms = self:deduplicateByName(self.terms, "name")
        if book_text and #book_text > 0 then
            self:sortDataByFrequency(self.terms, book_text, "name")
        end
        -- Merge book_type
        if final_book_data.book_type then
            self.book_type = final_book_data.book_type
        end
        -- Merge timeline: duplicate = same chapter name AND same page.
        local toc = self.ui.document:getToc()
        -- Assign TOC pages to incoming events before dedup check.
        self:assignTimelinePages(final_book_data.timeline or {}, toc, true)
        for _, new_event in ipairs(final_book_data.timeline or {}) do
            local found = false
            local new_norm = self:normalizeChapterName(new_event.chapter or "")
            for _, existing_event in ipairs(self.timeline or {}) do
                local exist_norm = self:normalizeChapterName(existing_event.chapter or "")
                if new_norm == exist_norm then
                    -- Both pages must be present and equal to count as a duplicate
                    if new_event.page and existing_event.page and
                       tonumber(new_event.page) == tonumber(existing_event.page) then
                        found = true
                        break
                    end
                end
            end
            if not found then table.insert(self.timeline, new_event) end
        end
        -- Sort the merged timeline chronologically
        self:sortTimelineByTOC(self.timeline)
    else
        self.characters = final_book_data.characters
        for _, char in ipairs(self.characters or {}) do
            if char.description and char.description ~= "" then
                char.history = char.history or {
                    {
                        page = current_page,
                        chapter = chapter_title or "",
                        description = char.description
                    }
                }
            end
        end
        self.historical_figures = final_book_data.historical_figures
        for _, fig in ipairs(self.historical_figures or {}) do
            if fig.biography and fig.biography ~= "" then
                fig.history = fig.history or {
                    {
                        page = current_page,
                        chapter = chapter_title or "",
                        biography = fig.biography
                    }
                }
            end
        end
        self.locations = final_book_data.locations
        for _, loc in ipairs(self.locations or {}) do
            if loc.description and loc.description ~= "" then
                loc.history = loc.history or {
                    {
                        page = current_page,
                        chapter = chapter_title or "",
                        description = loc.description
                    }
                }
            end
        end
        self.terms = final_book_data.terms or {}
        self.book_type = final_book_data.book_type
        self.timeline = final_book_data.timeline
        -- Assign TOC pages and sort
        local toc = self.ui.document:getToc()
        self:assignTimelinePages(self.timeline or {}, toc, true)
        self:sortTimelineByTOC(self.timeline)
    end

    -- If we don't have author info in memory, check if the cache already has it
    if not self.author_info then
        if not self.cache_manager then self.cache_manager = require(plugin_path .. "xray_cachemanager"):new() end
        local existing = self.book_data or self.cache_manager:loadCache(self.ui.document.file)
        if existing and existing.author_info then
            self.author_info = existing.author_info
        end
    end

    if not self.book_data then
        self.book_data = self.cache_manager:loadCache(self.ui.document.file) or {}
    end
    local updated_data = self.book_data
    updated_data.book_title = title
    updated_data.author = author
    updated_data.characters = self.characters
    updated_data.historical_figures = self.historical_figures
    updated_data.locations = self.locations
    updated_data.terms = self.terms
    updated_data.book_type = self.book_type or updated_data.book_type
    updated_data.timeline = self.timeline
    updated_data.author_info = self.author_info or updated_data.author_info
    updated_data.last_fetch_page = current_page
    
    self.book_data = updated_data

    if not self.cache_manager then self.cache_manager = require(plugin_path .. "xray_cachemanager"):new() end
    local cache_saved = self.cache_manager:asyncSaveCache(self.ui.document.file, updated_data)

    UIManager:scheduleIn(1, function()
        if self.destroyed then return end
        local reading_percent = 100
        if self.ui and self.ui.document and self.ui.document.getPageCount and current_page then
            local page_count = self.ui.document:getPageCount()
            if page_count and page_count > 0 then
                reading_percent = math.floor((current_page / page_count) * 100)
            end
        end
        local spoiler_setting = self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.spoiler_setting or "spoiler_free"
        if spoiler_setting == "full_book" then reading_percent = 100 end
        self:runPostFetchDuplicateCheck(title, author, reading_percent, is_silent)
    end)

    if is_silent then
        self:log(string.format("XRayPlugin: Silent merge complete - Chars: %d, Locs: %d, Events: %d, Cache: %s",
            #self.characters, #self.locations, #self.timeline,
            cache_saved and "saved" or "failed"))
    else
        local fetch_complete = self.loc:t("ai_fetch_complete_msg") or "AI Fetch Complete!"
        local cache_success = self.loc:t("cache_save_success") or "✓ Cache updated."
        local cache_fail = self.loc:t("cache_save_failed") or "✗ Cache failed."
        local summary = string.format("%s\n\nCharacters: %d\nLocations: %d\nEvents: %d\n\n%s", 
            fetch_complete, #self.characters, #self.locations, #self.timeline,
            cache_saved and cache_success or cache_fail)

        local success_dialog
        local ButtonDialog = require("ui/widget/buttondialog")
        success_dialog = ButtonDialog:new{ title = (self.loc:t("fetch_successful") or "Fetch successful") .. "\n\n" .. summary, buttons = {{{ text = self.loc:t("ok"), callback = function() 
            UIManager:close(success_dialog) 
        end }}} }
        UIManager:show(success_dialog)
    end

end

function M:runPostFetchDuplicateCheck(title, author, reading_percent, is_silent)
    if not self.ai_helper or not self.ai_helper.hasApiKey or not self.ai_helper:hasApiKey() then return end
    if self.ai_helper.settings and self.ai_helper.settings.auto_dupe_check_enabled == false then return end

    local DataStorage = require("datastorage")
    local settings_xray_dir = DataStorage:getSettingsDir() .. "/xray"

    -- Run checks for characters and locations in sequence using async subprocesses
    local function checkListAsync(list, list_name, entity_label, on_done)
        if not list or #list < 2 then on_done(nil); return end
        
        local unique_id = tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))
        local result_file = settings_xray_dir .. "/dupe_res_" .. list_name .. "_" .. unique_id .. ".json"
        
        self:log("XRayPlugin: Starting async duplicate check for " .. list_name)
        local pid = self.ai_helper:findDuplicatesAsync(title, author, list, entity_label, reading_percent, result_file)
        if not pid then
            self:log("XRayPlugin: Failed to start async duplicate check for " .. list_name)
            on_done(nil)
            return
        end
        
        local poll_count = 0
        local max_polls = 150 -- 5 minutes at 2s intervals
        local function poll()
            if self.destroyed then
                pcall(function() os.remove(result_file) end)
                return
            end
            poll_count = poll_count + 1
            local data, p_err_code, p_err_msg = self.ai_helper:checkAsyncResult(result_file)
            if data == nil then
                if poll_count < max_polls then
                    UIManager:scheduleIn(2, poll)
                else
                    self:log("XRayPlugin: Async duplicate check for " .. list_name .. " timed out")
                    pcall(function() os.remove(result_file) end)
                    on_done(nil)
                end
            elseif data == false then
                self:log("XRayPlugin: Async duplicate check for " .. list_name .. " failed: " .. tostring(p_err_msg))
                on_done(nil)
            else
                self:log("XRayPlugin: Async duplicate check for " .. list_name .. " succeeded")
                local pairs_found = data.duplicate_pairs or data.DuplicatePairs
                on_done(pairs_found)
            end
        end
        UIManager:scheduleIn(2, poll)
    end

    checkListAsync(self.characters, "characters",
        self.loc:t("entity_label_characters") or "characters",
        function(char_pairs)
            checkListAsync(self.locations, "locations",
                self.loc:t("entity_label_locations") or "locations",
                function(loc_pairs)
                    local has_chars = char_pairs and #char_pairs > 0
                    local has_locs  = loc_pairs  and #loc_pairs  > 0

                    if not has_chars and not has_locs then return end

                    if is_silent then
                        self.pending_duplicate_review = {
                            characters = char_pairs,
                            locations  = loc_pairs,
                        }
                        self:log("XRayPlugin: Stored " .. tostring(has_chars and #char_pairs or 0) .. " char and " .. tostring(has_locs and #loc_pairs or 0) .. " loc duplicate pairs for later review")
                    else
                        UIManager:scheduleIn(0.5, function()
                            if self.destroyed then return end
                            if has_chars then
                                self:showAIFindDuplicatesFlow(self.characters, "characters",
                                    self.loc:t("entity_label_characters") or "characters")
                            elseif has_locs then
                                self:showAIFindDuplicatesFlow(self.locations, "locations",
                                    self.loc:t("entity_label_locations") or "locations")
                            end
                        end)
                    end
                end
            )
        end
    )
end

function M:fetchMoreCharacters()
    require("ui/network/manager"):runWhenOnline(function() 
        if not self.ai_helper then
            local AIHelper = require(plugin_path .. "xray_aihelper")
            self.ai_helper = AIHelper
            self.ai_helper:init(self.path)
        end
        local props = self.ui.document:getProps() or {}
        local title = sanitizeMetadata(props.title)
        local author = sanitizeMetadata(props.authors)
        local current_page = self.ui:getCurrentPage()
        local reading_percent = math.floor((current_page / self.ui.document:getPageCount()) * 100)
        local spoiler_setting = self.ai_helper.settings and self.ai_helper.settings.spoiler_setting or "spoiler_free"
        
        if spoiler_setting == "full_book" then
            reading_percent = 100
        end
        
        local menu_to_close = self.char_menu
        self.char_menu = nil

        local wait_msg
        local is_cancelled = false
        local ButtonDialog = require("ui/widget/buttondialog")
        wait_msg = ButtonDialog:new{
            title = (self.loc:t("fetching_ai") or "Fetching AI...") .. "\n\n" .. (self.loc:t("extracting_more_characters") or "Extracting additional characters...") .. "\n\n" .. title,
            buttons = {{{
                text = self.loc:t("cancel") or "Cancel",
                callback = function()
                    is_cancelled = true
                    if wait_msg then UIManager:close(wait_msg) end
                end
            }}}
        }
        UIManager:show(wait_msg)
        
        UIManager:scheduleIn(0.5, function()
            if is_cancelled or self.destroyed then return end
            if not self.chapter_analyzer then self.chapter_analyzer = require(plugin_path .. "xray_chapteranalyzer"):new() end
            
            -- EVEN SAMPLING: Divide the readable range into equal segments
            local current_page = self.ui:getCurrentPage()
            local pages_per_sample = 20
            local chars_per_sample = 10000
            local num_samples = 6
            
            -- Track call count to shift windows on each invocation
            self.more_chars_call_count = (self.more_chars_call_count or 0) + 1
            local call_num = self.more_chars_call_count
            local offset = (call_num - 1) * pages_per_sample
            self:log("XRayPlugin: More chars call #" .. call_num .. " (offset: " .. offset .. " pages)")
            
            -- Divide readable range into equal segments
            local readable_pages = math.max(1, current_page)
            local segment_size = math.floor(readable_pages / num_samples)
            if segment_size < pages_per_sample then segment_size = pages_per_sample end
            
            local text_parts = {}
            for i = 0, num_samples - 1 do
                local segment_start = i * segment_size
                local sample_start = math.min(segment_start + offset, readable_pages - pages_per_sample)
                sample_start = math.max(1, sample_start)
                
                -- Wrap around within the segment if the offset pushes past the segment boundary
                local segment_end = (i + 1) * segment_size
                if sample_start >= segment_end and i < num_samples - 1 then
                    sample_start = segment_start + ((offset) % segment_size)
                    sample_start = math.max(1, math.min(sample_start, readable_pages - pages_per_sample))
                end
                
                if sample_start <= current_page then
                    local end_page = math.min(sample_start + pages_per_sample, current_page)
                    local sample = self.chapter_analyzer:getTextFromPageRange(self.ui, sample_start, end_page, chars_per_sample)
                    if sample and #sample > 100 then
                        table.insert(text_parts, "[SECTION " .. (i + 1) .. "]\n" .. sample)
                        self:log("XRayPlugin: More chars sample " .. (i + 1) .. " pages " .. sample_start .. "-" .. end_page .. ": " .. #sample .. " chars")
                    end
                end
            end
            local book_text = table.concat(text_parts, "\n\n---\n\n")
            
            local exclude_list = {}
            for _, char in ipairs(self.characters or {}) do
                table.insert(exclude_list, char.name)
            end
            
            local context = { 
                reading_percent = reading_percent, 
                filename = self.ui.document.file:match("([^/\\]+)$"), 
                series = props.series or props.Series, 
                book_text = book_text,
                exclude_characters = table.concat(exclude_list, ", ")
            }
            
            self.ai_helper:setTrapWidget(wait_msg)
            local more_data, error_code, error_msg = self.ai_helper:getMoreCharacters(title, author, nil, context)
            self.ai_helper:resetTrapWidget()
            
            if wait_msg then UIManager:close(wait_msg) end
            if is_cancelled or error_code == "USER_CANCELLED" then return end
            
            if not more_data or not more_data.characters then
                local title, text = utils:getFriendlyError(error_code, error_msg, self.loc)
                UIManager:show(ConfirmBox:new{
                    text = title .. "\n\n" .. text,
                    ok_text = self.loc:t("ok") or "OK",
                    cancel_text = nil
                })
                return
            end
            
            local new_count = 0
            for _, new_char in ipairs(more_data.characters) do
                local found = false
                for _, existing_char in ipairs(self.characters or {}) do
                    if existing_char.name:lower() == new_char.name:lower() then
                        found = true
                        break
                    end
                end
                if not found then
                    table.insert(self.characters, new_char)
                    new_count = new_count + 1
                end
            end
            
            -- Re-sort by frequency based on the newly extracted samples
            if book_text and #book_text > 0 then
                self:sortDataByFrequency(self.characters, book_text, "name")
            end
            
            -- Save to cache
            if not self.cache_manager then self.cache_manager = require(plugin_path .. "xray_cachemanager"):new() end
            if not self.book_data then
                self.book_data = self.cache_manager:loadCache(self.ui.document.file) or {}
            end
            local updated_data = self.book_data
            updated_data.book_title = title
            updated_data.author = author
            updated_data.characters = self.characters
            updated_data.historical_figures = self.historical_figures
            updated_data.locations = self.locations
            updated_data.terms = self.terms or updated_data.terms
            updated_data.book_type = self.book_type or updated_data.book_type
            updated_data.timeline = self.timeline or updated_data.timeline
            updated_data.author_info = self.author_info or updated_data.author_info
            
            self.cache_manager:asyncSaveCache(self.ui.document.file, updated_data)

            local current_page = self.ui and self.ui.getCurrentPage and self.ui:getCurrentPage() or 1
            local total_pages = self.ui and self.ui.document and self.ui.document.getPageCount and self.ui.document:getPageCount() or 1
            local reading_percent = total_pages and total_pages > 0 and math.floor((current_page / total_pages) * 100) or 100
            local spoiler_setting = self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.spoiler_setting or "spoiler_free"
            if spoiler_setting == "full_book" then reading_percent = 100 end

            UIManager:scheduleIn(0.5, function()
                if self.destroyed then return end
                self:runPostFetchDuplicateCheck(title, author, reading_percent, false)
            end)
            
            local added_msg = self.loc:t("msg_added_characters", new_count)
            UIManager:show(InfoMessage:new{ text = added_msg, timeout = 3 })

            if menu_to_close then
                UIManager:close(menu_to_close)
            end
            self:showCharacters()
        end)
    end)
end

function M:fetchMoreTerms()
    require("ui/network/manager"):runWhenOnline(function()
        if not self.ai_helper then
            local AIHelper = require(plugin_path .. "xray_aihelper")
            self.ai_helper = AIHelper
            self.ai_helper:init(self.path)
        end
        if not self.ai_helper:hasApiKey() then
            UIManager:show(InfoMessage:new{ text = self.loc:t("error_no_api_key"), timeout = 5 })
            return
        end

        local props = self.ui.document:getProps() or {}
        local title = sanitizeMetadata(props.title)
        local author = sanitizeMetadata(props.authors)
        local current_page = self.ui:getCurrentPage()
        local reading_percent = math.floor((current_page / self.ui.document:getPageCount()) * 100)
        local menu_to_close = self.terms_menu
        self.terms_menu = nil
        local is_cancelled = false
        local ButtonDialog = require("ui/widget/buttondialog")

        local wait_msg = ButtonDialog:new{
            title = (self.loc:t("fetching_ai") or "Fetching AI...") .. "\n\n" .. (self.loc:t("extracting_more_terms") or "Extracting additional terms...") .. "\n\n" .. title,
            buttons = {{{
                text = self.loc:t("cancel") or "Cancel",
                callback = function()
                    is_cancelled = true
                    if wait_msg then UIManager:close(wait_msg) end
                end
            }}}
        }
        UIManager:show(wait_msg)
        
        UIManager:scheduleIn(0.5, function()
            if is_cancelled or self.destroyed then return end
            if not self.chapter_analyzer then self.chapter_analyzer = require(plugin_path .. "xray_chapteranalyzer"):new() end
            
            local pages_per_sample = 20
            local chars_per_sample = 10000
            local num_samples = 6
            
            self.more_terms_call_count = (self.more_terms_call_count or 0) + 1
            local call_num = self.more_terms_call_count
            local offset = (call_num - 1) * pages_per_sample
            
            local readable_pages = math.max(1, current_page)
            local segment_size = math.floor(readable_pages / num_samples)
            if segment_size < pages_per_sample then segment_size = pages_per_sample end
            
            local text_parts = {}
            for i = 0, num_samples - 1 do
                local segment_start = i * segment_size
                local sample_start = math.min(segment_start + offset, readable_pages - pages_per_sample)
                sample_start = math.max(1, sample_start)
                if sample_start <= current_page then
                    local end_page = math.min(sample_start + pages_per_sample, current_page)
                    local sample = self.chapter_analyzer:getTextFromPageRange(self.ui, sample_start, end_page, chars_per_sample)
                    if sample and #sample > 100 then
                        table.insert(text_parts, "[SECTION " .. (i + 1) .. "]\n" .. sample)
                    end
                end
            end
            local book_text = table.concat(text_parts, "\n\n")

            self.terms = self.terms or {}
            local exclude_list = {}
            for _, term in ipairs(self.terms) do
                table.insert(exclude_list, term.name)
            end
            local exclude_str = #exclude_list > 0 and table.concat(exclude_list, ", ") or "None"

            local context = {
                exclude_terms = exclude_str,
                reading_percent = reading_percent,
                book_text = book_text
            }

            self.ai_helper:setTrapWidget(wait_msg)
            local more_data, error_code, error_msg = self.ai_helper:getMoreTerms(title, author, nil, context)
            self.ai_helper:resetTrapWidget()

            if wait_msg then UIManager:close(wait_msg) end
            if is_cancelled or error_code == "USER_CANCELLED" then return end
            
            if not more_data or not more_data.terms then
                local err_title, err_text = utils:getFriendlyError(error_code, error_msg, self.loc)
                UIManager:show(ConfirmBox:new{
                    text = err_title .. "\n\n" .. err_text,
                    ok_text = self.loc:t("ok") or "OK",
                    cancel_text = nil
                })
                return
            end
            
            local new_count = 0
            for _, new_term in ipairs(more_data.terms) do
                local found = false
                for _, existing in ipairs(self.terms) do
                    if existing.name:lower() == new_term.name:lower() then
                        found = true; break
                    end
                end
                if not found then
                    table.insert(self.terms, new_term)
                    new_count = new_count + 1
                end
            end
            
            self.terms = self:deduplicateByName(self.terms, "name")
            if book_text and #book_text > 0 then
                self:sortDataByFrequency(self.terms, book_text, "name")
            end
            
            if not self.cache_manager then self.cache_manager = require(plugin_path .. "xray_cachemanager"):new() end
            if not self.book_data then
                self.book_data = self.cache_manager:loadCache(self.ui.document.file) or {}
            end
            local updated_data = self.book_data
            updated_data.book_title = title
            updated_data.author = author
            updated_data.characters = self.characters
            updated_data.historical_figures = self.historical_figures
            updated_data.locations = self.locations
            updated_data.terms = self.terms
            updated_data.book_type = self.book_type or updated_data.book_type
            updated_data.timeline = self.timeline or updated_data.timeline
            updated_data.author_info = self.author_info or updated_data.author_info
            
            self.cache_manager:asyncSaveCache(self.ui.document.file, updated_data)
            
            local added_msg = self.loc:t("msg_added_terms", new_count)
            UIManager:show(InfoMessage:new{ text = added_msg, timeout = 3 })

            if menu_to_close then UIManager:close(menu_to_close) end
            self:showTerms()
        end)
    end)
end

function M:fetchAuthorInfo()
    if not self.ai_helper then
        local AIHelper = require(plugin_path .. "xray_aihelper")
        self.ai_helper = AIHelper
        self.ai_helper:init(self.path)
    end
    local props = self.ui.document:getProps() or {}
    local title = sanitizeMetadata(props.title)
    local author = sanitizeMetadata(props.authors)
    local wait_msg
    local is_cancelled = false
    local ButtonDialog = require("ui/widget/buttondialog")
    wait_msg = ButtonDialog:new{
        title = (self.loc:t("fetching_author", "AI") or "Fetching Author...") .. "\n\n" .. title .. " - " .. author,
        buttons = {{{
            text = self.loc:t("cancel") or "Cancel",
            callback = function()
                is_cancelled = true
                if wait_msg then UIManager:close(wait_msg) end
            end
        }}}
    }
    UIManager:show(wait_msg)
    UIManager:scheduleIn(0.5, function()
        if is_cancelled or self.destroyed then return end
        
        if not self.chapter_analyzer then
            local ChapterAnalyzer = require(plugin_path .. "xray_chapteranalyzer")
            self.chapter_analyzer = ChapterAnalyzer:new()
        end
        local book_text = self.chapter_analyzer:getTextForAnalysis(self.ui, 1000, nil, self.ui:getCurrentPage())
        local context = { book_text = book_text }
        
        self.ai_helper:setTrapWidget(wait_msg)
        local author_data, error_code, error_msg = self.ai_helper:getAuthorData(title, author, nil, context)
        self.ai_helper:resetTrapWidget()
        
        if wait_msg then UIManager:close(wait_msg) end
        if is_cancelled or error_code == "USER_CANCELLED" then return end

        if not author_data then
            local title, text = utils:getFriendlyError(error_code, error_msg, self.loc)
            UIManager:show(ConfirmBox:new{
                text = title .. "\n\n" .. text,
                ok_text = self.loc:t("ok") or "OK",
                cancel_text = nil
            })
            return
        end
        self.author_info = { 
            name = sanitizeMetadata(author_data.author or author), 
            description = sanitizeMetadata(author_data.author_bio or self.loc:t("msg_no_bio") or "No biography available."), 
            birthDate = sanitizeMetadata(author_data.author_birth or "---"), 
            deathDate = sanitizeMetadata(author_data.author_death or "---") 
        }
        if not self.cache_manager then self.cache_manager = require(plugin_path .. "xray_cachemanager"):new() end
        if not self.book_data then
            self.book_data = self.cache_manager:loadCache(self.ui.document.file) or {}
        end
        local cache = self.book_data
        cache.author_info = self.author_info
        cache.author = self.author_info.name
        cache.author_bio = self.author_info.description
        cache.author_birth = self.author_info.birthDate
        cache.author_death = self.author_info.deathDate
        
        -- Store book_type if AI detected it during author fetch
        if author_data.book_type then
            cache.book_type = author_data.book_type
            self.book_type = author_data.book_type
        end
        
        self.cache_manager:asyncSaveCache(self.ui.document.file, cache)
        self:showAuthorInfo()
    end)
end

function M:checkWeeklyUpdate()
    if not self.ai_helper or not self.ai_helper.settings then return end
    
    local last_check = self.ai_helper.settings.last_update_check or 0
    local now = os.time()
    local week_seconds = 7 * 24 * 60 * 60
    
    if (now - last_check) > week_seconds then
        local NetworkMgr = require("ui/network/manager")
        if NetworkMgr:isConnected() and NetworkMgr:isOnline() then
            self:log("XRayPlugin: Triggering weekly silent update check")
            self.ai_helper:saveSettings({ last_update_check = now })
            local updater = require(plugin_path .. "xray_updater")
            updater.checkSilentForUpdates(self.loc, self.ai_helper.settings.beta_channel_enabled)
        else
            self:log("XRayPlugin: Skipping weekly update check (offline)")
        end
    end
end

function M:mergeSeriesContext(cache_data, series_info)
    if not cache_data or not series_info then return end

    local function filterPrior(tbl)
        local filtered = {}
        for _, item in ipairs(tbl or {}) do
            if item.source ~= "series_prior" then
                table.insert(filtered, item)
            end
        end
        return filtered
    end

    self.characters = filterPrior(self.characters)
    self.locations = filterPrior(self.locations)
    self.terms = filterPrior(self.terms)
    self.timeline = filterPrior(self.timeline)

    for idx = 1, series_info.index - 1 do
        local book_data = cache_data.books and cache_data.books[idx]
        if book_data then
            for _, new_char in ipairs(book_data.characters or {}) do
                local found = false
                local lower_name = new_char.name:lower()
                for _, existing_char in ipairs(self.characters) do
                    local matches = false
                    if existing_char.name:lower() == lower_name then
                        matches = true
                    else
                        for _, alias in ipairs(existing_char.aliases or {}) do
                            if alias:lower() == lower_name then
                                matches = true
                                break
                            end
                        end
                    end
                    
                    if matches then
                        found = true
                        local prefix = string.format("[From Book %d] ", idx)
                        if new_char.description and new_char.description ~= "" then
                            if not existing_char.description:find(prefix, 1, true) then
                                existing_char.description = prefix .. new_char.description .. "\n\n" .. existing_char.description
                            end
                        end
                        break
                    end
                end
                
                if not found then
                    local char_copy = {}
                    for k, v in pairs(new_char) do char_copy[k] = v end
                    char_copy.source = "series_prior"
                    char_copy.source_book = idx
                    table.insert(self.characters, char_copy)
                end
            end

            for _, new_loc in ipairs(book_data.locations or {}) do
                local found = false
                local lower_name = new_loc.name:lower()
                for _, existing_loc in ipairs(self.locations) do
                    if existing_loc.name:lower() == lower_name then
                        found = true
                        local prefix = string.format("[From Book %d] ", idx)
                        if new_loc.description and new_loc.description ~= "" then
                            if not existing_loc.description:find(prefix, 1, true) then
                                existing_loc.description = prefix .. new_loc.description .. "\n\n" .. existing_loc.description
                            end
                        end
                        break
                    end
                end
                if not found then
                    local loc_copy = {}
                    for k, v in pairs(new_loc) do loc_copy[k] = v end
                    loc_copy.source = "series_prior"
                    loc_copy.source_book = idx
                    table.insert(self.locations, loc_copy)
                end
            end

            for _, new_term in ipairs(book_data.terms or {}) do
                local found = false
                local lower_name = new_term.name:lower()
                for _, existing_term in ipairs(self.terms) do
                    if existing_term.name:lower() == lower_name then
                        found = true
                        local prefix = string.format("[From Book %d] ", idx)
                        if new_term.definition and new_term.definition ~= "" then
                            if not existing_term.definition:find(prefix, 1, true) then
                                existing_term.definition = prefix .. new_term.definition .. "\n\n" .. existing_term.definition
                            end
                        end
                        break
                    end
                end
                if not found then
                    local term_copy = {}
                    for k, v in pairs(new_term) do term_copy[k] = v end
                    term_copy.source = "series_prior"
                    term_copy.source_book = idx
                    table.insert(self.terms, term_copy)
                end
            end

            local events = {}
            for _, new_event in ipairs(book_data.timeline or {}) do
                if new_event.event and new_event.event ~= "" then
                    table.insert(events, new_event.event)
                end
            end
            if #events > 0 then
                local book_title = book_data.title or (cache_data.books and cache_data.books[idx] and cache_data.books[idx].title) or ""
                local label
                if book_title and book_title ~= "" then
                    label = string.format("[Book %d: %s]", idx, book_title)
                else
                    label = string.format("[Book %d]", idx)
                end
                local consolidated_event = table.concat(events, "\n\n")
                local ev_copy = {
                    chapter = label,
                    event = consolidated_event,
                    page = -1000 + idx,
                    source = "series_prior",
                    source_book = idx
                }
                table.insert(self.timeline, ev_copy)
            end
        end
    end

    local toc = self.ui.document:getToc() or {}
    self:assignTimelinePages(self.timeline, toc, true)
    self:sortTimelineByTOC(self.timeline)

    self.series_context_loaded = true
    if not self.cache_manager then
        self.cache_manager = require(plugin_path .. "xray_cachemanager"):new()
    end
    local book_path = self.ui.document.file
    if not self.book_data then
        self.book_data = self.cache_manager:loadCache(book_path) or {}
    end
    local cache = self.book_data
    cache.series_context_loaded = true
    cache.series_slug = series_info.slug
    cache.characters = self.characters
    cache.locations = self.locations
    cache.terms = self.terms
    cache.timeline = self.timeline
    self.cache_manager:asyncSaveCache(book_path, cache)
    self.book_data = cache
end

function M:fetchSeriesContext(is_silent, init_wait_dialog, cancel_ref)
    local function closeInitWait()
        if init_wait_dialog then
            UIManager:close(init_wait_dialog)
            init_wait_dialog = nil
        end
    end

    if cancel_ref and cancel_ref.cancelled then
        self:log("XRayPlugin: Series: fetchSeriesContext early exit: cancel_ref is cancelled")
        closeInitWait()
        return
    end

    if not self.ui or not self.ui.document then
        self:log("XRayPlugin: Series: fetchSeriesContext called with no document/ui, aborting")
        closeInitWait()
        return
    end

    if not self.ai_helper or not self.ai_helper.settings or not self.ai_helper.settings.series_context_enabled then
        self:log("XRayPlugin: Series: fetchSeriesContext early exit: setting series_context_enabled is false or nil")
        closeInitWait()
        return
    end

    local props = self.ui.document:getProps() or {}
    local title = sanitizeMetadata(props.title)
    local author = sanitizeMetadata(props.authors)

    self:log("XRayPlugin: Series: fetchSeriesContext starting for: title=" .. tostring(title) .. ", author=" .. tostring(author))

    local series_info = self.series_manager:detectSeries(props, title, author, self.ai_helper)
    if cancel_ref and cancel_ref.cancelled then
        self:log("XRayPlugin: Series: fetchSeriesContext cancelled after detectSeries")
        closeInitWait()
        return
    end

    if not series_info or not series_info.name or not series_info.index or series_info.index <= 1 then
        self:log("XRayPlugin: Series: No series detected or current book is the first one in the series. series_info=" .. (series_info and ("name=" .. tostring(series_info.name) .. ", index=" .. tostring(series_info.index)) or "nil"))
        closeInitWait()
        if not is_silent then
            UIManager:show(InfoMessage:new{
                text = self.loc:t("series_no_prior_detected") or "No prior books detected for this series.",
                timeout = 5
            })
        end
        return
    end

    local slug = series_info.slug
    self:log("XRayPlugin: Series: Detected series=" .. series_info.name .. ", index=" .. tostring(series_info.index) .. ", slug=" .. tostring(slug))

    local cache_data = self.series_manager:loadSeriesCache(slug) or { books = {} }
    cache_data.books = cache_data.books or {}

    local prior_books = self.series_manager:getPriorBookList(series_info, author, self.ai_helper)
    if cancel_ref and cancel_ref.cancelled then
        self:log("XRayPlugin: Series: fetchSeriesContext cancelled after getPriorBookList")
        closeInitWait()
        return
    end

    if #prior_books == 0 then
        self:log("XRayPlugin: Series: getPriorBookList returned empty list, using generated placeholders")
        for i = 1, series_info.index - 1 do
            table.insert(prior_books, {
                index = i,
                title = string.format("%s (Book %d)", series_info.name, i),
                author = author or "Unknown Author"
            })
        end
    else
        self:log("XRayPlugin: Series: getPriorBookList returned " .. tostring(#prior_books) .. " prior books")
    end

    local missing_books = {}
    for _, book in ipairs(prior_books) do
        local idx = book.index
        if not cache_data.books[idx] then
            self:log("XRayPlugin: Series: Cache MISS for book index " .. tostring(idx) .. ": " .. tostring(book.title))
            table.insert(missing_books, book)
        else
            self:log("XRayPlugin: Series: Cache HIT for book index " .. tostring(idx) .. ": " .. tostring(book.title))
        end
    end

    if #missing_books == 0 then
        self:log("XRayPlugin: Series: All prior books are already cached. Merging context immediately.")
        closeInitWait()
        self:mergeSeriesContext(cache_data, series_info)
        if not is_silent then
            local count = series_info.index - 1
            local loaded_msg = self.loc:t("series_context_loaded", count)
            UIManager:show(InfoMessage:new{
                text = loaded_msg,
                timeout = 5
            })
        end
        return
    end

    self:log("XRayPlugin: Series: Needs to fetch " .. tostring(#missing_books) .. " missing books from AI. Running when online.")

    require("ui/network/manager"):runWhenOnline(function()
        closeInitWait()
        if cancel_ref and cancel_ref.cancelled then
            self:log("XRayPlugin: Series: runWhenOnline fired after user cancelled")
            return
        end
        local is_cancelled = cancel_ref and cancel_ref.cancelled or false
        local wait_msg

        local function showProgress(current_idx, total_count, book_title)
            if is_silent then return end
            closeInitWait()
            if wait_msg then UIManager:close(wait_msg) end

            local progress_text = self.loc:t("fetching_series_context", current_idx, total_count)
            wait_msg = ButtonDialog:new{
                title = progress_text .. "\n\n" .. book_title .. "\n\n" .. (self.loc:t("fetching_wait") or "This may take a moment.\nTap Cancel to stop."),
                buttons = {{{
                    text = self.loc:t("cancel") or "Cancel",
                    callback = function()
                        is_cancelled = true
                        self:log("XRayPlugin: Series: User tapped Cancel on progress dialog.")
                        if wait_msg then UIManager:close(wait_msg) end
                    end
                }}}
            }
            UIManager:show(wait_msg)
        end

        local function fetchNext(step_idx)
            if is_cancelled then
                self:log("XRayPlugin: Series: fetch series context cancelled by user.")
                return
            end

            if step_idx > #missing_books then
                self:log("XRayPlugin: Series: All missing books fetched. Saving series cache and merging context.")
                if wait_msg then UIManager:close(wait_msg) end
                self.series_manager:saveSeriesCache(slug, cache_data)
                self:mergeSeriesContext(cache_data, series_info)

                if not is_silent then
                    local count = series_info.index - 1
                    local loaded_msg = self.loc:t("series_context_loaded", count)
                    UIManager:show(InfoMessage:new{
                        text = loaded_msg,
                        timeout = 5
                    })
                end
                return
            end

            local current_book = missing_books[step_idx]
            self:log("XRayPlugin: Series: Fetching AI context for book " .. tostring(current_book.index) .. " (" .. tostring(step_idx) .. "/" .. tostring(#missing_books) .. "): " .. tostring(current_book.title))
            showProgress(step_idx, #missing_books, current_book.title)

            UIManager:scheduleIn(0.5, function()
                if is_cancelled or self.destroyed then return end

                local context = {
                    series_name = series_info.name,
                    index = current_book.index
                }
                local prompt = self.ai_helper:createPrompt(current_book.title, current_book.author or author, context, "series_book_summary")
                
                self.ai_helper:setTrapWidget(wait_msg)
                local result, err_code, err_msg = self.ai_helper:executeUnifiedRequest(prompt)
                self.ai_helper:resetTrapWidget()

                if is_cancelled then return end

                if not result then
                    self:log("XRayPlugin: Series: Failed fetching book summary for " .. tostring(current_book.title) .. ", err_code=" .. tostring(err_code) .. ", err_msg=" .. tostring(err_msg))
                    if wait_msg then UIManager:close(wait_msg) end
                    if not is_silent then
                        local err_title, err_text = utils:getFriendlyError(err_code, err_msg, self.loc)
                        UIManager:show(ConfirmBox:new{
                            text = err_title .. "\n\n" .. err_text,
                            ok_text = self.loc:t("ok") or "OK",
                            cancel_text = nil
                        })
                    end
                    return
                end

                self:log("XRayPlugin: Series: Fetched context for " .. tostring(current_book.title) .. ". Characters=" .. tostring(#(result.characters or {})) .. ", locations=" .. tostring(#(result.locations or {})) .. ", terms=" .. tostring(#(result.terms or {})) .. ", timeline=" .. tostring(#(result.timeline or {})))

                cache_data.books[current_book.index] = {
                    title = current_book.title,
                    author = current_book.author,
                    characters = result.characters or {},
                    locations = result.locations or {},
                    terms = result.terms or {},
                    timeline = result.timeline or {}
                }

                fetchNext(step_idx + 1)
            end)
        end

        fetchNext(1)
    end)
end

return M
