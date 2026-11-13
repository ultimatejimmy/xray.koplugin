--[[
    xray_duplicates.lua
    Duplicate candidate building, rejection persistence, review dialogs, and interactive merge flows for KOReader X-Ray Plugin.
--]]

local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local ButtonDialog = require("ui/widget/buttondialog")

local plugin_path = ((...) or ""):match("(.-)[^%.]+$") or ""
local utils = require(plugin_path .. "xray_utils")

local M = {}

function M:buildDuplicateCandidates(list, current_story)
    if not list then return {} end
    local is_anthology = self.isAnthologyMode and self:isAnthologyMode()
    if not is_anthology or not current_story or not current_story.story_id then
        return list
    end

    local cur_sid = current_story.story_id
    local candidates = {}
    local seen_cores = {}

    for _, item in ipairs(list) do
        local sid = item.story_id or (self.resolveEntityStory and self:resolveEntityStory(item))
        local role, in_cur = false, false
        if self.getEntityStoryRole then
            role, in_cur = self:getEntityStoryRole(item, cur_sid)
        else
            in_cur = (sid == cur_sid)
        end

        local eligible = (sid == cur_sid) or (in_cur == true) or (sid == nil)
        if eligible then
            local core, title = self:canonicalNameKey(item.name or "")
            if core == "" then
                table.insert(candidates, item)
            else
                local bucket = seen_cores[core]
                if not bucket then
                    seen_cores[core] = { { item = item, title = title, sid = sid } }
                    table.insert(candidates, item)
                else
                    local found_entry = nil
                    for _, entry in ipairs(bucket) do
                        if entry.title == nil or title == nil or entry.title == title then
                            found_entry = entry
                            break
                        end
                    end
                    if not found_entry then
                        table.insert(bucket, { item = item, title = title, sid = sid })
                        table.insert(candidates, item)
                    else
                        -- If the incoming item belongs to the current story and the stored one doesn't, swap
                        if sid == cur_sid and found_entry.sid ~= cur_sid then
                            for c_idx, c_it in ipairs(candidates) do
                                if c_it == found_entry.item then
                                    candidates[c_idx] = item
                                    found_entry.item = item
                                    found_entry.sid = sid
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return candidates
end

function M:resolveDuplicatePair(candidates, pair, current_story)
    if not candidates or not pair or not pair.primary or not pair.secondary then return nil end
    local cur_sid = current_story and current_story.story_id
    local is_anthology = self.isAnthologyMode and self:isAnthologyMode()

    local function findBestMatch(query)
        if not query or query == "" then return nil end
        local q_lower = query:lower()
        local tier1, tier2, tier3 = {}, {}, {}

        for _, it in ipairs(candidates) do
            local it_name = it.name or ""
            local it_sid = it.story_id or (self.resolveEntityStory and self:resolveEntityStory(it))
            if it_name:lower() == q_lower then
                table.insert(tier1, { item = it, sid = it_sid })
            elseif self.namesMatchCanonical and self:namesMatchCanonical(it_name, query) then
                table.insert(tier2, { item = it, sid = it_sid })
            elseif it.aliases and type(it.aliases) == "table" then
                for _, a in ipairs(it.aliases) do
                    if type(a) == "string" and (a:lower() == q_lower or (self.namesMatchCanonical and self:namesMatchCanonical(a, query))) then
                        table.insert(tier3, { item = it, sid = it_sid })
                        break
                    end
                end
            end
        end

        local function pickFromTier(t)
            if #t == 0 then return nil end
            if cur_sid then
                for _, e in ipairs(t) do
                    if e.sid == cur_sid then return e.item end
                end
            end
            return t[1].item
        end

        return pickFromTier(tier1) or pickFromTier(tier2) or pickFromTier(tier3)
    end

    local p_item = findBestMatch(pair.primary)
    local s_item = findBestMatch(pair.secondary)

    if not p_item or not s_item or p_item == s_item then
        return nil
    end

    local p_sid = p_item.story_id or (self.resolveEntityStory and self:resolveEntityStory(p_item))
    local s_sid = s_item.story_id or (self.resolveEntityStory and self:resolveEntityStory(s_item))
    local cross_story = is_anthology and (p_sid ~= s_sid)

    if cross_story and cur_sid then
        if p_sid ~= cur_sid and s_sid ~= cur_sid then
            return nil
        end
    end

    return p_item, s_item, cross_story
