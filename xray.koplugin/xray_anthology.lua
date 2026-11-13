-- xray_anthology.lua - Anthology mode, story boundaries, recurring characters, and presence tracking
local UIManager = require("ui/uimanager")
local plugin_path = ((...) or ""):match("(.-)[^%.]+$") or ""

local M = {}

function M:detectAnthologyFromMetadata(props, title)
    props = props or (self.ui and self.ui.document and self.ui.document.getProps and self.ui.document:getProps()) or {}
    local fields = {}
    if title then table.insert(fields, tostring(title)) end
    if props.title then table.insert(fields, tostring(props.title)) end
    if props.keywords then table.insert(fields, tostring(props.keywords)) end
    if props.subject then table.insert(fields, tostring(props.subject)) end
    if props.genre then table.insert(fields, tostring(props.genre)) end
    if props.series then table.insert(fields, tostring(props.series)) end
    if props.tag then table.insert(fields, tostring(props.tag)) end
    if props.tags then table.insert(fields, tostring(props.tags)) end
    local combined = table.concat(fields, " "):lower()
    if combined == "" then return false end

    local patterns = {
        "antholog",
        "short stor",
        "collected stor",
        "complete stor",
        "selected stor",
        "collection of stor",
        "stories and tales",
        "short fiction",
        "collected works",
        "complete works",
        "stories,",
        "%f[%a]stories%f[%A]",
    }
    for _, pat in ipairs(patterns) do
        if combined:find(pat) then
            return true
        end
    end
    return false
end

function M:isAnthologyMode()
    local override = self.book_data and (self.book_data.book_mode_override or self.book_data.book_type)
    if override == "anthology" then
        return true
    elseif override == "fiction" or override == "non_fiction" then
        return false
    end
    if self.book_type == "anthology" then
        return true
    end
    if self.book_data and self.book_data.anthology_detected ~= nil then
        return self.book_data.anthology_detected == true
    end
    if override == "auto" or not override then
        if self:detectAnthologyFromMetadata() then
            return true
        end
    end
    return false
end

function M:markStoryPresence(name, story_id)
    if not name or not story_id then return false end
    if not self.book_data then self.book_data = {} end
    self.book_data.story_presence = self.book_data.story_presence or {}
    self.book_data.story_presence[name] = self.book_data.story_presence[name] or {}
    if not self.book_data.story_presence[name][story_id] then
        self.book_data.story_presence[name][story_id] = true
        self._presence_index = nil
        return true
    end
    return false
end

function M:getStoryPresence(name)
    if not name or not self.book_data or not self.book_data.story_presence then return nil end
    local sp = self.book_data.story_presence
    if not self._presence_index or self._presence_index_src ~= sp then
        local index = {}
        for raw_name, st_map in pairs(sp) do
            local core, title = self:canonicalNameKey(raw_name)
            if core ~= "" then
                index[core] = index[core] or {}
                table.insert(index[core], { title = title, map = st_map })
            end
        end
        self._presence_index = index
        self._presence_index_src = sp
    end

    local q_core, q_title = self:canonicalNameKey(name)
    local buckets = self._presence_index[q_core]
    if not buckets then return nil end

    local merged = {}
    local count = 0
    for _, entry in ipairs(buckets) do
        if entry.title == nil or q_title == nil or entry.title == q_title then
            for sid, v in pairs(entry.map) do
                if v and not merged[sid] then
                    merged[sid] = true
                    count = count + 1
                end
            end
        end
    end
    return count > 0 and merged or nil
end

function M:migrateStoryPresence(old_name, new_name)
    if not old_name or not new_name or old_name == new_name then return end
    if not self.book_data or not self.book_data.story_presence then return end
    local old_map = self.book_data.story_presence[old_name]
    if old_map then
        for sid, v in pairs(old_map) do
            if v then self:markStoryPresence(new_name, sid) end
        end
        self.book_data.story_presence[old_name] = nil
        self._presence_index = nil
    end
end

