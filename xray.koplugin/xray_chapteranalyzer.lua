-- ChapterAnalyzer - Analyze which characters appear in current chapter/page
local logger = require("logger")
local plugin_path = ((...) or ""):match("(.-)[^%.]+$") or ""
local AIHelper = require(plugin_path .. "xray_aihelper")
local xray_utils = require(plugin_path .. "xray_utils")

-- Helper function to flatten KOReader's nested TOC tree
local function flattenTOC(nodes, flat_list, current_depth)
    flat_list = flat_list or {}
    current_depth = current_depth or 1
    if not nodes then return flat_list end
    
    for _, node in ipairs(nodes) do
        if type(node) == "table" then
            if node.depth == nil then
                node.depth = current_depth
            end
            table.insert(flat_list, node)
            local next_depth = (node.depth or current_depth) + 1
            if #node > 0 then
                flattenTOC(node, flat_list, next_depth)
            elseif node.sub_item_table then
                flattenTOC(node.sub_item_table, flat_list, next_depth)
            elseif node.children then
                flattenTOC(node.children, flat_list, next_depth)
            end
        else
            table.insert(flat_list, node)
        end
    end
    return flat_list
end

local ChapterAnalyzer = {}

-- Keep byte budgets, but never return a partial UTF-8 code point.
local function utf8_sub(s, first, last)
    if not s or s == "" then return s or "" end
    local len = #s
    first = first or 1
    last = last or len
    if first < 0 then first = len + first + 1 end
    if last < 0 then last = len + last + 1 end
    first = math.max(1, first)
    last = math.min(len, last)
    if first > last then return "" end

    -- Scan complete code points from the beginning. This handles a requested
    -- start inside a character and an end inside a character without relying
    -- on any particular byte alignment.
    local out, i = {}, 1
    while i <= len do
        local lead = s:byte(i)
        local width = (lead < 0x80 and 1) or (lead < 0xE0 and 2)
            or (lead < 0xF0 and 3) or (lead < 0xF5 and 4) or 1
        local finish = i + width - 1
        if i >= first and finish <= last then
            out[#out + 1] = s:sub(i, finish)
        end
        i = finish + 1
    end
    return table.concat(out)
end

ChapterAnalyzer.utf8_sub = utf8_sub

function ChapterAnalyzer:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

-- Page ranges use different end semantics across KOReader document types.
-- Reflowable extraction stops at the end XPointer, so the next page marks the
-- end of the current page. Page-based extraction is inclusive and must stop on
-- the current page to avoid reading one page ahead.
function ChapterAnalyzer:getEndPageForCurrentPage(ui, current_page)
    if not current_page then return nil end
    if ui and ui.rolling ~= nil then
        return current_page + 1
    end
    return current_page
end

-- Get current chapter/section text
function ChapterAnalyzer:getCurrentChapterText(ui)
    if not ui or not ui.document then
        logger.warn("ChapterAnalyzer: No document available")
        AIHelper:log("ChapterAnalyzer: No document available")
        return nil
    end
    
    -- Check if it's a reflowable document (EPUB, etc.) or page-based (PDF, etc.)
    local is_reflowable = ui.rolling ~= nil
    local is_paged = ui.paging ~= nil
    
    logger.info("ChapterAnalyzer: Reflowable:", is_reflowable, "Paged:", is_paged)
    AIHelper:log("ChapterAnalyzer: Reflowable: " .. tostring(is_reflowable) .. " Paged: " .. tostring(is_paged))
    
    if is_reflowable then
        return self:getReflowableText(ui)
    elseif is_paged then
        return self:getPageBasedText(ui)
    else
        logger.warn("ChapterAnalyzer: Unknown document type")
        AIHelper:log("ChapterAnalyzer: Unknown document type")
        return self:getFallbackText(ui)
    end
end

-- Get text from reflowable documents (EPUB, HTML, FB2)
function ChapterAnalyzer:getReflowableText(ui)
    -- Get current position - different methods for different versions
    local current_pos = nil
    
    -- Try different methods to get current position
    if ui.rolling.current_page then
        current_pos = ui.rolling.current_page
    elseif ui.rolling.getCurrentPos then
        current_pos = ui.rolling:getCurrentPos()
    elseif ui.document.getCurrentPos then
        current_pos = ui.document:getCurrentPos()
    elseif ui.view and ui.view.state and ui.view.state.page then
        current_pos = ui.view.state.page
    else
        -- Last resort: use page 1
        current_pos = 1
    end
    
    logger.info("ChapterAnalyzer: Current position:", current_pos)
    
    -- Try to get chapter from TOC
    local raw_toc = ui.document:getToc()
    local toc = flattenTOC(raw_toc)
    local default_chapter_title = ui.loc and ui.loc:t("this_chapter") or "This Chapter"
    if not toc or #toc == 0 then
        logger.info("ChapterAnalyzer: No TOC, using visible text")
        return self:getVisibleTextReflowable(ui), default_chapter_title
    end
    
    -- Find current chapter: select the chapter with page <= current_pos closest to current_pos
    local current_chapter = nil
    local max_chapter_page = -1
    local chapter_title = default_chapter_title
    
    for _, chapter in ipairs(toc) do
        if chapter.page then
            local p = tonumber(chapter.page)
            if p and p <= current_pos and p >= max_chapter_page then
                max_chapter_page = p
                current_chapter = chapter
                chapter_title = chapter.title or default_chapter_title
            end
        end
    end
    
    if not current_chapter then
        logger.warn("ChapterAnalyzer: No current chapter found")
        return self:getVisibleTextReflowable(ui), default_chapter_title
    end
    
    logger.info("ChapterAnalyzer: Current chapter:", chapter_title)
    
    -- For EPUB, we'll try to get text from the document
    -- Method 1: Try getTextFromPositions if available
    local text = ""
    local text_length = 50000  -- ~50k characters
    
    if ui.document.getTextFromPositions then
        local success, result = pcall(function()
            return ui.document:getTextFromPositions(current_pos, current_pos + text_length)
        end)
        
        if success and result and #result > 100 then
            text = result
            logger.info("ChapterAnalyzer: Got", #text, "characters from positions")
            collectgarbage("collect") -- Force cleanup after large string allocation
            return text, chapter_title
        end
    end
    
    -- Method 2: Try to extract text from current chapter xpointer
    if ui.document.getTextFromXPointer and current_chapter.xpointer then
        local success, result = pcall(function()
            return ui.document:getTextFromXPointer(current_chapter.xpointer)
        end)
        
        if success and result and #result > 100 then
            text = result
            logger.info("ChapterAnalyzer: Got", #text, "characters from xpointer")
            collectgarbage("collect") -- Force cleanup after large string allocation
            return text, chapter_title
        end
    end
    
    -- Method 3: Get visible text (fallback)
    text = self:getVisibleTextReflowable(ui)
    logger.info("ChapterAnalyzer: Using visible text fallback")
    collectgarbage("collect")
    
    return text, chapter_title
end

-- Get currently visible text (reflowable)
function ChapterAnalyzer:getVisibleTextReflowable(ui)
    -- Try multiple methods to get text
    local text = ""
    
    -- Method 1: Try getting text from view
    if ui.view and ui.view.document and ui.view.document.extractText then
        local success, result = pcall(function()
            return ui.view.document:extractText()
        end)
        if success and result and #result > 100 then
            logger.info("ChapterAnalyzer: Got text from view.document.extractText")
            return result
        end
    end
    
    -- Method 2: Try document getFullText
    if ui.document.getFullText then
        local success, result = pcall(function()
            return ui.document:getFullText()
        end)
        if success and result and #result > 100 then
            logger.info("ChapterAnalyzer: Got text from getFullText")
            -- Limit size
            if #result > 100000 then
                result = utf8_sub(result, 1, 100000)
            end
            return result
        end
    end
    
    -- Method 3: Try to read from pages (if document has pages)
    if ui.document.getPageCount and ui.document.getPageText then
        local page_count = ui.document:getPageCount()
        local max_pages = math.min(page_count, 50)
        
        for i = 1, max_pages do
            local success, page_text = pcall(function()
                return ui.document:getPageText(i)
            end)
            if success and page_text then
                text = text .. " " .. page_text
            end
        end
        
        if #text > 100 then
            logger.info("ChapterAnalyzer: Got text from pages")
            return text
        end
    end
    
    -- If nothing worked, return empty
    logger.warn("ChapterAnalyzer: Could not extract any text")
    return ""
end

-- Get text from page-based documents (PDF, DJVU)
function ChapterAnalyzer:getPageBasedText(ui)
    -- Try to get chapter from TOC
    local raw_toc = ui.document:getToc()
    local toc = flattenTOC(raw_toc)
    if not toc or #toc == 0 then
        logger.info("ChapterAnalyzer: No TOC, using current page only")
        return self:getCurrentPageTextPDF(ui)
    end
    
    -- Find current chapter based on page
    local current_page = ui.paging:getCurrentPage()
    local current_chapter = nil
    local max_chapter_page = -1
    
    for _, chapter in ipairs(toc) do
        if chapter.page then
            local p = tonumber(chapter.page)
            if p and p <= current_page and p >= max_chapter_page then
                max_chapter_page = p
                current_chapter = chapter
            end
        end
    end
    
    if not current_chapter then
        logger.warn("ChapterAnalyzer: No current chapter found")
        return self:getCurrentPageTextPDF(ui)
    end
    
    logger.info("ChapterAnalyzer: Current chapter:", current_chapter.title)
    
    -- Get text from current chapter start to next chapter start (or end)
    local start_page = current_chapter.page
    local end_page = next_chapter and next_chapter.page - 1 or ui.document:getPageCount()
    
    -- Limit to reasonable range (max 50 pages for performance)
    if end_page - start_page > 50 then
        end_page = start_page + 50
        logger.info("ChapterAnalyzer: Limited to 50 pages for performance")
    end
    
    logger.info("ChapterAnalyzer: Analyzing pages", start_page, "to", end_page)
    
    -- Collect text from pages
    local chapter_text = ""
    for page = start_page, end_page do
        local page_text = ui.document:getPageText(page)
        if page_text then
            chapter_text = chapter_text .. " " .. page_text
        end
    end
    
    return chapter_text, current_chapter.title
end

-- Get current page text (PDF/page-based) - fallback
function ChapterAnalyzer:getCurrentPageTextPDF(ui)
    local current_page = ui.paging:getCurrentPage()
    
    -- Try to get text from current page and next few pages
    local text = ""
    for i = 0, 4 do  -- Current + 4 pages
        local page = current_page + i
        if page <= ui.document:getPageCount() then
            local page_text = ui.document:getPageText(page)
            if page_text then
                text = text .. " " .. page_text
            end
        end
    end
    
    local default_page_title = ui.loc and ui.loc:t("this_page") or "This Page"
    return text, default_page_title
end

-- Fallback for unknown document types
function ChapterAnalyzer:getFallbackText(ui)
    logger.warn("ChapterAnalyzer: Using fallback text extraction")
    
    -- Try different methods
    local text = ""
    
    -- Method 1: Try to get selection text or visible text
    if ui.highlight and ui.highlight.selected_text then
        text = ui.highlight.selected_text.text or ""
    end
    
    -- Method 2: Try document getTextFromPositions if available
    if #text < 100 and ui.document.getTextFromPositions then
        local success, result = pcall(function()
            return ui.document:getTextFromPositions(0, 10000)
        end)
        if success and result then
            text = result
        end
    end
    
    -- Method 3: Just show a message
    if #text < 100 then
        logger.warn("ChapterAnalyzer: Could not extract text")
        return nil, nil
    end
    
    local default_page_title = ui.loc and ui.loc:t("this_page") or "This Page"
    return text, default_page_title
end

-- Find characters mentioned in text
function ChapterAnalyzer:findCharactersInText(text, characters)
    if not text or not characters then
        return {}
    end
    
    local found_characters = {}
    local text_lower = string.lower(text)
    
    for _, char in ipairs(characters) do
        local name = char.name
        if name and #name >= 1 then
            local name_lower = string.lower(name)
            
            -- Helper to check word boundaries for short names
            local function findWithBoundaries(text, needle)
                if #needle < 4 then
                    local safe_needle = needle:gsub("([%(%)%.%%%+%-%*%?%[%^%$])", "%%%1")
                    local pattern = "%f[%w]" .. safe_needle .. "%f[%W]"
                    return string.find(text, pattern)
                else
                    return string.find(text, needle, 1, true)
                end
            end
            
            -- Check full name
            if findWithBoundaries(text_lower, name_lower) then
                table.insert(found_characters, {
                    character = char,
                    count = self:countMentions(text_lower, name_lower)
                })
            else
                -- Check first name only
                local first_name = string.match(name, "^(%S+)")
                if first_name and #first_name >= 1 then
                    local first_name_lower = string.lower(first_name)
                    if findWithBoundaries(text_lower, first_name_lower) then
                        table.insert(found_characters, {
                            character = char,
                            count = self:countMentions(text_lower, first_name_lower)
                        })
                    end
                end
            end
        end
    end
    
    -- Sort by mention count
    table.sort(found_characters, function(a, b)
        return a.count > b.count
    end)
    
    logger.info("ChapterAnalyzer: Found", #found_characters, "characters in text")
    AIHelper:log("ChapterAnalyzer: Found " .. tostring(#found_characters) .. " characters in text")
    
    return found_characters
end

-- Extract text from a specific page range (start_page to end_page)
-- Returns up to max_len characters from the specified region
function ChapterAnalyzer:getTextFromPageRange(ui, start_page, end_page, max_len)
    if not ui or not ui.document then return nil end
    max_len = max_len or 15000
    
    local is_reflowable = ui.rolling ~= nil
    
    if is_reflowable then
        -- Save the reader's actual position so we can restore it
        local saved_xp = ui.document:getXPointer()
        
        local success, result = pcall(function()
            -- Get XPointer for the start of the range
            local start_xp = nil
            if ui.document.getPageXPointer then
                start_xp = ui.document:getPageXPointer(start_page)
            end
            if not start_xp then
                ui.document:gotoPage(start_page)
                start_xp = ui.document:getXPointer()
            end
            
            -- Get XPointer for the end of the range
            local end_xp = nil
            if ui.document.getPageXPointer then
                end_xp = ui.document:getPageXPointer(end_page)
            end
            if not end_xp then
                ui.document:gotoPage(end_page)
                end_xp = ui.document:getXPointer()
            end
            
            if not start_xp or not end_xp then return "" end
            
            -- Extract text between the two XPointers
            local text = ui.document:getTextFromXPointers(start_xp, end_xp) or ""
            
            -- Trim to max_len (take from the beginning since we want this specific range)
            if #text > max_len then
                text = text:sub(1, max_len)
            end
            return text
        end)
        
        -- Always restore the reader's position
        if saved_xp then
            pcall(function() ui.document:gotoXPointer(saved_xp) end)
        end
        
        if success and result and #result > 0 then
            return result
        end
        return nil
    else
        -- PDF: page-by-page extraction
        if not ui.document.getPageText then
            return nil
        end
        local text = ""
        for page = start_page, end_page do
            local page_text = ui.document:getPageText(page) or ""
            if type(page_text) == "table" then
                local texts = {}
                for _, block in ipairs(page_text) do
                    if type(block) == "table" then
                        for j = 1, #block do
                            local span = block[j]
                            if type(span) == "table" and span.word then
                                table.insert(texts, span.word)
                            end
                        end
                    end
                end
                page_text = table.concat(texts, " ")
            end
            text = text .. page_text .. "\n"
            if #text >= max_len then
                return utf8_sub(text, 1, max_len)
            end
        end
        return #text > 0 and text or nil
    end
end

-- Get text for analysis (up to max_len characters before current position)
function ChapterAnalyzer:getTextForAnalysis(ui, max_len, progress_callback, current_page, start_page, target_xp, story_bounds)
    if not ui or not ui.document then
        AIHelper:log("ChapterAnalyzer: getTextForAnalysis - no document")
        return nil
    end
    
    max_len = max_len or 100000 
    local book_text = ""
    AIHelper:log("ChapterAnalyzer: Extracting text for analysis (max " .. tostring(max_len) .. " chars)")

    if story_bounds then
        if story_bounds.start_page then
            start_page = math.max(start_page or story_bounds.start_page, story_bounds.start_page)
        end
        if story_bounds.end_page and current_page and current_page > story_bounds.end_page then
            current_page = story_bounds.end_page
        end
    end
    
    -- Check if it's a reflowable document (EPUB, etc.)
    local is_reflowable = ui.rolling ~= nil
    
    if is_reflowable then
        local current_xp = nil
        
        -- Priority 1: Exact target XPointer (e.g., from a highlighted word)
        if target_xp then
            current_xp = target_xp
            AIHelper:log("ChapterAnalyzer: Using exact target_xp for context boundary")
        end
        
        if not current_xp then
            pcall(function()
                if not ui or not ui.document then return end
                -- Priority 2: Use getPageXPointer if provided and supported
                if current_page and ui.document.getPageXPointer then
                    local total_pages = ui.document:getPageCount() or current_page
                    local safe_pos = math.min(current_page, total_pages)
                    current_xp = ui.document:getPageXPointer(safe_pos)
                end
                -- Fallback to jumping if getPageXPointer is not available but we have a target pos
                if not current_xp and current_page then
                    local total_pages = ui.document:getPageCount() or current_page
                    local safe_pos = math.min(current_page, total_pages)
                    
                    -- Save current position to jump back
                    local current_real_xp = ui.document:getXPointer()
                    if current_real_xp then
                        ui.document:gotoPage(safe_pos)
                        current_xp = ui.document:getXPointer()
                        ui.document:gotoXPointer(current_real_xp)
                    end
                end
                
                -- Ultimate fallback to current screen top
                if not current_xp then 
                    current_xp = ui.document:getXPointer()
                end
            end)
        end
        
        if not current_xp then 
            AIHelper:log("ChapterAnalyzer: getTextForAnalysis - could not get XPointer")
            return nil 
        end
        
        -- Optimization: Try to get start XPointer without jumping to avoid "white flash"
        local success, result = pcall(function()
            if not ui or not ui.document then return "" end
            if progress_callback then progress_callback(0.1) end
            
            local start_xp = nil
            if start_page and start_page > 1 then
                AIHelper:log("ChapterAnalyzer: getTextForAnalysis - incremental mode from page " .. tostring(start_page))
                
                -- Cap the window: never look back more than 60 pages regardless of start_page.
                -- If start_page is ahead of or equal to current_p, an incremental XPointer
                -- range would be empty/reversed and can freeze the UI on massive extractions.
                local current_p = current_page or 1
                if start_page >= current_p then
                    AIHelper:log("ChapterAnalyzer: start_page=" .. tostring(start_page)
                        .. " >= current_page=" .. tostring(current_p)
                        .. "; nothing new to fetch")
                    return ""
                else
                    local max_lookback = 60
                    local capped_start = math.max(start_page, current_p - max_lookback)
                    if story_bounds and story_bounds.start_page then
                        capped_start = math.max(capped_start, story_bounds.start_page)
                    end
                    if capped_start > start_page then
                        AIHelper:log("ChapterAnalyzer: Capping incremental start_page from " .. tostring(start_page) .. " to " .. tostring(capped_start) .. " (60-page window)")
                        start_page = capped_start
                    end
                end

                if start_page then
                    -- Method 1: Use getPageXPointer (fast, no flash)
                    if ui.document.getPageXPointer then
                        start_xp = ui.document:getPageXPointer(start_page)
                    end
                    
                    -- Method 2: Fallback to jumping (causes flash, but only if Method 1 failed)
                    if not start_xp then
                        AIHelper:log("ChapterAnalyzer: Fallback to gotoPage for start XPointer")
                        ui.document:gotoPage(start_page)
                        start_xp = ui.document:getXPointer()
                        ui.document:gotoXPointer(current_xp)
                    end
                end
            end
            if not start_page or start_page <= 1 then
                -- Limit window: at most 60 pages back to avoid blocking extraction
                local current_p = current_page or (ui.getCurrentPage and ui:getCurrentPage()) or 1
                local min_bound = (story_bounds and story_bounds.start_page) or 1
                local window_start = math.max(min_bound, current_p - 60)
                if ui.document.getPageXPointer then
                    start_xp = ui.document:getPageXPointer(window_start)
                elseif ui.document.gotoPos then
                    -- Legacy fallback: jump to a nearby page instead of position 0
                    local saved_xp = ui.document:getXPointer()
                    ui.document:gotoPage(window_start)
                    start_xp = ui.document:getXPointer()
                    if saved_xp then ui.document:gotoXPointer(saved_xp) end
                end
            end
            
            if not start_xp then return "" end
            
            if progress_callback then progress_callback(0.3) end
            
            -- Extract EVERYTHING from start to here
            local full_text = ui.document:getTextFromXPointers(start_xp, current_xp) or ""
            
            -- Trim to the last max_len characters
            if #full_text > max_len then
                return full_text:sub(-max_len)
            else
                return full_text
            end
        end)
        
        if success and result then
            book_text = result
        else
            AIHelper:log("ChapterAnalyzer: getTextForAnalysis - XPointer extraction failed: " .. tostring(result))
            book_text = ""
        end
    else
        -- For page-based documents (PDF), get text from a limited number of pages before current
        if not ui.document.getPageText then
            logger.warn("ChapterAnalyzer: getPageText not supported on ui.document")
            return ""
        end
        local current_pos = current_page or (ui.view and ui.view.state and ui.view.state.page) or 1
        if story_bounds and story_bounds.end_page and current_pos > story_bounds.end_page then
            current_pos = story_bounds.end_page
        end
        local max_pages = 100 
        local min_calc_base = (story_bounds and story_bounds.start_page) or 1
        local calc_start_page = math.max(min_calc_base, current_pos - max_pages)
        if start_page and start_page > 1 then
            if start_page >= current_pos then
                AIHelper:log("ChapterAnalyzer: start_page=" .. tostring(start_page)
                    .. " >= current_pos=" .. tostring(current_pos)
                    .. "; nothing new to fetch")
                return ""
            end
            calc_start_page = math.max(start_page, calc_start_page)
        end
        
        logger.info("ChapterAnalyzer: Extracting PDF pages", calc_start_page, "to", current_pos)
        AIHelper:log("ChapterAnalyzer: Extracting PDF pages " .. tostring(calc_start_page) .. " to " .. tostring(current_pos))
        
        for page = calc_start_page, current_pos do
            if not ui or not ui.document then break end
            if progress_callback and (page % 10 == 0) and current_pos > calc_start_page then
                progress_callback(0.1 + (0.8 * (page - calc_start_page) / (current_pos - calc_start_page)))
            end
            
            local ok_page, page_text = pcall(function() return ui.document:getPageText(page) end)
            if not ok_page then page_text = "" end
            page_text = page_text or ""
            if type(page_text) == "table" then
                local texts = {}
                for _, block in ipairs(page_text) do
                    if type(block) == "table" then
                        for i = 1, #block do
                            local span = block[i]
                            if type(span) == "table" and span.word then
                                table.insert(texts, span.word)
                            end
                        end
                    end
                end
                page_text = table.concat(texts, " ")
            end
            book_text = book_text .. page_text .. "\n"
        end
    end
    
    -- Limit text length (from the end)
    if #book_text > max_len then
        book_text = book_text:sub(-max_len)
    end
    
    if progress_callback then progress_callback(1.0) end
    logger.info("ChapterAnalyzer: Total characters extracted for analysis:", #book_text)
    AIHelper:log("ChapterAnalyzer: Total characters extracted for analysis: " .. tostring(#book_text))
    return book_text
end

-- Get highlights and notes for analysis (filtered up to max_page to prevent future leaks)
function ChapterAnalyzer:getAnnotationsForAnalysis(ui, max_page)
    local annotations_text = ""
    if not max_page and ui then
        if type(ui.getCurrentPage) == "function" then
            pcall(function() max_page = ui:getCurrentPage() end)
        elseif ui.document and type(ui.document.getCurrentPage) == "function" then
            pcall(function() max_page = ui.document:getCurrentPage() end)
        end
    end
    max_page = tonumber(max_page)
    
    -- Try to get annotations from the document/UI
    -- In KOReader, annotations are typically in ui.annotation.annotations
    if ui and ui.annotation and ui.annotation.annotations then
        for _, annot in ipairs(ui.annotation.annotations) do
            local annot_page = tonumber(annot.page)
            if not annot_page and type(annot.page) == "string" and ui.document and type(ui.document.getPageFromXPointer) == "function" then
                local ok, resolved = pcall(ui.document.getPageFromXPointer, ui.document, annot.page)
                if ok then
                    annot_page = tonumber(resolved)
                end
            end
            if not annot_page then
                annot_page = tonumber(annot.pageno)
                    or (type(annot.pos0) == "table" and tonumber(annot.pos0.page))
            end
            if not annot_page and type(annot.pos0) == "string" and ui.document and type(ui.document.getPageFromXPointer) == "function" then
                local ok, resolved = pcall(ui.document.getPageFromXPointer, ui.document, annot.pos0)
                if ok then
                    annot_page = tonumber(resolved)
                end
            end
            if not max_page or not annot_page or annot_page <= max_page then
                if annot.text and #annot.text > 0 then
                    annotations_text = annotations_text .. "Highlight: " .. annot.text .. "\n"
                end
                if annot.note and #annot.note > 0 then
                    annotations_text = annotations_text .. "Note: " .. annot.note .. "\n"
                end
            end
        end
    end
    
    return #annotations_text > 0 and annotations_text or nil
end

function ChapterAnalyzer:resolveTocEntryPage(ui, ch)
    if not ch then return nil end
    if ch.page and tonumber(ch.page) then
        return tonumber(ch.page)
    end
    if ch.xpointer and ui and ui.document and type(ui.document.getPageFromXPointer) == "function" then
        local ok, p = pcall(ui.document.getPageFromXPointer, ui.document, ch.xpointer)
        if ok and p and tonumber(p) then
            local pg = tonumber(p)
            ch.page = pg
            return pg
        end
    end
    return nil
end

function ChapterAnalyzer:isNonStoryEntry(title, book_title)
    if not title then return true end
    local lower = title:lower():gsub("^%s+", ""):gsub("%s+$", "")
    if lower == "" then return true end

    -- Project Gutenberg / license markers
    if lower:find("project gutenberg") or lower:find("license") then return true end

    -- Matches the entire book title (NCX entry 1 in many Gutenberg epubs)
    if book_title then
        local bt_lower = book_title:lower():gsub("^%s+", ""):gsub("%s+$", "")
        if lower == bt_lower then return true end
    end

    -- Front/Back matter markers that shouldn't be counted as a story
    local non_story_patterns = {
        "^the full project gutenberg",
        "^gutenberg",
        "^introduction",
        "^preface",
        "^foreword",
        "^editor'?s note",
        "^note on the text",
        "^publisher'?s note",
        "^colophon",
        "^table of contents",
        "^contents$",
        "^cover$",
        "^title page",
        "^half%-title",
        "^appendix",
        "^index$",
        "^bibliography",
        "^also by",
        "^other books",
        "^about the author",
        "^about the",
        "^dedication",
        "^acknowledgment",
    }
    for _, pat in ipairs(non_story_patterns) do
        if lower:match(pat) then return true end
    end
    return false
end

function ChapterAnalyzer:getStoryMap(ui, custom_depth)
    if not ui or not ui.document then
        return { stories = {}, by_id = {}, by_toc_idx = {}, target_depth = 1 }
    end
    local doc_file = ui.document.file or "current"
    self._story_map_cache = self._story_map_cache or {}
    local cache_key = tostring(doc_file) .. "::" .. tostring(custom_depth or "auto")
    if self._story_map_cache[cache_key] then
        return self._story_map_cache[cache_key]
    end

    local book_title = nil
    if ui.document.getProps then
        pcall(function()
            local props = ui.document:getProps()
            if props and props.title then book_title = props.title end
        end)
    end

    local raw_toc
    pcall(function()
        if ui.document.getToc then raw_toc = ui.document:getToc() end
    end)
    local toc = flattenTOC(raw_toc)
    if not toc or #toc == 0 then
        local empty_map = { stories = {}, by_id = {}, by_toc_idx = {}, target_depth = 1 }
        self._story_map_cache[cache_key] = empty_map
        return empty_map
    end

    local total_pages = 0
    if ui.document.getPageCount then
        pcall(function() total_pages = ui.document:getPageCount() or 0 end)
    elseif ui.document.getNumberOfPages then
        pcall(function() total_pages = ui.document:getNumberOfPages() or 0 end)
    end

    local isNonNarrative = function(title)
        if self:isNonStoryEntry(title, book_title) then return true end
        if self.plugin and self.plugin.isNonNarrativeChapter then
            return self.plugin:isNonNarrativeChapter(title)
        end
        local ok_data, xray_data = pcall(require, plugin_path .. "xray_data")
        if ok_data and xray_data and xray_data.isNonNarrativeChapter then
            return xray_data:isNonNarrativeChapter(title)
        end
        return false
    end

    -- Determine minimum narrative depth
    local min_depth = nil
    local narrative_at_depth = {}
    for i, ch in ipairs(toc) do
        local d = ch.depth or 1
        ch.toc_index = i
        if not isNonNarrative(ch.title) then
            if not min_depth or d < min_depth then
                min_depth = d
            end
            narrative_at_depth[d] = (narrative_at_depth[d] or 0) + 1
        end
    end
    min_depth = min_depth or 1

    local target_depth = min_depth
    if custom_depth and tonumber(custom_depth) then
        target_depth = tonumber(custom_depth)
    elseif custom_depth == "auto" or not custom_depth then
        local part_count = 0
        local total_min_narrative = 0
        for _, ch in ipairs(toc) do
            if (ch.depth or 1) == min_depth and not isNonNarrative(ch.title) then
                total_min_narrative = total_min_narrative + 1
                local t_low = (ch.title or ""):lower():gsub("^%s+", "")
                if t_low:match("^part[%s%p%d]") or t_low:match("^volume[%s%p%d]")
                    or t_low:match("^book[%s%p%d]") or t_low:match("^section[%s%p%d]")
                    or t_low:match("^[ivxlcdm]+$") then
                    part_count = part_count + 1
                end
            end
        end
        if total_min_narrative > 0 and (part_count / total_min_narrative >= 0.5) and (narrative_at_depth[min_depth + 1] or 0) > 0 then
            target_depth = min_depth + 1
        end
    end

    local stories = {}
    local by_id = {}
    local by_toc_idx = {}
    local current_story = nil

    local function closeCurrentStory(next_start_page, next_start_xp, last_toc_idx)
        if current_story then
            current_story.end_toc_idx = last_toc_idx or current_story.start_toc_idx
            if next_start_page and next_start_page > 0 then
                current_story.end_page = math.max(current_story.start_page or 1, next_start_page - 1)
            elseif total_pages > 0 then
                current_story.end_page = total_pages
            else
                current_story.end_page = current_story.start_page or 1
            end
            current_story.end_xp = next_start_xp
        end
    end

    for i, ch in ipairs(toc) do
        local is_non = isNonNarrative(ch.title)
        local d = ch.depth or 1
        local p = self:resolveTocEntryPage(ui, ch)

        local is_container = false
        if d < target_depth then
            local nxt = toc[i + 1]
            if nxt and (nxt.depth or 1) > d then
                is_container = true
            end
        end

        if not is_non and not is_container and d <= target_depth then
            closeCurrentStory(p, ch.xpointer, i - 1)
            local story_id = "toc_" .. tostring(i)
            current_story = {
                story_id = story_id,
                story_title = ch.title or ("Story " .. tostring(#stories + 1)),
                start_toc_idx = i,
                end_toc_idx = i,
                start_page = p or (current_story and (current_story.end_page or 0) + 1) or 1,
                end_page = nil,
                start_xp = ch.xpointer,
                end_xp = nil,
                depth = d,
            }
            table.insert(stories, current_story)
            by_id[story_id] = current_story
            by_toc_idx[i] = current_story
        elseif current_story then
            current_story.end_toc_idx = i
            by_toc_idx[i] = current_story
            if not current_story.start_page and p then
                current_story.start_page = p
            end
        end
    end

    closeCurrentStory(total_pages > 0 and (total_pages + 1) or nil, nil, #toc)

    for idx, s in ipairs(stories) do
        if not s.start_page then
            local prev = stories[idx - 1]
            s.start_page = prev and ((prev.end_page or prev.start_page or 0) + 1) or 1
        end
        if not s.end_page or s.end_page < s.start_page then
            local nxt = stories[idx + 1]
            if nxt and nxt.start_page and nxt.start_page > s.start_page then
                s.end_page = nxt.start_page - 1
            elseif total_pages > 0 then
                s.end_page = total_pages
            else
                s.end_page = s.start_page
            end
        end
    end

    local map = {
        stories = stories,
        by_id = by_id,
        by_toc_idx = by_toc_idx,
        target_depth = target_depth,
    }
    self._story_map_cache[cache_key] = map
    return map
end

function ChapterAnalyzer:getStoryForTocIndex(ui, toc_idx, custom_depth)
    local map = self:getStoryMap(ui, custom_depth)
    if not map or not map.stories or #map.stories == 0 then return nil end
    if map.by_toc_idx and map.by_toc_idx[toc_idx] then return map.by_toc_idx[toc_idx] end
    local best = map.stories[1]
    for _, s in ipairs(map.stories) do
        if s.start_toc_idx <= toc_idx then
            best = s
        else
            break
        end
    end
    return best
end

function ChapterAnalyzer:getStoryForPage(ui, page, custom_depth)
    local map = self:getStoryMap(ui, custom_depth)
    if not map or not map.stories or #map.stories == 0 then return nil end
    page = tonumber(page) or 1
    local best = map.stories[1]
    for _, s in ipairs(map.stories) do
        if s.start_page and s.start_page <= page then
            best = s
        elseif s.start_page and s.start_page > page then
            break
        end
    end
    return best
end

-- Subdivide oversized TOC entries (e.g. books with only "Parts" like Carrie, or chapters > 60 pages)
-- into granular virtual segments for sequential Story Arc prefetching.
function ChapterAnalyzer:expandOversizedTocChapters(toc, total_pages, max_pages_per_segment)
    if not toc or #toc == 0 then return {} end
    max_pages_per_segment = max_pages_per_segment or 60
    total_pages = total_pages or 0

    local expanded = {}
    local global_toc_index = 1

    for i, ch in ipairs(toc) do
        local parent_idx = ch.parent_toc_index or ch.toc_index or i
        local parent_name = ch.parent_title or ch.title or ("Chapter " .. tostring(parent_idx))
        local next_page = nil
        for j = i + 1, #toc do
            if toc[j] and toc[j].page and toc[j].page > (ch.page or 0) then
                next_page = toc[j].page
                break
            end
        end
        if not next_page and total_pages > (ch.page or 0) then
            next_page = total_pages + 1
        end

        local page_span = (ch.page and next_page and next_page > ch.page) and (next_page - ch.page) or 0
        if page_span > max_pages_per_segment then
            local num_parts = math.ceil(page_span / max_pages_per_segment)
            local pages_per_part = math.ceil(page_span / num_parts)
            for part = 1, num_parts do
                local seg_start = ch.page + (part - 1) * pages_per_part
                local seg_end = math.min(next_page - 1, seg_start + pages_per_part - 1)
                local sub_ch = {
                    title = string.format("%s (%d/%d)", ch.title or "Chapter", part, num_parts),
                    parent_title = parent_name,
                    parent_toc_index = parent_idx,
                    part_index = part,
                    total_parts = num_parts,
                    page = seg_start,
                    end_page = seg_end,
                    toc_index = parent_idx,
                    segment_index = global_toc_index,
                    depth = ch.depth,
                    is_virtual_segment = true,
                    xpointer = (part == 1 and ch.xpointer) or nil,
                }
                table.insert(expanded, sub_ch)
                global_toc_index = global_toc_index + 1
            end
        else
            local cloned = {
                title = ch.title,
                parent_title = parent_name,
                parent_toc_index = parent_idx,
                part_index = 1,
                total_parts = 1,
                page = ch.page,
                end_page = next_page and (next_page - 1) or nil,
                toc_index = parent_idx,
                segment_index = global_toc_index,
                depth = ch.depth,
                xpointer = ch.xpointer,
            }
            table.insert(expanded, cloned)
            global_toc_index = global_toc_index + 1
        end
    end

    return expanded
end

-- Get bounded text for a single chapter (#150 & #131 sequential pipeline)
function ChapterAnalyzer:getSingleChapterText(ui, chapter, next_chapter, current_page, max_len)
    if not ui or not ui.document or not chapter then return "" end
    max_len = max_len or 40000

    -- If reader is inside this chapter and spoiler protection is needed, strictly truncate to current page
    if current_page and chapter.page and chapter.page <= current_page then
        local next_page = chapter.end_page or (next_chapter and next_chapter.page)
        if not next_page or next_page > current_page then
            local end_page = self:getEndPageForCurrentPage(ui, current_page)
            return self:getTextFromPageRange(ui, chapter.page, end_page, max_len) or ""
        end
    end

    -- Explicit page bounds (e.g. virtual segment from expandOversizedTocChapters)
    if chapter.end_page and chapter.page then
        local txt = self:getTextFromPageRange(ui, chapter.page, chapter.end_page, max_len)
        if txt and #txt > 0 then return txt end
    end

    -- Reflowable document: extract bounded range between XPointers
    if ui.document.getTextFromXPointers and chapter.xpointer then
        local end_xp = next_chapter and next_chapter.xpointer
        if not end_xp and ui.document.getEndXPointer then
            end_xp = ui.document:getEndXPointer()
        end
        if end_xp then
            local txt = ui.document:getTextFromXPointers(chapter.xpointer, end_xp)
            if txt and #txt > 0 then
                if #txt > max_len then return utf8_sub(txt, 1, max_len) end
                return txt
            end
        end
    end

    -- Fallback to page range
    if chapter.page then
        local end_page = chapter.end_page or (next_chapter and next_chapter.page and (next_chapter.page - 1))
        if not end_page or end_page < chapter.page then end_page = chapter.page + 30 end
        local txt = self:getTextFromPageRange(ui, chapter.page, end_page, max_len)
        if txt and #txt > 0 then return txt end
    end

    -- Last resort XPointer fallback
    if ui.document.getTextFromXPointer and chapter.xpointer then
        local txt = ui.document:getTextFromXPointer(chapter.xpointer) or ""
        if #txt > max_len then return utf8_sub(txt, 1, max_len) end
        return txt
    end

    return ""
end

-- Get detailed samples (Start/Mid/End) from each chapter
function ChapterAnalyzer:getDetailedChapterSamples(ui, max_chapters, total_limit, is_full_book, start_page, known_chapters, resolved_current_page, story_bounds)
    if not ui or not ui.document then return nil, nil end
    
    local raw_toc
    pcall(function()
        if ui.document and ui.document.getToc then
            raw_toc = ui.document:getToc()
        end
    end)
    local toc = flattenTOC(raw_toc)
    if not toc or #toc == 0 then 
        logger.info("ChapterAnalyzer: No TOC found for detailed sampling")
        return nil, nil 
    end
    
    local current_page = resolved_current_page
    if not is_full_book then
        if current_page then
            -- The fetch pipeline resolves the page once and passes it through.
            -- Do not mix that value with view/rolling state, which can use a
            -- different pagination coordinate system for reflowable books.
        elseif type(ui.getCurrentPage) == "function" then
            local ok, pg = pcall(function() return ui:getCurrentPage() end)
            if ok and pg then current_page = pg end
        elseif ui.view and ui.view.state and ui.view.state.page then
            current_page = ui.view.state.page
        elseif ui.rolling and ui.rolling.current_page then
            current_page = ui.rolling.current_page
        elseif ui.paging and type(ui.paging.getCurrentPage) == "function" then
            local ok, pg = pcall(function() return ui.paging:getCurrentPage() end)
            if ok and pg then current_page = pg end
        end
    end
    
    max_chapters = max_chapters or 200
    total_limit = total_limit or 150000
    
    -- Non-narrative TOC entries to exclude
    local non_narrative_patterns = {
        "^cover$", "^title", "^copyright", "^table of contents", "^contents$",
        "^dedication", "^acknowledgment", "^also by", "^about the author",
        "^epigraph$", "^foreword$", "^preface$",
        "^appendix", "^glossary", "^index$", "^notes$", "^bibliography",
        "^colophon", "^frontispiece",
    }
    local function isNonNarrative(title)
        if not title then return false end
        local lower = title:lower():gsub("^%s+", ""):gsub("%s+$", "")
        for _, pat in ipairs(non_narrative_patterns) do
            if lower:match(pat) then return true end
        end
        return false
    end

    -- Helper to normalize title for comparison (matching main.lua logic roughly)
    local function normalize(t)
        if not t then return "" end
        return t:lower():gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", ""):gsub("^chapter%s*", ""):gsub("^ch%.?%s*", "")
    end

    -- Filter chapters
    local active_chapters = {}
    local chapter_titles = {}
    if toc and #toc > 0 then
        for i, chapter in ipairs(toc) do
            local ch_page = tonumber(chapter.page)
            local skip_by_story = false
            if story_bounds then
                if story_bounds.start_toc_idx and i < story_bounds.start_toc_idx then
                    skip_by_story = true
                elseif story_bounds.end_toc_idx and i > story_bounds.end_toc_idx then
                    skip_by_story = true
                elseif ch_page and story_bounds.start_page and ch_page < story_bounds.start_page then
                    skip_by_story = true
                elseif ch_page and story_bounds.end_page and ch_page > story_bounds.end_page then
                    skip_by_story = true
                end
            end
            if skip_by_story then
                -- Skip chapters outside the story bounds
            elseif not is_full_book and current_page and ch_page and ch_page > current_page then
                -- Skip chapters past current_page without breaking (since TOC items may not be strictly page-ordered)
            else
                -- Skip non-narrative chapters
                if isNonNarrative(chapter.title) then
                    AIHelper:log("ChapterAnalyzer: Skipping non-narrative chapter: " .. (chapter.title or tostring(i)))
                else
                    local skip = false
                    if start_page and not is_full_book then
                        -- Scan forward for the next TOC entry with a valid page number
                        local next_chapter_page = math.huge
                        for j = i + 1, #toc do
                            local np = tonumber(toc[j].page)
                            if np then
                                next_chapter_page = np
                                break
                            end
                        end
                        if next_chapter_page <= start_page then
                            -- ONLY skip if it's already in our data
                            if known_chapters then
                                local norm_title = normalize(chapter.title)
                                if known_chapters[norm_title] then
                                    skip = true
                                end
                            else
                                -- Fallback to old behavior if no list provided
                                skip = true
                            end
                        end
                    end
                    
                    if not skip then
                        if #active_chapters >= max_chapters then break end
                        chapter.toc_index = i
                        table.insert(active_chapters, chapter)
                        table.insert(chapter_titles, chapter.title or tostring(i))
                    else
                        AIHelper:log("ChapterAnalyzer: Skipping already-fetched chapter: " .. (chapter.title or tostring(i)))
                    end
                end
            end
        end
    end
    
    -- If no chapters found in TOC, we don't exit; we'll fallback to even sampling later.
    -- However, we still need a count for budget calculations.
    local num_chapters = #active_chapters
    if num_chapters == 0 then
        num_chapters = 20 -- Default budget for even sampling
    end
    
    -- DYNAMIC BUDGET: Scale down for large books to leave room for AI output
    if #active_chapters > 60 then
        -- Very large omnibus: aggressive compression
        total_limit = math.min(total_limit, 60000)
        AIHelper:log("ChapterAnalyzer: Large book detected (" .. num_chapters .. " chapters). Compressed total_limit to " .. total_limit)
    elseif num_chapters > 30 then
        -- Large book: moderate compression
        total_limit = math.min(total_limit, 100000)
        AIHelper:log("ChapterAnalyzer: Medium-large book detected (" .. num_chapters .. " chapters). Compressed total_limit to " .. total_limit)
    end

    -- Calculate budget per chapter
    -- Reserve 20k for the main book_text (last 20k)
    local chapter_total_budget = total_limit - 20000
    local per_chapter_budget = math.floor(chapter_total_budget / num_chapters)
    
    -- Dynamic hard limit based on chapter count
    local max_per_chapter = num_chapters > 60 and 600 or (num_chapters > 30 and 2000 or 3600)
    if per_chapter_budget > max_per_chapter then per_chapter_budget = max_per_chapter end
    
    -- Minimum budget for it to be useful
    if per_chapter_budget < 300 then per_chapter_budget = 300 end
    
    local sample_len = math.floor(per_chapter_budget / 3)
    local samples = {}
    
    if #active_chapters > 0 then
        logger.info("ChapterAnalyzer: Detailed sampling for", #active_chapters, "chapters. Budget per chapter:", per_chapter_budget)
        AIHelper:log("ChapterAnalyzer: Sampling " .. #active_chapters .. " chapters with " .. per_chapter_budget .. " chars each.")
        
        for i, chapter in ipairs(active_chapters) do
            if not ui or not ui.document then break end
            local is_current_chapter = false
            if not is_full_book and current_page and chapter.page and chapter.page <= current_page then
                local next_chapter = toc[chapter.toc_index + 1]
                if not next_chapter or (next_chapter.page and next_chapter.page > current_page) then
                    is_current_chapter = true
                end
            end

            local success, chapter_text = pcall(function()
                if not ui or not ui.document then return "" end
                if is_current_chapter then
                    local end_page = self:getEndPageForCurrentPage(ui, current_page)
                    return self:getTextFromPageRange(ui, chapter.page, end_page, total_limit)
                elseif ui.document.getTextFromXPointers and chapter.xpointer then
                    -- Bounded chapter extraction (#150: prevent multi-chapter DocFragment leaks)
                    local next_ch = toc[chapter.toc_index + 1]
                    local end_xp = next_ch and next_ch.xpointer
                    if not end_xp and ui.document.getEndXPointer then
                        end_xp = ui.document:getEndXPointer()
                    end
                    if end_xp then
                        local txt = ui.document:getTextFromXPointers(chapter.xpointer, end_xp)
                        if txt and #txt > 0 then return txt end
                    end
                    return (ui.document.getTextFromXPointer and ui.document:getTextFromXPointer(chapter.xpointer)) or ""
                elseif ui.document.getTextFromXPointer and chapter.xpointer then
                    -- EPUB fallback
                    return ui.document:getTextFromXPointer(chapter.xpointer)
                end
                return ""
            end)
            
            if success and chapter_text and #chapter_text > 100 then
                local start_txt = utf8_sub(chapter_text, 1, sample_len)
                local mid_start = math.max(1, math.floor(#chapter_text / 2) - math.floor(sample_len / 2))
                local mid_txt = utf8_sub(chapter_text, mid_start, mid_start + sample_len)
                local end_txt = utf8_sub(chapter_text, -sample_len, -1)
                
                table.insert(samples, string.format(
                    "CHAPTER [%s]:\n[EXCERPT_START]: %s\n[EXCERPT_MID]: %s\n[EXCERPT_END]: %s",
                    chapter.title or tostring(i),
                    start_txt, mid_txt, end_txt
                ))
            end
        end
    else
        -- NO TOC FALLBACK: Even sampling across the book
        local max_range = 0
        pcall(function()
            if ui and ui.document then
                max_range = (is_full_book or not current_page) and ui.document:getPageCount() or current_page
            end
        end)
        if max_range and max_range > 0 then
            local num_sections = math.min(20, max_range)
            local step = math.floor(max_range / num_sections)
            local log_msg = (toc and #toc > 0)
                and ("ChapterAnalyzer: No un-fetched chapters found up to page " .. tostring(current_page) .. ". Using even sampling across " .. num_sections .. " sections.")
                or ("ChapterAnalyzer: No TOC found. Using even sampling across " .. num_sections .. " sections.")
            AIHelper:log(log_msg)
            
            for i = 1, num_sections do
                if not ui or not ui.document then break end
                local p = (i - 1) * step + 1
                local success, section_text = pcall(function()
                    if ui and ui.document and ui.document.getPageText then
                        return ui.document:getPageText(p)
                    end
                    return ""
                end)
                
                if success and section_text and #section_text > 100 then
                    table.insert(samples, string.format(
                        "SECTION [%d] (Near Page %d):\n%s",
                        i, p, utf8_sub(section_text, 1, per_chapter_budget)
                    ))
                    table.insert(chapter_titles, "Section " .. i)
                end
            end
        end
    end
    
    return (#samples > 0 and table.concat(samples, "\n\n---\n\n") or nil), chapter_titles
end

function ChapterAnalyzer:countMentions(text, name)
    local count = 0
    local pos = 1
    
    local pattern
    if #name < 4 then
        local safe_name = name:lower():gsub("([%(%)%.%%%+%-%*%?%[%^%$])", "%%%1")
        pattern = "%f[%w]" .. safe_name .. "%f[%W]"
    end
    
    while true do
        local start_pos
        if pattern then
            start_pos = text:lower():find(pattern, pos)
        else
            start_pos = text:lower():find(name:lower(), pos, true)
        end
        if not start_pos then break end
        count = count + 1
        pos = start_pos + 1
    end
    
    return count
end

-- Extract a sentence-aware snippet around a match position in raw text.
-- Returns: ONLY the sentence containing the match,
-- capped at max_len characters.
local function extractSentenceSnippet(text, match_pos, max_len)
    max_len = max_len or 300
    if not text or not match_pos then return "" end

    -- Use pattern matching to find boundaries, which is much faster than byte loops in Lua
    local before = text:sub(1, match_pos - 1)
    local sent_start = 1
    -- Find the last sentence-ending character before the match
    local b_start, b_end = before:find("[.!?\n][^.!?\n]*$")
    if b_start then
        sent_start = b_start + 1
    end

    local after = text:sub(match_pos)
    local sent_end = #text
    -- Find the first sentence-ending character after the match
    local a_start, a_end = after:find("[.!?\n]")
    if a_start then
        sent_end = match_pos + a_start - 1
    end

    -- Trim to max_len if still too long
    if (sent_end - sent_start) > max_len then
        local half = math.floor(max_len / 2)
        sent_start = math.max(sent_start, match_pos - half)
        sent_end = math.min(sent_end, match_pos + half)
    end

    return utf8_sub(text, sent_start, sent_end):gsub("^%s+", ""):gsub("%s+$", "")
end


-- Scan a single TOC entry for occurrences of `name`.
-- Returns a list of { chapter, page, snippet } tables.
function ChapterAnalyzer:findMentionsInChapter(ui, entity, toc_entry, next_toc_entry, yield_fn)
    if not ui or not ui.document or not entity or not entity.name or not toc_entry then return {} end
    if not toc_entry.xpointer then return {} end

    local name = entity.name
    local name_lower = name:lower()
    local chapter_mentions = {}

    -- Load chapter text first so we can use frequency analysis when building terms
    local ok, raw_text = pcall(function()
        if toc_entry.xpointer then
            if type(toc_entry.xpointer) == "string" and toc_entry.xpointer:sub(1, 5) == "page:" then
                local p = tonumber(toc_entry.xpointer:match("page:(%d+)"))
                if p and ui.document.getPageText then
                    local end_p = next_toc_entry and next_toc_entry.xpointer and tonumber(next_toc_entry.xpointer:match("page:(%d+)")) or (ui.document.getTotalPages and ui.document:getTotalPages()) or p
                    if end_p < p then end_p = p end
                    local txt = ""
                    for curr_p = p, end_p do
                        local pt = ui.document:getPageText(curr_p)
                        if type(pt) == "table" then
                            local parts = {}
                            for _, block in ipairs(pt) do
                                if type(block) == "table" then
                                    for _, span in ipairs(block) do
                                        if type(span) == "table" and span.word then
                                            table.insert(parts, span.word)
                                        end
                                    end
                                end
                            end
                            pt = table.concat(parts, " ")
                        end
                        txt = txt .. (pt or "") .. "\n"
                    end
                    return txt
                end
            end
            if ui.document.getTextFromXPointers then
                local end_xp = next_toc_entry and next_toc_entry.xpointer
                if not end_xp and ui.document.getEndXPointer then
                    end_xp = ui.document:getEndXPointer()
                end
                if end_xp then
                    return ui.document:getTextFromXPointers(toc_entry.xpointer, end_xp) or ""
                end
            end
            if ui.document.getTextFromXPointer then
                return ui.document:getTextFromXPointer(toc_entry.xpointer) or ""
            end
        end
        
        -- Fallback for PDF/page-based documents
        if toc_entry.page and ui.document.getPageText then
            local start_pg = tonumber(toc_entry.page)
            local end_pg = next_toc_entry and tonumber(next_toc_entry.page) or (ui.document.getTotalPages and ui.document:getTotalPages()) or start_pg
            if start_pg then
                local txt = ""
                for p = start_pg, end_pg do
                    local pt = ui.document:getPageText(p)
                    if type(pt) == "table" then
                        local parts = {}
                        for _, block in ipairs(pt) do
                            if type(block) == "table" then
                                for _, span in ipairs(block) do
                                    if type(span) == "table" and span.word then
                                        table.insert(parts, span.word)
                                    end
                                end
                            end
                        end
                        pt = table.concat(parts, " ")
                    end
                    txt = txt .. (pt or "") .. "\n"
                end
                return txt
            end
        end
        return ""
    end)
    if not ok or not raw_text or #raw_text < 10 then return {} end

    local text_lower = raw_text:lower()

    -- Count occurrences of a needle in text_lower (used for frequency check)
    local function countIn(needle)
        if not needle or needle == "" then return 0 end
        local escaped = needle:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1")
        local pattern = escaped
        local starts_w = needle:sub(1, 1):match("%w") ~= nil
        local ends_w = needle:sub(-1):match("%w") ~= nil
        if #needle < 4 and starts_w and ends_w then
            pattern = "%f[%w]" .. escaped .. "%f[%W]"
        end
        local n = 0
        local init = 1
        while true do
            local s, e = text_lower:find(pattern, init)
            if not s then break end
            n = n + 1
            init = math.max(e + 1, s + 1)
        end
        return n
    end

    -- Honorifics: fast-path blocklist for known titles.
    -- Short honorifics (< 3 chars) are already caught by the length check;
    -- 3-char ones (mr., mrs, sir, dr., etc.) need explicit listing since they
    -- can have plausible frequency ratios in heavily character-focused chapters.
    local honorifics = {
        ["mr"] = true, ["mr."] = true, ["mrs"] = true, ["mrs."] = true, ["ms"] = true, ["ms."] = true,
        ["dr"] = true, ["dr."] = true, ["sir"] = true, ["rev"] = true, ["rev."] = true, ["lt"] = true, ["lt."] = true,
        ["col"] = true, ["col."] = true, ["sgt"] = true, ["sgt."] = true, ["gen"] = true, ["gen."] = true,
        ["miss"] = true, ["lord"] = true, ["lady"] = true, ["dame"] = true, ["prof"] = true, ["prof."] = true,
        ["capt"] = true, ["capt."] = true, ["st"] = true, ["st."] = true, ["jr"] = true, ["jr."] = true,
        
        -- International
        ["m"] = true, ["m."] = true, ["mme"] = true, ["mme."] = true, ["mlle"] = true, ["mlle."] = true, ["mgr"] = true,
        ["herr"] = true, ["frau"] = true, ["hr"] = true, ["hr."] = true, ["fr"] = true, ["fr."] = true,
        ["sr"] = true, ["sr."] = true, ["sra"] = true, ["sra."] = true, ["don"] = true, ["dona"] = true, ["doña"] = true,
        ["bey"] = true, ["hanım"] = true,
        ["пан"] = true, ["пані"] = true, ["г-н"] = true, ["г-жа"] = true,
    }

    -- 2. Type-Aware Entity Classification
    -- Characters and Historical Figures have a 'role' but not a term 'definition'.
    local is_person = (entity.role ~= nil) and (entity.definition == nil)
    local is_term   = (entity.definition ~= nil)

    -- 1. Calculate the maximum frequency among the full name AND all AI-provided aliases.
    -- This provides a much more robust baseline for what constitutes "too generic".
    local max_base_freq = countIn(name_lower)
    if entity.aliases and type(entity.aliases) == "table" then
        for _, alias in ipairs(entity.aliases) do
            if type(alias) == "string" and #alias > 3 then
                max_base_freq = math.max(max_base_freq, countIn(alias:lower()))
            end
        end
    end
    local name_freq = math.max(1, max_base_freq)

    local function isTooGeneric(term)
        local term_l = term:lower()
        if #term < 2 or honorifics[term_l] then return true end
        -- Relax the multiplier for people and terms to prevent self-suppression in high-frequency fiction
        local limit
        if is_person then
            limit = math.max(10, name_freq * 5)
        elseif is_term then
            limit = math.max(50, name_freq * 10)
        else
            limit = 100
        end
        return countIn(term_l) > limit
    end

    -- Always start with the full name
    local terms = { { s = name_lower, l = #name_lower } }

    if is_person then
        -- Auto-generate first and last name components for people
        local first_name = name:match("^(%S+)")
        local last_name  = name:match("(%S+)$")
        if first_name and first_name ~= name then
            local fl = first_name:lower()
            if not honorifics[fl] and not isTooGeneric(fl) then
                table.insert(terms, { s = fl, l = #fl })
            end
        end
        if last_name and last_name ~= first_name and last_name ~= name then
            local ll = last_name:lower()
            if not honorifics[ll] and not isTooGeneric(ll) then
                table.insert(terms, { s = ll, l = #ll })
            end
        end
    else
        -- For non-people (Terms, Locations), handle articles and variations
        -- a. Strip leading articles (The, A, An, Der, Die, Das, Le, La, El, etc.)
        local stripped = name:match("^[Tt]he%s+(.+)") or 
                         name:match("^[Aa]n?%s+(.+)") or
                         name:match("^[Dd][ie][er]%s+(.+)") or
                         name:match("^[Dd]as%s+(.+)") or
                         name:match("^[Ll][ae]s?%s+(.+)") or
                         name:match("^[Ll]'%s*(.+)") or
                         name:match("^[Ee]l%s+(.+)") or
                         name:match("^[Uu]n[ae]?s?%s+(.+)")

        if stripped and stripped ~= name then
            local sl = stripped:lower()
            -- Bypassing isTooGeneric for direct article stripping; this is a high-value core variation.
            table.insert(terms, { s = sl, l = #sl })
        end
        
        if is_term then
            -- Never split multi-word terms into single-word aliases.
            -- Instead, apply plural/singular variations to the full term name.
            if name_lower:sub(-1) == "s" then
                local singular = name_lower:sub(1, -2)
                if #singular > 3 and not isTooGeneric(singular) then
                    table.insert(terms, { s = singular, l = #singular })
                end
            else
                local plural = name_lower .. "s"
                if not isTooGeneric(plural) then
                    table.insert(terms, { s = plural, l = #plural })
                end
            end
        else
            -- Locations: simple plural/singular variations (existing behavior)
            if name_lower:sub(-1) == "s" then
                local singular = name_lower:sub(1, -2)
                if #singular > 3 then
                    table.insert(terms, { s = singular, l = #singular })
                end
            else
                local plural = name_lower .. "s"
                table.insert(terms, { s = plural, l = #plural })
            end
        end
        
        -- Logging the terms we are about to search for debugging
        local log_terms = {}
        for _, t in ipairs(terms) do table.insert(log_terms, t.s) end
        logger.info("XRayPlugin: Searching for mentions of '" .. name .. "' using variants: " .. table.concat(log_terms, " | "))
    end

    -- 3. Add AI-provided aliases, filtered by the same rules
    if entity.aliases and type(entity.aliases) == "table" then
        for _, alias in ipairs(entity.aliases) do
            if type(alias) == "string" then
                local al = alias:lower()
                if not honorifics[al] and not isTooGeneric(al) then
                    local exists = false
                    for _, t in ipairs(terms) do
                        if t.s == al then exists = true; break end
                    end
                    if not exists then
                        table.insert(terms, { s = al, l = #al })
                    end
                end
            end
        end
    end

    -- 4. Declined forms (Slovak/Czech): also match "Petra"/"Petrovi" for "Peter",
    -- "Bratislave" for "Bratislava", etc.
    if xray_utils:usesInflection(self.plugin or { ui = ui, ai_helper = AIHelper }) then
        local base_count = #terms
        for i = 1, base_count do
            local t = terms[i]
            if not t.s:find("[%s%-]") then
                for _, stem in ipairs(xray_utils:inflectionStems(t.s)) do
                    local exists = false
                    for _, other in ipairs(terms) do
                        if other.inflect and other.s == stem.s then exists = true; break end
                    end
                    if not exists then
                        table.insert(terms, { s = stem.s, l = #stem.s, inflect = stem })
                    end
                end
            end
        end
    end

    local pos = 1

    -- Next match of a term at or after `from`; declined forms also need a valid suffix.
    local function findTerm(t, from)
        if not t.pattern then return text_lower:find(t.s, from, true) end
        if not t.inflect then return text_lower:find(t.pattern, from) end
        while true do
            local s, e = text_lower:find(t.pattern, from)
            if not s then return nil end
            if xray_utils:isInflectionSuffix(t.inflect, text_lower:sub(s + #t.s, e)) then return s end
            from = s + 1
        end
    end

    -- Pre-calculate the first match position for each term.
    -- Enforce strict word boundaries for all single-word terms (no spaces or hyphens)
    -- to prevent substring matches (e.g. "flow" matching "airflow" or "flower").
    for _, t in ipairs(terms) do
        local is_single_word = not t.s:find("[%s%-]")
        if t.inflect then
            -- Whole word = stem + a short declension suffix (UTF-8 letters count as word bytes)
            local safe_s = t.s:gsub("([%(%)%.%%%+%-%*%?%[%^%$])", "%%%1")
            t.pattern = "%f[%a\128-\255]" .. safe_s
                .. string.rep("[%a\128-\255]?", t.inflect.max or xray_utils.INFLECTION_MAX_SUFFIX)
                .. "%f[^%a\128-\255]"
            t.next_p = findTerm(t, pos)
        elseif is_single_word then
            local safe_s = t.s:gsub("([%(%)%.%%%+%-%*%?%[%^%$])", "%%%1")
            local starts_w = safe_s:sub(1, 1):match("%w") ~= nil
            local ends_w = safe_s:sub(-1):match("%w") ~= nil
            if starts_w and ends_w then
                t.pattern = "%f[%w]" .. safe_s .. "%f[%W]"
            else
                t.pattern = safe_s
            end
            t.next_p = text_lower:find(t.pattern, pos)
        else
            t.next_p = text_lower:find(t.s, pos, true)
        end
    end


    local last_yield = os.clock()
    
    while true do
        local min_p = math.huge
        local best_term = nil
        
        for _, t in ipairs(terms) do
            if t.next_p and t.next_p < min_p then
                min_p = t.next_p
                best_term = t
            end
        end
        
        if not best_term then
            break
        end
        
        local match_pos = min_p

        local start_page = tonumber(toc_entry.page) or 1
        local end_page = next_toc_entry and tonumber(next_toc_entry.page) or (ui.document.getTotalPages and ui.document:getTotalPages()) or start_page
        if end_page < start_page then end_page = start_page end
        
        local est_page = start_page
        local total_chars = #raw_text
        if total_chars > 0 and end_page > start_page then
            local fraction = match_pos / total_chars
            est_page = math.floor(start_page + ((end_page - start_page) * fraction))
        end

        table.insert(chapter_mentions, {
            chapter = toc_entry.title or "???",
            page    = est_page,
            snippet = extractSentenceSnippet(raw_text, match_pos, 300),
        })
        
        pos = match_pos + math.max(1, best_term.l or 1)
        
        -- Update ONLY the term we just found. Others are still valid if their next_p >= pos.
        for _, t in ipairs(terms) do
            if not t.next_p or t.next_p < pos then
                t.next_p = findTerm(t, pos)
            end
        end

        -- Yield every 100ms to keep UI alive
        if yield_fn and (os.clock() - last_yield > 0.1) then
            yield_fn()
            last_yield = os.clock()
        end
    end
    return chapter_mentions
end

function ChapterAnalyzer:scanMentionsAsync(ui, entity, toc, min_page, max_page, on_progress, on_complete)
    if not ui or not ui.document or not entity or not entity.name then 
        if on_complete then
            -- Schedule the callback so it executes asynchronously, preventing 
            -- a nil reference crash in the caller's assignment logic.
            local UIManager = require("ui/uimanager")
            UIManager:scheduleIn(0, function() on_complete({}) end)
        end
        return { cancel = function() end } 
    end

    local scan_toc = toc
    if not scan_toc or #scan_toc == 0 then
        local page_count = ui.document:getPageCount() and ui.document:getPageCount() or (ui.document.getTotalPages and ui.document:getTotalPages()) or 100
        local num_sections = math.min(20, page_count)
        local step = math.floor(page_count / num_sections)
        if step < 1 then step = 1 end
        scan_toc = {}
        for idx = 1, num_sections do
            local p = (idx - 1) * step + 1
            table.insert(scan_toc, {
                title = (ui.loc and ui.loc:t("this_page") or "Section") .. " " .. idx,
                page = p,
                xpointer = "page:" .. p
            })
        end
    end

    local UIManager = require("ui/uimanager")
    local cancel_handle = { _cancelled = false }
    function cancel_handle:cancel()
        self._cancelled = true
    end

    local mentions = {}
    local total_chapters = #scan_toc
    
    -- Cooperative multitasking using Coroutines
    local scan_co = coroutine.create(function()
        local last_progress_time = 0
        for i = 1, total_chapters do
            if cancel_handle._cancelled then break end

            local entry = scan_toc[i]
            local next_entry = scan_toc[i + 1]
            
            local start_p = tonumber(entry.page)
            local end_p = next_entry and tonumber(next_entry.page) or math.huge

            if start_p and max_page and start_p > max_page then
                -- Reached spoiler limit
                break
            end
            
            if not (min_page and end_p <= min_page) then
                -- We pass a yield function that will pause the coroutine
                local chapter_mentions = self:findMentionsInChapter(ui, entity, entry, next_entry, function()
                    coroutine.yield()
                end)
                
                -- Filter out mentions that pass max_page or are before min_page (#150: strict boundary without overscan)
                for _, m in ipairs(chapter_mentions) do
                    if not (max_page and m.page and m.page > max_page) and not (min_page and m.page and m.page <= min_page) then
                        table.insert(mentions, m)
                    end
                end

                local now = os.clock()
                if on_progress and (now - last_progress_time >= 0.5 or i == total_chapters) then
                    last_progress_time = now
                    on_progress(mentions, i, total_chapters)
                end
            end

            -- Incremental GC step to keep memory bounded without freezing the event loop
            collectgarbage("step", 100)
            
            -- Yield after each chapter
            coroutine.yield()
        end
        
        collectgarbage("collect")

        if on_complete and not cancel_handle._cancelled then 
            on_complete(mentions) 
        end
    end)

    local function resumeScan()
        if cancel_handle._cancelled or not ui or not ui.document then return end
        
        local ok, err = coroutine.resume(scan_co)
        if not ok then
            logger.error("XRayPlugin: Mentions scan error:", err)
            if on_complete and not cancel_handle._cancelled then on_complete(mentions) end
            return
        end

        if coroutine.status(scan_co) ~= "dead" then
            -- Schedule next chunk with device-aware delay
            local delay = 0.02
            if xray_utils and xray_utils.isLowPowerForScan and xray_utils:isLowPowerForScan() then
                delay = 0.06
            end
            UIManager:scheduleIn(delay, resumeScan)
        end
    end

    -- Start the scan
    UIManager:scheduleIn(0.2, resumeScan)
    
    return cancel_handle
end

function ChapterAnalyzer:scanStoryPresence(ui, story, entities)
    if not ui or not story or not entities or #entities == 0 then return {} end
    local start_p = story.start_page or 1
    local end_p = story.end_page or (start_p + 20)
    local text = self:getTextFromPageRange(ui, start_p, end_p, 80000)
    if not text or text == "" then return {} end
    local text_lower = text:lower()

    local found = {}
    for _, e in ipairs(entities) do
        local name = e.name
        if name and type(name) == "string" then
            local is_multi = name:find("%s") ~= nil
            local is_long_single = #name >= 5
            if is_multi or is_long_single then
                local pat = name:lower()
                local matched = false
                if is_multi then
                    if text_lower:find(pat, 1, true) then matched = true end
                else
                    local escaped = pat:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
                    if text_lower:find("%f[%a]" .. escaped .. "%f[%A]") then matched = true end
                end
                if not matched and e.aliases and type(e.aliases) == "table" then
                    for _, al in ipairs(e.aliases) do
                        if type(al) == "string" and (#al >= 4) then
                            local a_multi = al:find("%s") ~= nil
                            if a_multi and text_lower:find(al:lower(), 1, true) then
                                matched = true; break
                            elseif not a_multi and #al >= 5 then
                                local esc_al = al:lower():gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
                                if text_lower:find("%f[%a]" .. esc_al .. "%f[%A]") then
                                    matched = true; break
                                end
                            end
                        end
                    end
                end
                if matched then
                    table.insert(found, name)
                end
            end
        end
    end
    return found
end

function ChapterAnalyzer:scanStoryPresenceAsync(ui, stories, entities, on_progress, on_done)
    local UIManager = require("ui/uimanager")
    if not ui or not ui.document or not stories or #stories == 0 or not entities or #entities == 0 then
        if on_done then UIManager:scheduleIn(0, function() on_done({}) end) end
        return { cancel = function() end }
    end

    local cancel_handle = { _cancelled = false }
    function cancel_handle:cancel()
        self._cancelled = true
    end

    local story_presence = {}
    local total_stories = #stories

    local scan_co = coroutine.create(function()
        for idx, story in ipairs(stories) do
            if cancel_handle._cancelled then break end
            local found_names = self:scanStoryPresence(ui, story, entities)
            for _, name in ipairs(found_names) do
                story_presence[name] = story_presence[name] or {}
                story_presence[name][story.story_id] = true
            end

            if on_progress then
                on_progress(idx, total_stories)
            end

            collectgarbage("step", 50)
            coroutine.yield()
        end

        if on_done and not cancel_handle._cancelled then
            on_done(story_presence)
        end
    end)

    local function resumeScan()
        if cancel_handle._cancelled or not ui or not ui.document then return end
        local ok, err = coroutine.resume(scan_co)
        if not ok then
            logger.error("XRayPlugin: scanStoryPresenceAsync error:", err)
            if on_done and not cancel_handle._cancelled then on_done(story_presence) end
            return
        end
        if coroutine.status(scan_co) ~= "dead" then
            UIManager:scheduleIn(0.02, resumeScan)
        end
    end

    UIManager:scheduleIn(0.1, resumeScan)
    return cancel_handle
end

return ChapterAnalyzer
