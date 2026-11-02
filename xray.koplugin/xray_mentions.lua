-- X-Ray Mentions Logic and UI

local UIManager = require("ui/uimanager")
local Menu = require("ui/widget/menu")
local Device = require("device")
local Screen = Device.screen
local Font = require("ui/font")
local ButtonDialog = require("ui/widget/buttondialog")
local Event = require("ui/event")

local plugin_path = ((...) or ""):match("(.-)[^%.]+$") or ""
local XRayConfig = require(plugin_path .. "xray_config")

local function safe_utf8_truncate(s, max_bytes)
    if not s or #s <= max_bytes then return s or "" end
    local out, i, len = {}, 1, #s
    while i <= len do
        local lead = s:byte(i)
        local width = (lead < 0x80 and 1) or (lead < 0xE0 and 2)
            or (lead < 0xF0 and 3) or (lead < 0xF5 and 4) or 1
        if (i + width - 1) > max_bytes then
            break
        end
        out[#out + 1] = s:sub(i, i + width - 1)
        i = i + width
    end
    return table.concat(out)
end

local M = {}

function M:showHighlightOverlay(boxes)
    self.scroll_highlight_boxes = boxes
    if self.ui and self.ui.view then
        local plugin = self
        local banner_h = self._banner_natural_h or 100
        local screen_h = Screen:getHeight()
        local clip_bottom = screen_h - banner_h

        self.ui.view:registerViewModule("xray_highlights", {
            paintTo = function(this, bb, x, y)
                if not plugin.scroll_highlight_boxes then return end
                for _, box in ipairs(plugin.scroll_highlight_boxes) do
                    if box.x and box.y and box.w and box.h and box.y < clip_bottom then
                        local draw_h = math.min(box.h, clip_bottom - box.y)
                        if draw_h > 0 then
                            -- Use invertRect for guaranteed E-ink contrast (matches native temp_drawer)
                            bb:invertRect(box.x, box.y, box.w, draw_h)
                        end
                    end
                end
            end
        })
        UIManager:setDirty(self.ui.view.dialog, "ui")
        local is_pb = Device and Device.isPocketBook and Device:isPocketBook()
        if not is_pb and UIManager and type(UIManager.forceRePaint) == "function" then
            UIManager:forceRePaint()
        end
    end
end

function M:clearHighlightOverlay()
    self.scroll_highlight_boxes = nil
    if self.ui and self.ui.view and self.ui.view.view_modules then
        self.ui.view.view_modules["xray_highlights"] = nil
        UIManager:setDirty(self.ui.view.dialog, "ui")
    end
end




-- Safe helper to merge overlapping bounding boxes (prevents double darkening of matching aliases)
local function _mergeBoxes(boxes)
    if not boxes or #boxes == 0 then return {} end
    local merged = {}
    for _, box in ipairs(boxes) do
        if box.x and box.y and box.w and box.h then
            local placed = false
            for _, m in ipairs(merged) do
                -- Check if they overlap vertically (on the same line or extremely close)
                local y_overlap = math.max(0, math.min(box.y + box.h, m.y + m.h) - math.max(box.y, m.y))
                if y_overlap > 0 or math.abs(box.y - m.y) < 5 then
                    -- Check if they overlap horizontally
                    local x_overlap = math.max(0, math.min(box.x + box.w, m.x + m.w) - math.max(box.x, m.x))
                    if x_overlap > 0 or (box.x <= m.x + m.w and m.x <= box.x + box.w) then
                        -- Merge them
                        local min_x = math.min(box.x, m.x)
                        local min_y = math.min(box.y, m.y)
                        local max_x = math.max(box.x + box.w, m.x + m.w)
                        local max_y = math.max(box.y + box.h, m.y + m.h)
                        m.x = min_x
                        m.y = min_y
                        m.w = max_x - min_x
                        m.h = max_y - min_y
                        placed = true
                        break
                    end
                end
            end
            if not placed then
                table.insert(merged, {
                    x = box.x,
                    y = box.y,
                    w = box.w,
                    h = box.h,
                })
            end
        end
    end
    
    -- Recursively merge until no more changes happen (transitive overlaps)
    local final_merged = {}
    local changed = false
    for _, box in ipairs(merged) do
        local placed = false
        for _, m in ipairs(final_merged) do
            local y_overlap = math.max(0, math.min(box.y + box.h, m.y + m.h) - math.max(box.y, m.y))
            if y_overlap > 0 or math.abs(box.y - m.y) < 5 then
                local x_overlap = math.max(0, math.min(box.x + box.w, m.x + m.w) - math.max(box.x, m.x))
                if x_overlap > 0 or (box.x <= m.x + m.w and m.x <= box.x + box.w) then
                    local min_x = math.min(box.x, m.x)
                    local min_y = math.min(box.y, m.y)
                    local max_x = math.max(box.x + box.w, m.x + m.w)
                    local max_y = math.max(box.y + box.h, m.y + m.h)
                    m.x = min_x
                    m.y = min_y
                    m.w = max_x - min_x
                    m.h = max_y - min_y
                    placed = true
                    changed = true
                    break
                end
            end
        end
        if not placed then
            table.insert(final_merged, box)
        end
    end
    
    if changed then
        return _mergeBoxes(final_merged)
    else
        return final_merged
    end
end


-- Safe helper for current page
local function _getCurrentPage(plugin)
    if not plugin then return 1 end
    if plugin.last_pageno then return plugin.last_pageno end
    if plugin.getCurrentDocPage then
        local ok, pg = pcall(function() return plugin:getCurrentDocPage() end)
        if ok and pg then return pg end
    end
    if plugin.getCurrentPage then
        local ok, pg = pcall(function() return plugin:getCurrentPage() end)
        if ok and pg then return pg end
    end
    if plugin.ui and plugin.ui.paging and plugin.ui.paging.getCurrentPage then
        local ok, pg = pcall(function() return plugin.ui.paging:getCurrentPage() end)
        if ok and pg then return pg end
    end
    if plugin.ui and plugin.ui.pageno then
        return plugin.ui.pageno
    end
    return 1
end

-- Removed background scanning functions

function M:saveMentionsToCache()
    if self.destroyed or not self.ui or not self.ui.document then return end
    local doc_file = self.ui.document.file
    if not doc_file then return end

    if not self.cache_manager then
        self.cache_manager = require(plugin_path .. "xray_cachemanager"):new()
    end
    
    if not self.book_data then
        self.book_data = self.cache_manager:loadCache(doc_file) or {}
    end
    local updated = self.book_data
    
    -- Update only the entity lists that contain the new mentions
    updated.characters         = self.characters
    updated.historical_figures = self.historical_figures
    updated.locations          = self.locations
    updated.terms              = self.terms
    updated.timeline           = self.timeline
    
    if self.book_data then
        updated.book_title      = self.book_data.book_title or updated.book_title
        updated.author          = self.book_data.author or updated.author
        updated.last_fetch_page = self.book_data.last_fetch_page or updated.last_fetch_page
    end
    
    if self.author_info then
        updated.author_info = self.author_info
    end

    self.cache_manager:asyncSaveCache(doc_file, updated)
end

function M:showMentionsForEntity(entity)
    if self.destroyed or not self.ui or not self.ui.document then return end
    if not entity then return end
    if not self.return_page_origin then
        self.return_page_origin = (self.getCurrentPage and self:getCurrentPage()) or _getCurrentPage(self)
    end
    local name = entity.name or "???"
    if (self.active_mention_scan and self.active_mention_scan.entity_name == name) then
        self:showMentionsMenu(entity); return
    end
    
    -- If there's a running scan for a DIFFERENT entity, cancel it to avoid resource conflicts
    if self.active_mention_scan and self.active_mention_scan.cancel_handle then
        self.active_mention_scan.cancel_handle:cancel()
        self.active_mention_scan = nil
    end

    if not self.chapter_analyzer then
        local ChapterAnalyzer = require(plugin_path .. "xray_chapteranalyzer")
        self.chapter_analyzer = ChapterAnalyzer:new{ plugin = self }
    end

    local utils = require(plugin_path .. "xray_utils")
    local toc = utils:flattenTOC(self.ui and self.ui.document and self.ui.document.getToc and self.ui.document:getToc())
    local spoiler_free = (self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.spoiler_setting or "spoiler_free") == "spoiler_free"
    
    local story = nil
    if self.isAnthologyMode and self:isAnthologyMode() then
        local s_id = entity.story_id or (self.resolveEntityStory and select(1, self:resolveEntityStory(entity)))
        local custom_depth = self.book_data and self.book_data.story_toc_depth
        local story_map = self.chapter_analyzer:getStoryMap(self.ui, custom_depth)
        if s_id and story_map then
            story = (story_map.by_id and story_map.by_id[s_id]) or (story_map.stories and (function()
                for _, s in ipairs(story_map.stories) do
                    if s.story_id == s_id then return s end
                end
            end)())
        end
        if not story and self.getCurrentStory then
            story = self:getCurrentStory()
        end
    end

    if story and story.start_toc_idx and story.end_toc_idx and #toc > 0 then
        local sliced_toc = {}
        for i = story.start_toc_idx, story.end_toc_idx do
            if toc[i] then table.insert(sliced_toc, toc[i]) end
        end
        if #sliced_toc > 0 then
            toc = sliced_toc
        end
    end

    local max_page = nil
    if story and story.end_page then
        max_page = spoiler_free and math.min(_getCurrentPage(self), story.end_page) or story.end_page
    else
        max_page = spoiler_free and _getCurrentPage(self) or nil
    end

    local min_page = entity.last_mention_page
    if story and story.start_page then
        min_page = math.max(min_page or story.start_page, story.start_page)
    end
    
    local target_end = max_page or (story and story.end_page) or math.huge
    local needs_scan = false
    if max_page == nil then
        if entity.last_mention_page ~= math.huge then
            needs_scan = true
        end
    else
        if not entity.last_mention_page or entity.last_mention_page < max_page then
            needs_scan = true
        end
    end
    
    if not needs_scan then
        self:showMentionsMenu(entity)
        return
    end

    self.active_mention_scan = { entity_name = name, chapter_idx = 0, total_chapters = #toc, cancel_handle = nil }
    self.active_mention_scan.cancel_handle = self.chapter_analyzer:scanMentionsAsync(
        self.ui, entity, toc, min_page, max_page,
        function(mentions_so_far, chapter_idx, total_chapters)
            if self.active_mention_scan and self.active_mention_scan.entity_name == name then
                self.active_mention_scan.chapter_idx = chapter_idx
                self.active_mention_scan.total_chapters = total_chapters
                -- Just update the scanning text, don't append incomplete mentions yet
                if self.mentions_menu then self:updateMentionsMenuInPlace(entity) end
            end
        end,
        function(new_mentions)
            if self.active_mention_scan and self.active_mention_scan.entity_name == name then self.active_mention_scan = nil end
            entity.mentions = entity.mentions or {}
            for _, m in ipairs(new_mentions) do table.insert(entity.mentions, m) end
            table.sort(entity.mentions, function(a, b) return (a.page or 0) < (b.page or 0) end)
            
            entity.last_mention_page = target_end
            
            self:saveMentionsToCache()
            if self.mentions_menu then self:updateMentionsMenuInPlace(entity) end
        end
    )
    self:showMentionsMenu(entity)
end

function M:buildMentionsMenuItems(entity)
    local items = {}
    local name = entity.name or "???"
    local raw_mentions = entity.mentions or {}
    local is_spoiler_free = (self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.spoiler_setting or "spoiler_free") == "spoiler_free"
    local cur_page = _getCurrentPage(self)

    local story = nil
    if self.isAnthologyMode and self:isAnthologyMode() then
        local s_id = entity.story_id or (self.resolveEntityStory and select(1, self:resolveEntityStory(entity)))
        local custom_depth = self.book_data and self.book_data.story_toc_depth
        if not self.chapter_analyzer then
            local ChapterAnalyzer = require(plugin_path .. "xray_chapteranalyzer")
            self.chapter_analyzer = ChapterAnalyzer:new{ plugin = self }
        end
        local story_map = self.chapter_analyzer:getStoryMap(self.ui, custom_depth)
        if s_id and story_map then
            story = (story_map.by_id and story_map.by_id[s_id]) or (story_map.stories and (function()
                for _, s in ipairs(story_map.stories) do
                    if s.story_id == s_id then return s end
                end
            end)())
        end
    end

    local mentions = {}
    for _, m in ipairs(raw_mentions) do
        local p = tonumber(m.page)
        local page_ok = not is_spoiler_free or not cur_page or not p or p <= cur_page
        if page_ok and story and story.start_page and story.end_page and p then
            if p < story.start_page or p > story.end_page then
                page_ok = false
            end
        end
        if page_ok then
            table.insert(mentions, m)
        end
    end
    local is_scanning = self.active_mention_scan and self.active_mention_scan.entity_name == name
    
    if is_scanning then
        local scan_tmpl = self.loc:t("mentions_scanning")
        if scan_tmpl == "mentions_scanning" then scan_tmpl = "Scanning... %1 of %2 chapters" end
        local scan_text = scan_tmpl:gsub("%%1", tostring(self.active_mention_scan.chapter_idx)):gsub("%%2", tostring(self.active_mention_scan.total_chapters))
        table.insert(items, { text = "\xE2\x8F\xB3 " .. scan_text, keep_menu_open = true, callback = function() end })
        table.insert(items, { text = "\xE2\x9C\x96 " .. (self.loc:t("close") or "Close"), keep_menu_open = true, callback = function() if self.mentions_menu then UIManager:close(self.mentions_menu); self.mentions_menu = nil end end, separator = true })
    else
        table.insert(items, { text = "\xe2\x86\xba " .. (self.loc:t("mentions_refresh") or "Refresh Mentions"), keep_menu_open = true, callback = function()
            -- Stop any active scan
            if self.active_mention_scan and self.active_mention_scan.cancel_handle then 
                self.active_mention_scan.cancel_handle:cancel() 
            end
            self.active_mention_scan = nil
            -- Clear data
            entity.mentions = {}; entity.last_mention_page = nil; 
            -- Re-trigger logic (it will see needs_scan = true and min_page = nil)
            self:showMentionsForEntity(entity)
        end, separator = true })
    end

    if not is_scanning and (#mentions == 0) then
        local none_tmpl = self.loc:t("mentions_none")
        if none_tmpl == "mentions_none" then none_tmpl = "No mentions found for '%s' yet." end
        table.insert(items, { text = none_tmpl:format(name), keep_menu_open = true, callback = function() end })
        return items
    end

    table.sort(mentions, function(a, b) return (a.page or 0) < (b.page or 0) end)

    for _, m in ipairs(mentions) do
        local pg = m.page
        local snippet = m.snippet or ""
        if #snippet > 100 then snippet = safe_utf8_truncate(snippet, 100):gsub("%s%S*$", "") .. "…" end
        table.insert(items, {
            text = "p." .. tostring(pg) .. " \xE2\x80\x94 " .. (m.chapter or "") .. ((snippet ~= "") and ("\n" .. snippet) or ""),
            keep_menu_open = true,
            callback = function()
                local return_pg = self.return_page_origin or _getCurrentPage(self)
                self.return_page_origin = return_pg
                
                self.pending_return_banner = {
                    return_page = return_pg,
                    entity = entity,
                    mentions = mentions
                }
                
                self:closeAllMenus()
                UIManager:nextTick(function()
                    self.ui:handleEvent(Event:new("GotoPage", pg))
                end)
            end,
        })
    end
    return items
end

function M:updateMentionsMenuInPlace(entity)
    if not self.mentions_menu then return end
    if self.mentions_menu.raw_items ~= nil then
        self.mentions_menu.entity = entity
        self.mentions_menu.raw_items = entity.mentions or {}
        local is_scanning = self.active_mention_scan and self.active_mention_scan.entity_name == (entity and entity.name)
        if is_scanning then
            local now = os.clock()
            if not self._last_mentions_ui_rebuild or (now - self._last_mentions_ui_rebuild >= 0.5) then
                self._last_mentions_ui_rebuild = now
                self.mentions_menu:prepareItems()
                self.mentions_menu:buildUI()
                UIManager:setDirty(self.mentions_menu, "ui")
            end
        else
            self._last_mentions_ui_rebuild = nil
            self.mentions_menu:prepareItems()
            self.mentions_menu:buildUI()
            UIManager:setDirty(self.mentions_menu, "ui")
        end
    elseif self.mentions_menu.switchItemTable then
        local items = self:buildMentionsMenuItems(entity)
        local name = entity.name or "???"
        local title = (self.loc:t("mentions_title") or "Mentions: %s"):format(name)
        pcall(function() self.mentions_menu:switchItemTable(title, items) end)
    end
end

function M:showMentionsMenu(entity)
    if not entity then return end
    
    -- Unconditionally clear any existing menu to prevent stale states
    if self.mentions_menu then
        local m = self.mentions_menu
        self.mentions_menu = nil
        pcall(function() UIManager:close(m, "ui") end)
    end

    local EntityListOverlay = require(plugin_path .. "xray_entity_list")
    self.mentions_menu = EntityListOverlay:new{
        mode = "mentions",
        entity = entity,
        raw_items = entity.mentions or {},
        plugin = self,
        modal = true,
        covers_fullscreen = true,
        on_close_callback = function()
            if self.active_mention_scan and self.active_mention_scan.cancel_handle then
                self.active_mention_scan.cancel_handle:cancel()
                self.active_mention_scan = nil
            end
            self.mentions_menu = nil
        end,
    }
    UIManager:show(self.mentions_menu, "ui")
end

function M:highlightMentionsOnPage(page, entity)
    if not self.ui or not self.ui.document or not self.ui.view or not entity then return end
    if self.isAnthologyMode and self:isAnthologyMode() and type(entity) == "table" then
        local s_id = entity.story_id or (self.resolveEntityStory and select(1, self:resolveEntityStory(entity)))
        if s_id and self.chapter_analyzer then
            local custom_depth = self.book_data and self.book_data.story_toc_depth
            local story = self.chapter_analyzer:getStoryForPage(self.ui, page, custom_depth)
            if story and story.story_id ~= s_id then
                return
            end
        end
    end
    
    local ok, err = pcall(function()
        local names_to_search = {}
        if type(entity) == "table" then
            table.insert(names_to_search, entity.name)
            
            local honorifics = { ["mr"]=true, ["mrs"]=true, ["ms"]=true, ["miss"]=true, ["dr"]=true, ["sir"]=true, ["lord"]=true, ["lady"]=true, ["professor"]=true, ["the"]=true, ["and"]=true }
            
            -- Dynamically extract significant word parts (like first/last name) for highlighting
            if entity.name:match("%s") then
                for w in entity.name:gmatch("%S+") do
                    local clean_w = w:gsub("[%p%s]+", "")
                    if #clean_w > 3 and not honorifics[clean_w:lower()] then
                        table.insert(names_to_search, clean_w)
                    end
                end
            end
            
            if entity.aliases and type(entity.aliases) == "table" then
                for _, alias in ipairs(entity.aliases) do
                    if type(alias) == "string" and alias ~= "" then
                        table.insert(names_to_search, alias)
                        -- Also split multi-word aliases
                        if alias:match("%s") then
                            for w in alias:gmatch("%S+") do
                                local clean_w = w:gsub("[%p%s]+", "")
                                if #clean_w > 3 and not honorifics[clean_w:lower()] then
                                    table.insert(names_to_search, clean_w)
                                end
                            end
                        end
                    end
                end
            end
            
            -- Deduplicate
            local unique_names = {}
            local final_names = {}
            for _, n in ipairs(names_to_search) do
                local nl = n:lower()
                if not unique_names[nl] then
                    unique_names[nl] = true
                    table.insert(final_names, n)
                end
            end
            names_to_search = final_names
        else
            table.insert(names_to_search, entity)
        end

        local combined_res = {}
        for _, name in ipairs(names_to_search) do
            if self.log then self:log("XRayPlugin: highlightMentionsOnPage searching for name/alias: " .. tostring(name)) end
            local res = self.ui.document:findAllText(name, true, 0, 500, false)
            if res and #res > 0 then
                for _, r in ipairs(res) do
                    table.insert(combined_res, r)
                end
            end
        end
        
        if self.log then self:log("XRayPlugin: findAllText combined matches: " .. tostring(#combined_res)) end
        
        if #combined_res > 0 then
            local merged_boxes = {}
            local scroll_highlighted = false
            
            if self.ui.rolling then
                if self.log then self:log("XRayPlugin: Processing matches in SCROLL mode") end
                -- Scroll mode (XPointers)
                local Screen = require("device").screen
                local screen_h = Screen and Screen:getHeight() or 1000
                local has_screen_boxes = false
                
                for _, r in ipairs(combined_res) do
                    if self.ui.document.getScreenBoxesFromPositions then
                        local boxes = self.ui.document:getScreenBoxesFromPositions(r.start, r["end"], true)
                        if boxes then
                            for _, box in ipairs(boxes) do
                                if box.y and box.y >= 0 and box.y < screen_h then
                                    table.insert(merged_boxes, box)
                                    has_screen_boxes = true
                                end
                            end
                        end
                    end
                end
                
                -- Fallback to native single selection highlight if no boxes were generated
                if not has_screen_boxes then
                    for _, r in ipairs(combined_res) do
                        if not scroll_highlighted then
                            if self.ui.document.getTextFromXPointers then
                                self.ui.document:getTextFromXPointers(r.start, r["end"], true)
                            end
                            scroll_highlighted = true
                        end
                    end
                end
            else
                if self.log then self:log("XRayPlugin: Processing matches in PAGINATED mode") end
                -- Paginated mode
                for _, r in ipairs(combined_res) do
                    -- In paginated mode, r.start is the 1-based page number
                    if r.start == page then
                        if r.boxes then
                            for _, box in ipairs(r.boxes) do
                                local page_box = self.ui.document:nativeToPageRectTransform(page, box)
                                if page_box then
                                    table.insert(merged_boxes, page_box)
                                end
                            end
                        end
                    end
                end
            end

            
            merged_boxes = _mergeBoxes(merged_boxes)
            if self.log then self:log("XRayPlugin: Generated " .. #merged_boxes .. " highlight boxes") end
            
            if #merged_boxes > 0 then
                if self.ui.rolling then
                    self:showHighlightOverlay(merged_boxes)
                else
                    self.ui.view.highlight.temp[page] = merged_boxes
                end
            end

            
            if not self.ui.rolling and (#merged_boxes > 0 or scroll_highlighted) then
                if self.log then self:log("XRayPlugin: Triggering UI repaint...") end
                -- Attempt multiple ways to trigger a repaint safely
                if UIManager then
                    if self.ui.view.dialog then UIManager:setDirty(self.ui.view.dialog, "ui") end
                    if self.ui then UIManager:setDirty(self.ui, "ui") end
                    UIManager:forceRePaint()
                end
                if self.ui.handleEvent then
                    self.ui:handleEvent(Event:new("Redraw"))
                end
            end
        end
    end)
    if not ok then
        if self.log then self:log("XRayPlugin: ERROR inside highlightMentionsOnPage: " .. tostring(err)) end
    end
end

function M:showReturnBanner(return_page, entity, mentions, current_page)
    if self.return_banner then UIManager:close(self.return_banner); self.return_banner = nil end

    local plugin = self
    local ret_pg = return_page or plugin.return_page_origin or (plugin.getCurrentPage and plugin:getCurrentPage()) or _getCurrentPage(plugin)
    plugin.return_page_origin = ret_pg

    local entity_name = type(entity) == "table" and entity.name or tostring(entity)
    local title = (self.loc:t("mentions_at_location") or "Mention: %s"):format(entity_name)
    
    local unique_pages = {}
    local page_to_idx = {}
    if mentions then
        for _, m in ipairs(mentions) do
            if m.page and not page_to_idx[m.page] then
                table.insert(unique_pages, m.page)
                page_to_idx[m.page] = #unique_pages
            end
        end
    end
    local current_pg_idx = page_to_idx[current_page] or 1
    local prev_enabled = current_pg_idx > 1
    local next_enabled = current_pg_idx < #unique_pages

    -- ButtonDialog is stable. To fix "pretty" and "middle", we customize it.
    local buttons = {{
        {
            text = prev_enabled and "\xE2\x97\x80" or "\xE2\x94\x81", -- Arrow vs Bar
            callback = function()
                if not prev_enabled then return end
                local prev_pg = unique_pages[current_pg_idx - 1]
                plugin.pending_return_banner = { return_page = ret_pg, entity = entity, mentions = mentions }
                plugin:_doReturnJump(prev_pg)
            end,
        },
        {
            text = (self.loc:t("back_to_reading") or "Back"),
            callback = function() plugin:_doReturnJump(ret_pg) end,
        },
        {
            text = "\xE2\x9C\x95", -- Close icon
            callback = function()
                UIManager:nextTick(function()
                    if plugin.return_banner then UIManager:close(plugin.return_banner) end
                end)
            end,
        },
        {
            text = next_enabled and "\xE2\x96\xB6" or "\xE2\x94\x81",
            callback = function()
                if not next_enabled then return end
                local next_pg = unique_pages[current_pg_idx + 1]
                plugin.pending_return_banner = { return_page = ret_pg, entity = entity, mentions = mentions }
                plugin:_doReturnJump(next_pg)
            end,
        },
    }}

    self.return_banner = ButtonDialog:new{
        title = title,
        buttons = buttons,
        is_borderless = true,
        width = Screen:getWidth(),
        show_close_button = false,
    }
    
    -- STABILITY SECRET: Override onCloseWidget to ensure highlights/references clear when closed by tap-off or button click
    self.return_banner.onCloseWidget = function(this)
        UIManager:setDirty(nil, function()
            return "flashui", this.movable.dimen
        end)
        plugin.return_banner = nil
        plugin.return_page_origin = nil
        pcall(function()
            if plugin.clearHighlightOverlay then
                plugin:clearHighlightOverlay()
            end
            if plugin.ui.view and plugin.ui.view.highlight then
                plugin.ui.view.highlight.temp = {}
            end
            if plugin.ui.rolling and plugin.ui.document and plugin.ui.document.clearSelection then
                plugin.ui.document:clearSelection()
            end
            if UIManager and type(UIManager.forceRePaint) == "function" then
                UIManager:forceRePaint()
            end
        end)
    end
    
    -- STABILITY SECRET: Override recenter to force it to the bottom (shifted up slightly for progress bar)
    local bottom_offset = 32
    self.return_banner.recenter = function(this)
        if this.movable and this.movable.dimen then
            this.movable.dimen.x = 0
            this.movable.dimen.y = Screen:getHeight() - this.movable.dimen.h - bottom_offset
        end
        this.dimen = this.movable and this.movable.dimen
    end

    -- Force the CenterContainer wrapper to position content at the bottom with bottom_offset
    if self.return_banner[1] then
        self.return_banner[1].paintTo = function(this, bb, x, y)
            local content_size = this[1]:getSize()
            local x_pos = x + math.floor((this.dimen.w - content_size.w) / 2)
            local y_pos = y + this.dimen.h - content_size.h - bottom_offset
            this[1]:paintTo(bb, x_pos, y_pos)
        end
    end
    
    -- Save natural height for highlight clipping (including the offset shift)
    self._banner_natural_h = ((self.return_banner.movable and self.return_banner.movable.dimen and self.return_banner.movable.dimen.h) or 100) + bottom_offset
    
    UIManager:show(self.return_banner)
    if UIManager and type(UIManager.forceRePaint) == "function" then
        UIManager:forceRePaint()
    end
    
    plugin:highlightMentionsOnPage(current_page, entity)
    
    self.is_programmatic_navigation = true
    if UIManager and type(UIManager.scheduleIn) == "function" then
        UIManager:scheduleIn(0.5, function()
            self.is_programmatic_navigation = nil
        end)
    else
        self.is_programmatic_navigation = nil
    end
end

function M:showImageReturnBanner(return_page, image_entry, current_page)
    if self.return_banner then UIManager:close(self.return_banner); self.return_banner = nil end

    local plugin = self
    local ret_pg = return_page or plugin.return_page_origin or (plugin.getCurrentPage and plugin:getCurrentPage()) or _getCurrentPage(plugin)
    plugin.return_page_origin = ret_pg

    local image_title = (image_entry and image_entry.title) or (self.loc and self.loc:t("illustration") or "Illustration")
    local title = image_title
    if current_page and tonumber(current_page) then
        title = string.format("%s · Page %d", image_title, tonumber(current_page))
    end

    local buttons = {{
        {
            text = (self.loc and self.loc:t("back_to_reading") or "Back to Reading"),
            callback = function() plugin:_doReturnJump(ret_pg) end,
        },
        {
            text = (self.loc and self.loc:t("menu_images") or "Images & Maps"),
            callback = function()
                UIManager:nextTick(function()
                    if plugin.resumeImagesFeature then
                        plugin:resumeImagesFeature()
                    elseif plugin.showImages then
                        plugin:showImages()
                    end
                end)
            end,
        },
        {
            text = "\xE2\x9C\x95", -- Close icon
            callback = function()
                UIManager:nextTick(function()
                    if plugin.return_banner then UIManager:close(plugin.return_banner) end
                end)
            end,
        },
    }}

    self.return_banner = ButtonDialog:new{
        title = title,
        buttons = buttons,
        is_borderless = true,
        width = Screen:getWidth(),
        show_close_button = false,
    }

    self.return_banner.onCloseWidget = function(this)
        UIManager:setDirty(nil, function()
            return "flashui", this.movable.dimen
        end)
        plugin.return_banner = nil
        plugin.return_page_origin = nil
    end

    local bottom_offset = 32
    self.return_banner.recenter = function(this)
        if this.movable and this.movable.dimen then
            this.movable.dimen.x = 0
            this.movable.dimen.y = Screen:getHeight() - this.movable.dimen.h - bottom_offset
        end
        this.dimen = this.movable and this.movable.dimen
    end

    if self.return_banner[1] then
        self.return_banner[1].paintTo = function(this, bb, x, y)
            local content_size = this[1]:getSize()
            local x_pos = x + math.floor((this.dimen.w - content_size.w) / 2)
            local y_pos = y + this.dimen.h - content_size.h - bottom_offset
            this[1]:paintTo(bb, x_pos, y_pos)
        end
    end

    UIManager:show(self.return_banner)
    local is_pb = Device and Device.isPocketBook and Device:isPocketBook()
    if not is_pb and UIManager and type(UIManager.forceRePaint) == "function" then
        UIManager:forceRePaint()
    end

    self.is_programmatic_navigation = true
    if UIManager and type(UIManager.scheduleIn) == "function" then
        UIManager:scheduleIn(0.5, function()
            self.is_programmatic_navigation = nil
        end)
    else
        self.is_programmatic_navigation = nil
    end
end

function M:_doReturnJump(return_page)
    local target_page = return_page or self.return_page_origin or (self.getCurrentPage and self:getCurrentPage()) or (self.last_pageno or 1)
    if not target_page then return end
    self.is_programmatic_navigation = true
    if self.return_banner then
        local banner = self.return_banner
        self.return_banner = nil
        self.return_page_origin = nil
        pcall(function() UIManager:close(banner) end)
    else
        self.return_page_origin = nil
    end
    self:clearHighlightOverlay()
    
    -- Sync repaint to clear screen boxes before transitioning page
    if UIManager and type(UIManager.forceRePaint) == "function" then
        UIManager:forceRePaint()
    end
    if self.ui and self.ui.handleEvent then
        self.ui:handleEvent(Event:new("GotoPage", target_page))
    elseif self.ui and self.ui.document and self.ui.document.gotoPage then
        self.ui.document:gotoPage(target_page)
    end
    if UIManager and type(UIManager.scheduleIn) == "function" then
        UIManager:scheduleIn(0.5, function()
            self.is_programmatic_navigation = nil
        end)
    else
        self.is_programmatic_navigation = nil
    end
end

return M