function M:isEntityRecurring(entity)
    if not entity then return false end
    if entity.is_recurring then return true end
    local name = entity.name
    if not name and entity.item then name = entity.item.name end
    if not name or name == "" then return false end

    local pres = name and (self.getStoryPresence and self:getStoryPresence(name) or (self.book_data and self.book_data.story_presence and self.book_data.story_presence[name]))
    if pres then
        local count = 0
        for _ in pairs(pres) do
            count = count + 1
            if count >= 2 then return true end
        end
    end

    -- Cross-check entity collections for multi-story appearances if presence not yet indexed
    local stories_seen = {}
    for _, list in ipairs({ self.characters or {}, self.locations or {}, self.terms or {}, self.historical_figures or {} }) do
        for _, it in ipairs(list) do
            local iname = it.name or (it.item and it.item.name)
            local matches = false
            if iname then
                if self.namesMatchCanonical then
                    matches = self:namesMatchCanonical(iname, name)
                else
                    matches = (iname:lower():gsub("^%s+", ""):gsub("%s+$", "") == name:lower():gsub("^%s+", ""):gsub("%s+$", ""))
                end
            end
            if matches then
                local sid = it.story_id or (it.item and it.item.story_id)
                if sid then stories_seen[sid] = true end
            end
        end
    end
    local st_count = 0
    for _ in pairs(stories_seen) do
        st_count = st_count + 1
        if st_count >= 2 then
            for sid in pairs(stories_seen) do
                if self.markStoryPresence then
                    self:markStoryPresence(name, sid)
                else
                    self.book_data = self.book_data or {}
                    self.book_data.story_presence = self.book_data.story_presence or {}
                    self.book_data.story_presence[name] = self.book_data.story_presence[name] or {}
                    self.book_data.story_presence[name][sid] = true
                end
            end
            return true
        end
    end

    return false
end

function M:getEntityStoryRole(entity, current_story_id)
    if not entity then return "other", false end
    local is_rec = self:isEntityRecurring(entity)
    local name = entity.name
    if not name and entity.item then name = entity.item.name end
    local st_id = entity.story_id or (self.resolveEntityStory and self:resolveEntityStory(entity))

    local in_cur = false
    if current_story_id and st_id and tostring(st_id) == tostring(current_story_id) then
        in_cur = true
    end
    local pres = name and (self.getStoryPresence and self:getStoryPresence(name) or (self.book_data and self.book_data.story_presence and self.book_data.story_presence[name]))
    if not in_cur and pres and current_story_id and (pres[current_story_id] or pres[tostring(current_story_id)]) then
        in_cur = true
    end

    if is_rec then
        return "recurring", in_cur
    end
    if in_cur then
        return "current", true
    end
    return "other", false
end

function M:isStoryAfterCurrent(entity, current_story)
    if not entity then return false end
    if not self.chapter_analyzer then
        local ChapterAnalyzer = require(plugin_path .. "xray_chapteranalyzer")
        self.chapter_analyzer = ChapterAnalyzer:new{ plugin = self }
    end
    local custom_depth = self.book_data and self.book_data.story_toc_depth
    local sm = self.chapter_analyzer:getStoryMap(self.ui, custom_depth)
    local stories = (sm and sm.stories) or {}
    if #stories == 0 then return false end

    current_story = current_story or (self.getCurrentStory and self:getCurrentStory()) or stories[1]
    if not current_story or not current_story.story_id then return false end

    local st_id = entity.story_id or (self.resolveEntityStory and self:resolveEntityStory(entity))
    if not st_id or tostring(st_id) == tostring(current_story.story_id) then return false end

    local cur_idx, ent_idx = nil, nil
    for idx, s in ipairs(stories) do
        if tostring(s.story_id) == tostring(current_story.story_id) then cur_idx = idx end
        if tostring(s.story_id) == tostring(st_id) then ent_idx = idx end
    end
    if cur_idx and ent_idx then
        return ent_idx > cur_idx
    end
    return false
end