end

function M:makeRejectKey(p_item, s_item)
    if not p_item or not s_item then return "" end
    local is_anthology = self.isAnthologyMode and self:isAnthologyMode()
    local p_name = (p_item.name or ""):lower()
    local s_name = (s_item.name or ""):lower()
    local name_key = p_name < s_name and (p_name .. "|" .. s_name) or (s_name .. "|" .. p_name)

    if not is_anthology then
        return name_key
    end

    local p_sid = tostring(p_item.story_id or (self.resolveEntityStory and select(1, self:resolveEntityStory(p_item))) or "")
    local s_sid = tostring(s_item.story_id or (self.resolveEntityStory and select(1, self:resolveEntityStory(s_item))) or "")
    local sid_key = p_sid < s_sid and (p_sid .. "|" .. s_sid) or (s_sid .. "|" .. p_sid)
    return sid_key .. "::" .. name_key
end

function M:isPairRejected(p_item, s_item)
    if not p_item or not s_item or not self.book_data or not self.book_data.rejected_merge_pairs then
        return false
    end
    local rejs = self.book_data.rejected_merge_pairs
    local scoped_key = self:makeRejectKey(p_item, s_item)
    if rejs[scoped_key] then return true end

    -- Legacy key check
    local p_name = (p_item.name or ""):lower()
    local s_name = (s_item.name or ""):lower()
    local legacy_key = p_name < s_name and (p_name .. "|" .. s_name) or (s_name .. "|" .. p_name)
    return rejs[legacy_key] == true
end

function M:filterValidDuplicatePairs(list, pairs)
    if not pairs or not list then return {} end
    if not self.book_data then
        if not self.cache_manager then
            self.cache_manager = require(plugin_path .. "xray_cachemanager"):new()
        end
        self.book_data = self.cache_manager:loadCache(self.ui.document.file) or {}
    end

    local is_anthology = self.isAnthologyMode and self:isAnthologyMode()
    local current_story = is_anthology and self.getCurrentStory and self:getCurrentStory() or nil
    local candidates = self:buildDuplicateCandidates(list, current_story)

    local filtered = {}
    local seen_resolved = {}

    for _, pair in ipairs(pairs) do
        local p_item, s_item, cross_story = self:resolveDuplicatePair(candidates, pair, current_story)
        if p_item and s_item and not self:isPairRejected(p_item, s_item) then
            local r_key = tostring(p_item) .. "<->" .. tostring(s_item)
            local r_key_rev = tostring(s_item) .. "<->" .. tostring(p_item)
            if not seen_resolved[r_key] and not seen_resolved[r_key_rev] then
                seen_resolved[r_key] = true
                table.insert(filtered, {
                    primary = p_item.name,
                    secondary = s_item.name,
                    reason = pair.reason or "Similar entries",
                    _p = p_item,
                    _s = s_item,
                    cross_story = cross_story,
                })
            end
        end
    end
    return filtered
end