function M:ensureStoryPresenceScanned(on_done)
    if not self:isAnthologyMode() then
        if on_done then on_done() end
        return
    end

    self.book_data = self.book_data or {}
    self.book_data.story_presence = self.book_data.story_presence or {}

    -- 1. Immediate seed from existing cached entities with story_ids
    local dirty = false
    local all_lists = { self.characters or {}, self.locations or {}, self.terms or {}, self.historical_figures or {} }
    for _, list in ipairs(all_lists) do
        for _, item in ipairs(list) do
            local nm = item.name or (item.item and item.item.name)
            local sid = item.story_id or (item.item and item.item.story_id)
            if nm and sid then
                if self.markStoryPresence then
                    if self:markStoryPresence(nm, sid) then
                        dirty = true
                    end
                else
                    if not self.book_data.story_presence[nm] then
                        self.book_data.story_presence[nm] = {}
                        dirty = true
                    end
                    if not self.book_data.story_presence[nm][sid] then
                        self.book_data.story_presence[nm][sid] = true
                        dirty = true
                    end
                end
            end
        end
    end

    if not self.chapter_analyzer then
        local ChapterAnalyzer = require(plugin_path .. "xray_chapteranalyzer")
        self.chapter_analyzer = ChapterAnalyzer:new{ plugin = self }
    end

    -- 2. Immediate sync scan for current story
    if self.ui and self.ui.document and self.characters and #self.characters > 0 then
        local cur_story = self:getCurrentStory()
        if cur_story then
            local found = self.chapter_analyzer:scanStoryPresence(self.ui, cur_story, self.characters)
            if found and #found > 0 then
                for _, nm in ipairs(found) do
                    if self:markStoryPresence(nm, cur_story.story_id) then
                        dirty = true
                    end
                end
            end
        end
    end

    if dirty and self.persistBookData then
        self:persistBookData()
    end

    -- 3. Background async scan for remaining stories if not already completed
    if self.ui and self.ui.document and not self._story_presence_scanning and not (self.book_data.story_presence_scanned_at) then
        self._story_presence_scanning = true
        local custom_depth = self.book_data and self.book_data.story_toc_depth
        local sm = self.chapter_analyzer:getStoryMap(self.ui, custom_depth)
        local stories = (sm and sm.stories) or {}
        local entities = self.characters or {}
        if #stories > 0 and #entities > 0 then
            self.chapter_analyzer:scanStoryPresenceAsync(self.ui, stories, entities, nil, function(scanned_presence)
                self._story_presence_scanning = false
                self.book_data.story_presence_scanned_at = os.time()
                for nm, st_map in pairs(scanned_presence or {}) do
                    for sid, pres in pairs(st_map) do
                        if pres then self:markStoryPresence(nm, sid) end
                    end
                end
                if self.persistBookData then
                    self:persistBookData()
                end
                if on_done then on_done() end
            end)
            return
        end
        self._story_presence_scanning = false
    end

    if on_done then on_done() end
end

function M:getCurrentStory(page)
    if not self.chapter_analyzer then
        local ChapterAnalyzer = require(plugin_path .. "xray_chapteranalyzer")
        self.chapter_analyzer = ChapterAnalyzer:new{ plugin = self }
    end
    local custom_depth = self.book_data and self.book_data.story_toc_depth
    page = page or (self.getCurrentDocPage and self:getCurrentDocPage()) or (self.ui and self.ui.getCurrentPage and self.ui:getCurrentPage()) or 1
    return self.chapter_analyzer:getStoryForPage(self.ui, page, custom_depth)
end

function M:resolveEntityStory(entity)
    if not entity then return nil end
    if not self.chapter_analyzer then
        local ChapterAnalyzer = require(plugin_path .. "xray_chapteranalyzer")
        self.chapter_analyzer = ChapterAnalyzer:new{ plugin = self }
    end
    local custom_depth = self.book_data and self.book_data.story_toc_depth
    local sm = self.chapter_analyzer:getStoryMap(self.ui, custom_depth)

    local ch_name = entity.chapter or (entity.visible_from and entity.visible_from.chapter_title)
    local p = entity.page or (entity.visible_from and entity.visible_from.page_hint)
    if not p and entity.mentions and #entity.mentions > 0 then
        p = entity.mentions[1].page
    end

    -- Check if existing story_id is present and consistent
    if entity.story_id and sm and sm.by_id then
        local s = sm.by_id[entity.story_id]
        if s then
            local is_mismatched = false
            -- 1. Check title conflict: if ch_name matches a different story, re-bind
            if ch_name and self.normalizeChapterName and s.story_title then
                local n_ch = self:normalizeChapterName(ch_name)
                local n_st = self:normalizeChapterName(s.story_title)
                if n_ch ~= "" and n_st ~= "" and n_ch ~= n_st then
                    for _, other_s in ipairs(sm.stories or {}) do
                        local n_other = self:normalizeChapterName(other_s.story_title)
                        if n_ch == n_other then
                            is_mismatched = true
                            s = other_s
                            entity.story_id = other_s.story_id
                            entity.story_title = other_s.story_title
                            break
                        end
                    end
                end
            end
            -- 2. Check page conflict: if p is outside story bounds and getStoryForPage finds another story
            if not is_mismatched and p and tonumber(p) and s.start_page and s.end_page then
                local num_p = tonumber(p)
                if num_p < s.start_page or num_p > s.end_page then
                    local page_s = self.chapter_analyzer:getStoryForPage(self.ui, num_p, custom_depth)
                    if page_s and page_s.story_id ~= entity.story_id then
                        s = page_s
                        entity.story_id = page_s.story_id
                        entity.story_title = page_s.story_title
                    end
                end
            end
            if not entity.story_title then
                entity.story_title = s.story_title
            end
            return entity.story_id, entity.story_title
        end
    end

    -- If no valid story_id yet, resolve using: 1. Title match, 2. Page, 3. TOC index
    local story = nil
    if ch_name and self.normalizeChapterName and sm and sm.stories then
        local n_ch = self:normalizeChapterName(ch_name)
        if n_ch ~= "" then
            for _, s in ipairs(sm.stories) do
                local n_st = self:normalizeChapterName(s.story_title)
                if n_ch == n_st then
                    story = s
                    break
                end
            end
        end
    end

    if not story and p and tonumber(p) then
        story = self.chapter_analyzer:getStoryForPage(self.ui, tonumber(p), custom_depth)
    end

    if not story then
        local ch_idx = entity.visible_from and entity.visible_from.chapter_index or entity.chapter_index
        if not ch_idx and entity.mentions and #entity.mentions > 0 then
            ch_idx = entity.mentions[1].chapter_index
        end
        if ch_idx and tonumber(ch_idx) then
            story = self.chapter_analyzer:getStoryForTocIndex(self.ui, tonumber(ch_idx), custom_depth)
        end
    end

    if story then
        entity.story_id = story.story_id
        entity.story_title = story.story_title
        return story.story_id, story.story_title
    end
    return entity.story_id, entity.story_title
end

function M:isEntityInCurrentStory(entity, current_story)
    if not entity then return false end
    current_story = current_story or self:getCurrentStory()
    if not current_story or not current_story.story_id then return true end

    local role, in_cur = self:getEntityStoryRole(entity, current_story.story_id)
    if in_cur or role == "current" then
        return true
    end

    local s_id = entity.story_id or (self.resolveEntityStory and self:resolveEntityStory(entity))
    if not s_id then
        return true -- unassigned entity remains visible
    end
    return tostring(s_id) == tostring(current_story.story_id)
end