function M:walkDuplicatePairs(list, list_name, pairs_found)
    local InfoMessage = require("ui/widget/infomessage")
    local ButtonDialog = require("ui/widget/buttondialog")

    self:log("XRayPlugin: Walking " .. tostring(pairs_found and #pairs_found or 0) .. " duplicate pair(s) for " .. tostring(list_name))

    if not pairs_found or #pairs_found == 0 then
        UIManager:show(InfoMessage:new{
            text = self.loc:t("no_duplicates_found") or "No duplicates found.",
            timeout = 3
        })
        return
    end

    if not self.book_data then
        if not self.cache_manager then
            self.cache_manager = require(plugin_path .. "xray_cachemanager"):new()
        end
        self.book_data = self.cache_manager:loadCache(self.ui.document.file) or {}
    end

    pairs_found = self:filterValidDuplicatePairs(list, pairs_found)

    self:log("XRayPlugin: " .. tostring(#pairs_found) .. " pair(s) remain after filtering rejected/non-existent for " .. tostring(list_name))

    if #pairs_found == 0 then
        UIManager:show(InfoMessage:new{
            text = self.loc:t("no_duplicates_found") or "No duplicates found.",
            timeout = 3
        })
        return
    end

    -- Walk through pairs one at a time
    local pair_idx = 1
    local merge_count = 0

    local function saveAndRefresh()
        if merge_count == 0 then return end
        local doc_file = self.ui and self.ui.document and self.ui.document.file
        if not self.cache_manager then
            self.cache_manager = require(plugin_path .. "xray_cachemanager"):new()
        end
        if not self.book_data then
            self.book_data = (doc_file and self.cache_manager:loadCache(doc_file)) or {}
        end
        local cache = self.book_data
        if list_name == "characters" then
            cache.characters = list
        elseif list_name == "locations" then
            cache.locations = list
        end
        if doc_file and self.cache_manager then
            self.cache_manager:asyncSaveCache(doc_file, cache)
        end
        -- Clear normalized lookup caches
        for _, it in ipairs(list) do
            it._norm_name = nil
            it._norm_aliases = nil
        end
    end

    local function processNextPair()
        if pair_idx > #pairs_found then
            saveAndRefresh()
            local msg = merge_count > 0
                and self.loc:t("ai_merged_n", merge_count)
                or  (self.loc:t("no_merges_performed") or "No merges performed.")
            UIManager:show(InfoMessage:new{ text = msg, timeout = 3 })
            self:log("XRayPlugin: Duplicate walk complete. " .. tostring(merge_count) .. " merge(s) performed.")
            if list_name == "characters" then self:showCharacters()
            elseif list_name == "locations" then self:showLocations() end
            return
        end

        local pair = pairs_found[pair_idx]
        pair_idx = pair_idx + 1

        -- Validate both entries still exist in list by reference
        local primary_item = pair._p
        local secondary_item = pair._s
        local p_found, s_found = false, false

        for _, it in ipairs(list) do
            if it == primary_item then p_found = true end
            if it == secondary_item then s_found = true end
        end

        -- Fallback to name search if references are missing (e.g. from legacy callers)
        if not p_found or not s_found then
            for _, it in ipairs(list) do
                if it.name and it.name:lower() == (pair.primary or ""):lower() then
                    primary_item = it
                    p_found = true
                end
                if it.name and it.name:lower() == (pair.secondary or ""):lower() then
                    secondary_item = it
                    s_found = true
                end
            end
        end

        if not p_found or not s_found or not primary_item or not secondary_item or primary_item == secondary_item then
            processNextPair()  -- skip silently
            return
        end

        local is_cross = pair.cross_story == true
        local cur_sid = (self.isAnthologyMode and self:isAnthologyMode()) and self.getCurrentStory and (function()
            local cs = self:getCurrentStory()
            return cs and cs.story_id
        end)() or nil

        local confirm_dialog
        if is_cross then
            -- Cross-story Link Confirmation
            local anchor, local_item = primary_item, secondary_item
            local p_sid = primary_item.story_id or (self.resolveEntityStory and select(1, self:resolveEntityStory(primary_item)))
            if p_sid == cur_sid then
                local_item, anchor = primary_item, secondary_item
            end

            local confirm_text = string.format(
                "%s\n\n%s: %s\n%s: %s (%s)\n\n%s: %s",
                self.loc:t("ai_link_confirm_title") or "Same entity in another story?",
                self.loc:t("link_this_story_label") or "THIS STORY",
                local_item.name,
                self.loc:t("link_same_as_label") or "SAME AS",
                anchor.name,
                anchor.story_title or "?",
                self.loc:t("reason") or "Reason",
                pair.reason or "Similar entries"
            )

            confirm_dialog = ButtonDialog:new{
                modal = true,
                title = confirm_text,
                buttons = {{
                    {
                        text = self.loc:t("link_button") or "Link",
                        callback = function()
                            self:log("XRayPlugin: Linking duplicate cross-story: local '" .. tostring(local_item.name) .. "', anchor '" .. tostring(anchor.name) .. "'")
                            UIManager:close(confirm_dialog)
                            local old_local_name = local_item.name
                            local survivor = self:linkEntriesAcrossStories(list, anchor, local_item)
                            if survivor then
                                if self.markStoryPresence then
                                    if anchor.story_id then self:markStoryPresence(anchor.name, anchor.story_id) end
                                    if survivor.story_id then self:markStoryPresence(anchor.name, survivor.story_id) end
                                end
                                if self.migrateStoryPresence and old_local_name ~= survivor.name then
                                    self:migrateStoryPresence(old_local_name, survivor.name)
                                end
                                merge_count = merge_count + 1
                            end
                            processNextPair()
                        end
                    },
                    {
                        text = self.loc:t("skip") or "Skip",
                        callback = function()
                            self:log("XRayPlugin: Skipping pair '" .. tostring(pair.primary) .. "' / '" .. tostring(pair.secondary) .. "'")
                            UIManager:close(confirm_dialog)
                            processNextPair()
                        end
                    },
                    {
                        text = self.loc:t("reject_pair") or "Reject",
                        callback = function()
                            self:log("XRayPlugin: Rejecting cross-story pair '" .. tostring(pair.primary) .. "' / '" .. tostring(pair.secondary) .. "'")
                            UIManager:close(confirm_dialog)
                            local doc_file = self.ui and self.ui.document and self.ui.document.file
                            if not self.book_data then
                                if not self.cache_manager then
                                    self.cache_manager = require(plugin_path .. "xray_cachemanager"):new()
                                end
                                self.book_data = (doc_file and self.cache_manager:loadCache(doc_file)) or {}
                            end
                            self.book_data.rejected_merge_pairs = self.book_data.rejected_merge_pairs or {}
                            local key = self:makeRejectKey(primary_item, secondary_item)
                            self.book_data.rejected_merge_pairs[key] = true
                            
                            if not self.cache_manager then
                                self.cache_manager = require(plugin_path .. "xray_cachemanager"):new()
                            end
                            if doc_file and self.cache_manager then
                                self.cache_manager:asyncSaveCache(doc_file, self.book_data)
                            end
                            
                            UIManager:show(InfoMessage:new{ text = self.loc:t("pair_rejected") or "Pair marked as not a duplicate.", timeout = 2 })
                            processNextPair()
                        end
                    },
                    {
                        text = self.loc:t("stop") or "Stop",
                        callback = function()
                            self:log("XRayPlugin: User stopped duplicate walk after " .. tostring(merge_count) .. " merge(s)")
                            UIManager:close(confirm_dialog)
                            pair_idx = #pairs_found + 1
                            processNextPair()
                        end
                    }
                }}
            }
        else
            -- Same-story Merge Confirmation
            local confirm_text = string.format(
                "%s\n\nKEEP:   %s\nREMOVE: %s\n\n%s: %s",
                self.loc:t("ai_merge_confirm_title") or "AI Duplicate Detected",
                primary_item.name, secondary_item.name,
                self.loc:t("reason") or "Reason",
                pair.reason or "Similar entries"
            )

            confirm_dialog = ButtonDialog:new{
                modal = true,
                title = confirm_text,
                buttons = {{
                    {
                        text = self.loc:t("merge_button") or "Merge",
                        callback = function()
                            self:log("XRayPlugin: Merging duplicate pair: keep '" .. tostring(primary_item.name) .. "', remove '" .. tostring(secondary_item.name) .. "'")
                            UIManager:close(confirm_dialog)
                            local sec_name_before = secondary_item.name
                            local p_desc = primary_item.description or primary_item.biography
                            local s_desc = secondary_item.description or secondary_item.biography
                            if p_desc and s_desc then
                                local wait_msg = InfoMessage:new{ text = self.loc:t("merging_smartly") or "Merging...", timeout = 120 }
                                UIManager:show(wait_msg)
                                UIManager:scheduleIn(0.1, function()
                                    coroutine.wrap(function()
                                        if self.destroyed or not self.ui or not self.ui.document then return end
                                        if self.ai_helper then self.ai_helper:setTrapWidget(wait_msg) end
                                        local ai_desc = self.ai_helper:mergeDescriptionsWithAI(p_desc, s_desc)
                                        if self.ai_helper then self.ai_helper:resetTrapWidget() end
                                        UIManager:close(wait_msg)
                                        local ok, old_p_name = self:mergeEntryItems(list, primary_item, secondary_item, ai_desc)
                                        if ok then
                                            merge_count = merge_count + 1
                                            if self.migrateStoryPresence then
                                                self:migrateStoryPresence(sec_name_before, primary_item.name)
                                                if old_p_name and old_p_name ~= primary_item.name then
                                                    self:migrateStoryPresence(old_p_name, primary_item.name)
                                                end
                                            end
                                        end
                                        processNextPair()
                                    end)()
                                end)
                            else
                                local ok, old_p_name = self:mergeEntryItems(list, primary_item, secondary_item, nil)
                                if ok then
                                    merge_count = merge_count + 1
                                    if self.migrateStoryPresence then
                                        self:migrateStoryPresence(sec_name_before, primary_item.name)
                                        if old_p_name and old_p_name ~= primary_item.name then
                                            self:migrateStoryPresence(old_p_name, primary_item.name)
                                        end
                                    end
                                end
                                processNextPair()
                            end
                        end
                    },
                    {
                        text = self.loc:t("skip") or "Skip",
                        callback = function()
                            self:log("XRayPlugin: Skipping pair '" .. tostring(pair.primary) .. "' / '" .. tostring(pair.secondary) .. "'")
                            UIManager:close(confirm_dialog)
                            processNextPair()
                        end
                    },
                    {
                        text = self.loc:t("reject_pair") or "Reject",
                        callback = function()
                            self:log("XRayPlugin: Rejecting pair '" .. tostring(pair.primary) .. "' / '" .. tostring(pair.secondary) .. "'")
                            UIManager:close(confirm_dialog)
                            local doc_file = self.ui and self.ui.document and self.ui.document.file
                            if not self.book_data then
                                if not self.cache_manager then
                                    self.cache_manager = require(plugin_path .. "xray_cachemanager"):new()
                                end
                                self.book_data = (doc_file and self.cache_manager:loadCache(doc_file)) or {}
                            end
                            self.book_data.rejected_merge_pairs = self.book_data.rejected_merge_pairs or {}
                            local key = self:makeRejectKey(primary_item, secondary_item)
                            self.book_data.rejected_merge_pairs[key] = true
                            
                            -- Save cache to persist rejection
                            if not self.cache_manager then
                                self.cache_manager = require(plugin_path .. "xray_cachemanager"):new()
                            end
                            if doc_file and self.cache_manager then
                                self.cache_manager:asyncSaveCache(doc_file, self.book_data)
                            end
                            
                            UIManager:show(InfoMessage:new{ text = self.loc:t("pair_rejected") or "Pair marked as not a duplicate.", timeout = 2 })
                            processNextPair()
                        end
                    },
                    {
                        text = self.loc:t("stop") or "Stop",
                        callback = function()
                            self:log("XRayPlugin: User stopped duplicate walk after " .. tostring(merge_count) .. " merge(s)")
                            UIManager:close(confirm_dialog)
                            pair_idx = #pairs_found + 1
                            processNextPair()
                        end
                    }
                }}
            }
        end
        UIManager:show(confirm_dialog)
    end

    processNextPair()
end

function M:showAIFindDuplicatesFlow(list, list_name, entity_label)
    local InfoMessage = require("ui/widget/infomessage")
    local ButtonDialog = require("ui/widget/buttondialog")

    self:log("XRayPlugin: AI duplicate scan started for " .. tostring(list_name))

    if not self.ai_helper or not self.ai_helper:hasApiKey() then
        UIManager:show(InfoMessage:new{
            text = self.loc:t("ai_key_required") or "An AI API key is required.",
            timeout = 4
        })
        return
    end

    local props = self.ui.document:getProps() or {}
    local title  = props.title  or (self.book_data and self.book_data.book_title) or "Unknown"
    local author = props.authors or (self.book_data and self.book_data.author)     or "Unknown"
    local current_page = self.ui:getCurrentPage()
    local reading_percent = math.floor((current_page / self.ui.document:getPageCount()) * 100)
    local spoiler_setting = self.ai_helper.settings and self.ai_helper.settings.spoiler_setting or "spoiler_free"
    if spoiler_setting == "full_book" then reading_percent = 100 end

    local is_anthology = self.isAnthologyMode and self:isAnthologyMode()
    local current_story = is_anthology and self:getCurrentStory(current_page) or nil

    if not self.chapter_analyzer then
        self.chapter_analyzer = require(plugin_path .. "xray_chapteranalyzer"):new()
    end
    local dup_book_text = self.chapter_analyzer:getTextForAnalysis(
        self.ui, 15000, nil, current_page, nil, nil, current_story)

    local target_list = list
    if is_anthology then
        target_list = self:buildDuplicateCandidates(list, current_story)
    end

    local wait_msg = InfoMessage:new{
        text = self.loc:t("ai_scanning_duplicates") or "AI is scanning for duplicates...",
        timeout = 120
    }
    UIManager:show(wait_msg)

    UIManager:scheduleIn(0.1, function()
        if self.destroyed or not self.ui or not self.ui.document then return end
        local scope_story_id = current_story and current_story.story_id or nil
        local pairs_found, err_code, err_msg = self.ai_helper:findDuplicates(
            title, author, target_list, entity_label, reading_percent, dup_book_text, scope_story_id
        )
        UIManager:close(wait_msg)

        if not pairs_found then
            self:log("XRayPlugin: AI duplicate scan failed for " .. tostring(list_name) .. ": " .. tostring(err_msg))
            UIManager:show(InfoMessage:new{
                text = (self.loc:t("ai_error") or "AI Error: ") .. tostring(err_msg),
                timeout = 4
            })
            return
        end

        self:log("XRayPlugin: AI duplicate scan found " .. tostring(#pairs_found) .. " pair(s) for " .. tostring(list_name))
        self:walkDuplicatePairs(list, list_name, pairs_found)
    end)
end

function M:showMergeFlow(list, list_name)
    local ButtonDialog = require("ui/widget/buttondialog")
    local InfoMessage = require("ui/widget/infomessage")
    
    local primary_dialog, secondary_dialog
    local showPrimaryPicker, pickSecondary
    local is_anthology = self.isAnthologyMode and self:isAnthologyMode()
    local cur_story = is_anthology and self.getCurrentStory and self:getCurrentStory() or nil
    local cur_sid = cur_story and cur_story.story_id
    
    pickSecondary = function(primary_item)
        local buttons = {}
        local p_st = is_anthology and (primary_item.story_id or (self.resolveEntityStory and select(1, self:resolveEntityStory(primary_item)))) or nil
        for _, item in ipairs(list) do
            if item ~= primary_item then
                local i_st = is_anthology and (item.story_id or (self.resolveEntityStory and select(1, self:resolveEntityStory(item)))) or nil
                local allowed = true
                if is_anthology then
                    -- Allowed if same story, or if one of the two belongs to the current story
                    allowed = (p_st == i_st) or (cur_sid and (p_st == cur_sid or i_st == cur_sid))
                end

                if allowed then
                    local secondary_item = item
                    local secondary_name = item.name
                    local display_label = secondary_name
                    local is_cross = is_anthology and (p_st ~= i_st)
                    if is_cross and item.story_title then
                        display_label = string.format("%s (%s)", secondary_name, item.story_title)
                    end

                    table.insert(buttons, {{
                        text = display_label,
                        align = "left",
                        callback = function()
                            if secondary_dialog then
                                UIManager:close(secondary_dialog)
                                secondary_dialog = nil
                            end

                            if is_cross then
                                -- Cross-story Link Confirmation
                                local anchor, local_item = primary_item, secondary_item
                                if p_st == cur_sid then
                                    local_item, anchor = primary_item, secondary_item
                                end

                                local confirm
                                confirm = ButtonDialog:new{
                                    modal = true,
                                    title = string.format(
                                        "%s\n\n%s: %s\n%s: %s (%s)",
                                        self.loc:t("ai_link_confirm_title") or "Same entity in another story?",
                                        self.loc:t("link_this_story_label") or "THIS STORY",
                                        local_item.name,
                                        self.loc:t("link_same_as_label") or "SAME AS",
                                        anchor.name,
                                        anchor.story_title or "?"
                                    ),
                                    buttons = {{
                                        {
                                            text = self.loc:t("close") or "Close",
                                            callback = function() UIManager:close(confirm) end,
                                        },
                                        {
                                            text = self.loc:t("link_button") or "Link",
                                            is_enter_default = true,
                                            callback = function()
                                                UIManager:close(confirm)
                                                local old_local_name = local_item.name
                                                local survivor = self:linkEntriesAcrossStories(list, anchor, local_item)
                                                if survivor then
                                                    if self.markStoryPresence then
                                                        if anchor.story_id then self:markStoryPresence(anchor.name, anchor.story_id) end
                                                        if survivor.story_id then self:markStoryPresence(anchor.name, survivor.story_id) end
                                                    end
                                                    if self.migrateStoryPresence and old_local_name ~= survivor.name then
                                                        self:migrateStoryPresence(old_local_name, survivor.name)
                                                    end

                                                    local doc_file = self.ui and self.ui.document and self.ui.document.file
                                                    if not self.cache_manager then
                                                        self.cache_manager = require(plugin_path .. "xray_cachemanager"):new()
                                                    end
                                                    if not self.book_data then
                                                        self.book_data = (doc_file and self.cache_manager:loadCache(doc_file)) or {}
                                                    end
                                                    local cache = self.book_data
                                                    if list_name == "characters" then
                                                        cache.characters = list
                                                    elseif list_name == "locations" then
                                                        cache.locations = list
                                                    end
                                                    if doc_file and self.cache_manager then
                                                        self.cache_manager:asyncSaveCache(doc_file, cache)
                                                    end

                                                    for _, it in ipairs(list) do
                                                        it._norm_name = nil
                                                        it._norm_aliases = nil
                                                    end

                                                    UIManager:show(InfoMessage:new{
                                                        text = self.loc:t("merge_success") or "Entries merged successfully.",
                                                        timeout = 3
                                                    })

                                                    if list_name == "characters" then
                                                        self:showCharacters()
                                                    elseif list_name == "locations" then
                                                        self:showLocations()
                                                    end
                                                end
                                            end
                                        }
                                    }}
                                }
                                UIManager:show(confirm)
                            else
                                -- Same-story Merge Confirmation
                                local confirm
                                confirm = ButtonDialog:new{
                                    modal = true,
                                    title = string.format(
                                        self.loc:t("merge_confirm") or "Merge %s into %s? The secondary entry will be deleted and its aliases absorbed.",
                                        secondary_name, primary_item.name
                                    ),
                                    buttons = {{
                                        {
                                            text = self.loc:t("close") or "Close",
                                            callback = function()
                                                UIManager:close(confirm)
                                            end,
                                        },
                                        {
                                            text = self.loc:t("yes") or "Yes",
                                            is_enter_default = true,
                                            callback = function()
                                                UIManager:close(confirm)
                                                local wait_msg = InfoMessage:new{ text = self.loc:t("merging_smartly") or "Merging...", timeout = 120 }
                                                UIManager:show(wait_msg)
                                                
                                                UIManager:scheduleIn(0.1, function()
                                                    if self.destroyed or not self.ui or not self.ui.document then return end
                                                    local ai_merged_desc = nil
                                                    if self.ai_helper and self.ai_helper:hasApiKey() then
                                                        if primary_item.description and secondary_item.description then
                                                            if self.ai_helper then self.ai_helper:setTrapWidget(wait_msg) end
                                                            ai_merged_desc = self.ai_helper:mergeDescriptionsWithAI(primary_item.description, secondary_item.description)
                                                            if self.ai_helper then self.ai_helper:resetTrapWidget() end
                                                        end
                                                    end
                                                    
                                                    UIManager:close(wait_msg)
                                                    
                                                    local sec_name_before = secondary_item.name
                                                    local ok, old_p_name = self:mergeEntryItems(list, primary_item, secondary_item, ai_merged_desc)
                                                    if ok then
                                                        if self.migrateStoryPresence then
                                                            self:migrateStoryPresence(sec_name_before, primary_item.name)
                                                            if old_p_name and old_p_name ~= primary_item.name then
                                                                self:migrateStoryPresence(old_p_name, primary_item.name)
                                                            end
                                                        end

                                                        local doc_file = self.ui and self.ui.document and self.ui.document.file
                                                        if not self.cache_manager then
                                                            self.cache_manager = require(plugin_path .. "xray_cachemanager"):new()
                                                        end
                                                        if not self.book_data then
                                                            self.book_data = (doc_file and self.cache_manager:loadCache(doc_file)) or {}
                                                        end
                                                        local cache = self.book_data
                                                        if list_name == "characters" then
                                                            cache.characters = list
                                                        elseif list_name == "locations" then
                                                            cache.locations = list
                                                        end
                                                        if doc_file and self.cache_manager then
                                                            self.cache_manager:asyncSaveCache(doc_file, cache)
                                                        end
                                                        
                                                        for _, it in ipairs(list) do
                                                            it._norm_name = nil
                                                            it._norm_aliases = nil
                                                        end
                                                        
                                                        UIManager:show(InfoMessage:new{
                                                            text = self.loc:t("merge_success") or "Entries merged successfully.",
                                                            timeout = 3
                                                        })
                                                        
                                                        if list_name == "characters" then
                                                            self:showCharacters()
                                                        elseif list_name == "locations" then
                                                            self:showLocations()
                                                        end
                                                    else
                                                        UIManager:show(InfoMessage:new{
                                                            text = self.loc:t("merge_failed") or "Merge failed.",
                                                            timeout = 3
                                                        })
                                                    end
                                                end)
                                            end,
                                        },
                                    }},
                                }
                                UIManager:show(confirm)
                            end
                        end
                    }})
                end
            end
        end
        
        table.insert(buttons, {{
            text = self.loc:t("merge_back") or "← Back",
            callback = function()
                if secondary_dialog then
                    UIManager:close(secondary_dialog)
                    secondary_dialog = nil
                end
                showPrimaryPicker()
            end
        }})
        
        secondary_dialog = ButtonDialog:new{
            modal = true,
            title = self.loc:t("merge_pick_secondary") or "Choose the entry to REMOVE",
            buttons = buttons
        }
        UIManager:show(secondary_dialog)
    end
    
    showPrimaryPicker = function()
        local buttons = {}
        local candidates = list
        if is_anthology and not self.anthology_show_all_stories and cur_story then
            candidates = self:buildDuplicateCandidates(list, cur_story)
        end
        for _, item in ipairs(candidates) do
            local primary_item = item
            local display_text = item.name
            if is_anthology and self.anthology_show_all_stories and item.story_title then
                display_text = string.format("%s (%s)", item.name, item.story_title)
            end
            table.insert(buttons, {{
                text = display_text,
                align = "left",
                callback = function()
                    if primary_dialog then
                        UIManager:close(primary_dialog)
                        primary_dialog = nil
                    end
                    pickSecondary(primary_item)
                end
            }})
        end
        
        table.insert(buttons, {{
            text = self.loc:t("close") or "Close",
            callback = function()
                if primary_dialog then
                    UIManager:close(primary_dialog)
                    primary_dialog = nil
                end
            end
        }})
        
        primary_dialog = ButtonDialog:new{
            modal = true,
            title = self.loc:t("merge_pick_primary") or "Choose the entry to KEEP",
            buttons = buttons
        }
        UIManager:show(primary_dialog)
    end

    showPrimaryPicker()
end



return M