function M:collectAnthologySignals()
    local props = (self.ui and self.ui.document and self.ui.document.getProps and self.ui.document:getProps()) or {}
    local title = props.title or ""
    local meta_match = self:detectAnthologyFromMetadata(props, title)

    if not self.chapter_analyzer then
        local ChapterAnalyzer = require(plugin_path .. "xray_chapteranalyzer")
        self.chapter_analyzer = ChapterAnalyzer:new{ plugin = self }
    end
    local custom_depth = self.book_data and self.book_data.story_toc_depth
    local story_map = self.chapter_analyzer:getStoryMap(self.ui, custom_depth)
    local stories = (story_map and story_map.stories) or {}

    local generic_patterns = {
        "^chapter[%s%p%d]",
        "^chapter$",
        "^ch[%s%p%d]",
        "^part[%s%p%d]",
        "^part$",
        "^book[%s%p%d]",
        "^book$",
        "^section[%s%p%d]",
        "^act[%s%p%d]",
        "^volume[%s%p%d]",
        "^vol[%s%p%d]",
        "^canto[%s%p%d]",
        "^scene[%s%p%d]",
    }
    local roman_only = "^[ivxlcdm]+$"
    local named_count = 0
    local total_count = #stories
    local sample_titles = {}

    for i, s in ipairs(stories) do
        local t = (s.story_title or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        local is_generic = false
        for _, pat in ipairs(generic_patterns) do
            if t:match(pat) then
                is_generic = true
                break
            end
        end
        if not is_generic and (t:match(roman_only) or t:match("^%d+$")) then
            is_generic = true
        end

        if not is_generic and t ~= "" then
            named_count = named_count + 1
        end
        if i <= 15 then
            table.insert(sample_titles, s.story_title)
        end
    end

    local named_ratio = total_count > 0 and (named_count / total_count) or 0

    return {
        meta_match = meta_match,
        story_count = total_count,
        named_ratio = named_ratio,
        sample_titles = sample_titles,
        subjects = props.subject or props.keywords or "",
        description = props.description or "",
        title = title,
        authors = props.authors or "",
    }
end

function M:persistBookData()
    if self.saveCurrentBookCache then
        return self:saveCurrentBookCache(self.book_data)
    end
    local doc_file = self.ui and self.ui.document and self.ui.document.file
    if doc_file and self.book_data and self.cache_manager then
        self.cache_manager:asyncSaveCache(doc_file, self.book_data)
    end
end

function M:retagEntitiesByStory()
    if not self:isAnthologyMode() then return end
    if not self.ui or not self.ui.document then return end

    if not self.chapter_analyzer then
        local ChapterAnalyzer = require(plugin_path .. "xray_chapteranalyzer")
        self.chapter_analyzer = ChapterAnalyzer:new{ plugin = self }
    end
    local custom_depth = self.book_data and self.book_data.story_toc_depth
    local story_map = self.chapter_analyzer:getStoryMap(self.ui, custom_depth)
    if not story_map or not story_map.stories or #story_map.stories == 0 then return end

    local all_lists = {
        self.characters or {},
        self.locations or {},
        self.terms or {},
        self.historical_figures or {},
        self.timeline or {}
    }

    local dirty = false
    for _, list in ipairs(all_lists) do
        for _, item in ipairs(list) do
            local old_sid = item.story_id
            local old_title = item.story_title

            local sid, stitle = self:resolveEntityStory(item)
            if sid and (sid ~= old_sid or stitle ~= old_title) then
                item.story_id = sid
                item.story_title = stitle
                dirty = true
            end

            -- For timeline events, also sync chapter_index to the story's start_toc_idx if outside story bounds
            if item.chapter and sid then
                local s = story_map.by_id and story_map.by_id[sid]
                if s and s.start_toc_idx then
                    local out_of_range = not item.chapter_index
                        or item.chapter_index < s.start_toc_idx
                        or (s.end_toc_idx and item.chapter_index > s.end_toc_idx)
                    if out_of_range then
                        item.chapter_index = s.start_toc_idx
                        dirty = true
                    end
                end
            end
        end
    end

    if dirty then
        self:persistBookData()
    end
    if self.ensureStoryPresenceScanned then
        self:ensureStoryPresenceScanned()
    end
end

function M:ensureAnthologyDecision(callback)
    local cb = function(res)
        if callback then callback(res) end
    end

    if not self.book_data then
        cb(self:isAnthologyMode())
        return
    end

    local mode_override = self.book_data.book_mode_override
    if mode_override and mode_override ~= "auto" then
        self.book_type = mode_override
        cb(mode_override == "anthology")
        return
    end

    if self.book_data.anthology_detected ~= nil then
        local is_anth = (self.book_data.book_type == "anthology") or (self.book_data.anthology_detected == true)
        self.book_type = is_anth and "anthology" or (self.book_data.book_type or "fiction")
        cb(is_anth)
        return
    end

    local signals = self:collectAnthologySignals()

    -- Confident anthology: meta_match + multiple distinct named stories
    if signals.meta_match and signals.story_count >= 3 and signals.named_ratio >= 0.7 then
        self.book_data.anthology_detected = true
        self.book_data.anthology_type = "anthology"
        self.book_data.book_type = "anthology"
        self.book_type = "anthology"
        self:persistBookData()
        self:retagEntitiesByStory()
        cb(true)
        return
    end

    -- Confident non-anthology: few chapters or generic numbered chapters with no meta match
    if signals.story_count < 3 or (signals.named_ratio < 0.3 and not signals.meta_match) then
        self.book_data.anthology_detected = false
        self.book_data.anthology_type = "novel"
        self:persistBookData()
        cb(false)
        return
    end

    -- Ambiguous: AI check if API key configured
    if self.ai_helper and self.ai_helper:hasApiKey() and not self._anthology_detecting then
        self._anthology_detecting = true
        local DataStorage = require("datastorage")
        local result_file = DataStorage:getFullDataDir() .. "/xray_anthology_" .. tostring(os.time()) .. ".json"
        local toc_text = table.concat(signals.sample_titles, "\n")
        local pid = self.ai_helper:detectAnthologyAsync(signals.title, signals.authors, signals.subjects, signals.description, toc_text, result_file)
        if pid then
            local function poll()
                if self.destroyed or not self.ui or not self.ui.document then
                    self._anthology_detecting = nil
                    cb(false)
                    return
                end
                local res = self.ai_helper:checkAsyncResult(result_file, pid)
                if res == nil then
                    UIManager:scheduleIn(1, poll)
                else
                    self._anthology_detecting = nil
                    local res_type = type(res) == "table" and res.type
                    if res_type == "anthology" then
                        self.book_data.anthology_detected = true
                        self.book_data.anthology_type = "anthology"
                        self.book_data.book_type = "anthology"
                        self.book_type = "anthology"
                        self:persistBookData()
                        self:retagEntitiesByStory()
                        cb(true)
                    elseif res_type == "novel_omnibus" then
                        self.book_data.anthology_type = "novel_omnibus"
                        local ConfirmBox = require("ui/widget/confirmbox")
                        UIManager:show(ConfirmBox:new{
                            text = (self.loc and self.loc:t("confirm_anthology_omnibus")) or "This book appears to be a multi-novel omnibus. Would you like to enable Anthology Mode (separating characters and locations by novel)?",
                            icon = false,
                            ok_text = (self.loc and self.loc:t("yes")) or "Yes",
                            cancel_text = (self.loc and self.loc:t("no")) or "No",
                            ok_callback = function()
                                self.book_data.book_mode_override = "anthology"
                                self.book_data.anthology_detected = true
                                self.book_data.book_type = "anthology"
                                self.book_type = "anthology"
                                self:persistBookData()
                                self:retagEntitiesByStory()
                                cb(true)
                            end,
                            cancel_callback = function()
                                self.book_data.book_mode_override = "fiction"
                                self.book_data.anthology_detected = false
                                self:persistBookData()
                                cb(false)
                            end,
                        })
                    else
                        self.book_data.anthology_detected = false
                        self.book_data.anthology_type = res_type or "novel"
                        self:persistBookData()
                        cb(false)
                    end
                end
            end
            UIManager:scheduleIn(1, poll)
            return
        end
    end

    -- Default fallback if AI not available
    local fallback_anthology = signals.meta_match and signals.story_count >= 3
    self.book_data.anthology_detected = fallback_anthology
    if fallback_anthology then
        self.book_data.book_type = "anthology"
        self.book_type = "anthology"
        self:retagEntitiesByStory()
    end
    self:persistBookData()
    cb(fallback_anthology)
end

return M
