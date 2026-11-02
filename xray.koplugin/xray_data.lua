-- X-Ray Data Processing Functions

local M = {}

local word_to_num = {
    one=1,two=2,three=3,four=4,five=5,six=6,seven=7,eight=8,nine=9,ten=10,
    eleven=11,twelve=12,thirteen=13,fourteen=14,fifteen=15,sixteen=16,
    seventeen=17,eighteen=18,nineteen=19,twenty=20,
    ["twenty-one"]=21,["twenty-two"]=22,["twenty-three"]=23,["twenty-four"]=24,["twenty-five"]=25,
    ["twenty-six"]=26,["twenty-seven"]=27,["twenty-eight"]=28,["twenty-nine"]=29,thirty=30,
    ["thirty-one"]=31,["thirty-two"]=32,["thirty-three"]=33,["thirty-four"]=34,["thirty-five"]=35,
    ["thirty-six"]=36,["thirty-seven"]=37,["thirty-eight"]=38,["thirty-nine"]=39,forty=40,
    ["forty-one"]=41,["forty-two"]=42,["forty-three"]=43,["forty-four"]=44,["forty-five"]=45,
    ["forty-six"]=46,["forty-seven"]=47,["forty-eight"]=48,["forty-nine"]=49,fifty=50,
}

local roman_map = { i = 1, v = 5, x = 10, l = 50, c = 100, d = 500, m = 1000 }

local function romanToDecimal(s)
    local res = 0
    local prev = 0
    for i = #s, 1, -1 do
        local curr = roman_map[s:sub(i, i)]
        if not curr then return nil end
        if curr < prev then
            res = res - curr
        else
            res = res + curr
        end
        prev = curr
    end
    return res
end

function M:sortDataByFrequency(list, text, key)
    if not list or #list == 0 then return list end

    local function getRoleScore(role)
        if not role or type(role) ~= "string" then return 0 end
        local r = role:lower()

        if r:find("protagonist") or r:find("main character") or r:find("lead character") or r:find("hero") then
            return 100
        end
        if r:find("private investigator") or r:find("lead investigator") or r:find("chief investigator") then
            return 100
        end
        if r:find("deuteragonist") or r:find("co%-lead") or r:find("second lead") then
            return 95
        end
        if r:find("detective") then
            return 90
        end
        if r:find("investigat") then
            if r:find("military") or r:find("insurance") or r:find("forensic") then
                return 45
            end
            return 90
        end

        if r:find("partner") then
            local is_personal = r:find("romantic") or r:find("ex%-") or r:find("ex ") or r:find("domestic")
                or r:find("life") or r:find("dating") or r:find("spouse") or r:find("husband")
                or r:find("wife") or r:find("girlfriend") or r:find("boyfriend") or r:find("'s partner")
            if is_personal then
                return 25
            else
                return 85
            end
        end

        if r:find("primary antagonist") or r:find("main antagonist") or r:find("arch%-villain") then
            return 80
        end
        if r:find("antagonist") or r:find("villain") or r:find("killer") or r:find("murderer") or r:find("culprit") then
            return 70
        end
        if r:find("victim") or r:find("client") then
            return 40
        end
        if r:find("suspect") or r:find("person of interest") then
            return 35
        end
        if r:find("secondary") or r:find("supporting") or r:find("informant") or r:find("fiance") or r:find("friend") or r:find("mother") or r:find("father") or r:find("brother") or r:find("sister") then
            return 30
        end
        if r:find("minor") or r:find("background") or r:find("incidental") or r:find("extra") then
            return 5
        end

        return 20
    end

    local function getEntityRole(entity)
        if not entity then return nil end
        if entity.role and entity.role ~= "" then return entity.role end
        if entity.states and #entity.states > 0 then
            for i = #entity.states, 1, -1 do
                local s = entity.states[i]
                if s and s.role and s.role ~= "" then return s.role end
            end
        end
        return entity.category or entity.occupation
    end

    local function getChapterCount(entity)
        if not entity then return 0 end
        local chapters = {}
        if entity.states and type(entity.states) == "table" then
            for _, s in ipairs(entity.states) do
                local ch = s.chapter_index or s.chapter_title or s.page_hint
                if ch then chapters[ch] = true end
            end
        end
        if entity.history and type(entity.history) == "table" then
            for _, h in ipairs(entity.history) do
                local ch = h.chapter_index or h.chapter or h.page
                if ch then chapters[ch] = true end
            end
        end
        local count = 0
        for _ in pairs(chapters) do count = count + 1 end
        return count
    end

    local lower_text = text and string.lower(text) or ""

    for _, item in ipairs(list) do
        local name = item[key or "name"]
        if name then
            local lower_name = string.lower(name):gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1")

            -- Signal 1: Role weight
            local role_score = getRoleScore(getEntityRole(item))

            -- Signal 2: Frequency in text (normalized by name length to prevent
            -- short first-name references inflating minor character scores)
            local freq = 0
            if lower_text ~= "" then
                local _, count = string.gsub(lower_text, lower_name, "")
                
                -- Signal 2.1: Always check first and last name fallbacks (very common in prose)
                local first_name = name:match("^(%S+)")
                local last_name  = name:match("(%S+)$")
                
                if first_name and #first_name > 3 and first_name ~= name then
                    local lower_first = string.lower(first_name):gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1")
                    local _, first_count = string.gsub(lower_text, lower_first, "")
                    count = math.max(count, math.floor(first_count / 2))
                end
                
                if last_name and #last_name > 3 and last_name ~= name and last_name ~= first_name then
                    local lower_last = string.lower(last_name):gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1")
                    local _, last_count = string.gsub(lower_text, lower_last, "")
                    -- Last names are often strong identifiers in many book styles
                    count = math.max(count, math.floor(last_count / 1.5))
                end

                -- Signal 2.2: Check aliases for frequency
                if item.aliases and type(item.aliases) == "table" then
                    for _, alias in ipairs(item.aliases) do
                        if type(alias) == "string" and #alias > 3 then
                            local lower_alias = string.lower(alias):gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1")
                            local _, alias_count = string.gsub(lower_text, lower_alias, "")
                            count = count + alias_count
                        end
                    end
                end
                
                -- Normalize: divide by name length bucket to reduce short-name bias
                local name_len_factor = math.max(1, math.floor(#name / 4))
                freq = (count > 0) and math.max(1, math.floor(count / name_len_factor)) or 0
            end

            local mentions_count = (item.mentions and type(item.mentions) == "table" and #item.mentions) or 0
            if mentions_count > 0 then
                freq = math.max(freq, mentions_count * 10)
            end

            -- Signal 3: Chapter count presence
            local ch_count = getChapterCount(item)

            -- Prior-only characters check:
            -- If an item is a prior series character and appears in the current book (freq > 0 or count > 0 or ch_count > 0 or has mentions),
            -- promote it to an active series character so it ranks with the current cast.
            if item.source == "series_prior" and (freq > 0 or (count and count > 0) or ch_count > 0 or mentions_count > 0) then
                item.is_series = true
                item.from_series = true
                item.source = nil
            end

            if item.source == "series_prior" then
                -- Truly prior-only (not mentioned or active in the current book):
                -- Assign negative score so they sort to the very bottom
                item._sort_score = -10000 + (item.source_book or 1) * 100 + role_score
            else
                if freq > 0 then
                    item._sort_score = freq * 100 + role_score * 10 + ch_count * 20
                else
                    item._sort_score = role_score * 10 + ch_count * 20
                end
            end
        else
            item._sort_score = 0
        end
    end

    table.sort(list, function(a, b)
        return (a._sort_score or 0) > (b._sort_score or 0)
    end)
    -- Stamp a persistent sort_order so cache loads can use a cheap numeric sort
    -- instead of rerunning the full regex-based scoring.
    for i, item in ipairs(list) do
        if item.source == "series_prior" and (item._sort_score or 0) < 0 then
            item.sort_order = 10000 + (item.source_book or 1) * 1000 + i
        else
            item.sort_order = i
        end
    end
    return list
end

M.TITLE_CLASSES = {
    ["dr"] = "dr", ["dr."] = "dr", ["doctor"] = "dr",
    ["mr"] = "mr", ["mr."] = "mr", ["mister"] = "mr",
    ["mrs"] = "mrs", ["mrs."] = "mrs", ["missus"] = "mrs",
    ["ms"] = "ms", ["ms."] = "ms", ["miss"] = "ms",
    ["sir"] = "sir",
    ["lady"] = "lady",
    ["lord"] = "lord",
    ["dame"] = "dame",
    ["prof"] = "prof", ["prof."] = "prof", ["professor"] = "prof",
    ["capt"] = "capt", ["capt."] = "capt", ["captain"] = "capt",
    ["col"] = "col", ["col."] = "col", ["colonel"] = "col",
    ["sgt"] = "sgt", ["sgt."] = "sgt", ["sergeant"] = "sgt",
    ["lt"] = "lt", ["lt."] = "lt", ["lieutenant"] = "lt",
    ["rev"] = "rev", ["rev."] = "rev", ["reverend"] = "rev",
    ["insp"] = "insp", ["insp."] = "insp", ["inspector"] = "insp",
    ["mme"] = "mme", ["mme."] = "mme", ["madame"] = "mme",
    ["mlle"] = "mlle", ["mlle."] = "mlle", ["mademoiselle"] = "mlle",
    ["monsieur"] = "monsieur",
    ["herr"] = "herr",
    ["frau"] = "frau",
}

M.NAME_SUFFIXES = {
    ["jr"] = true, ["jr."] = true,
    ["sr"] = true, ["sr."] = true,
    ["ii"] = true, ["iii"] = true,
    ["esq"] = true, ["esq."] = true,
}

local canon_memo, canon_memo_n = {}, 0

function M:canonicalNameKey(name)
    if type(name) ~= "string" or name == "" then return "", nil end
    local hit = canon_memo[name]
    if hit then return hit[1], hit[2] end
    local s = name:lower():gsub("[%.,]", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    local tokens = {}
    for w in s:gmatch("%S+") do tokens[#tokens + 1] = w end
    if #tokens > 1 and tokens[1] == "the" then table.remove(tokens, 1) end
    local title = nil
    while #tokens > 1 and M.TITLE_CLASSES[tokens[1]] do
        title = title or M.TITLE_CLASSES[tokens[1]]
        table.remove(tokens, 1)
    end
    while #tokens > 1 and M.NAME_SUFFIXES[tokens[#tokens]] do table.remove(tokens) end
    local core = table.concat(tokens, " ")
    if core == "" then core = s end
    canon_memo_n = canon_memo_n + 1
    if canon_memo_n > 2000 then canon_memo, canon_memo_n = {}, 1 end
    canon_memo[name] = { core, title }
    return core, title
end

function M:namesMatchCanonical(a, b)
    local ca, ta = self:canonicalNameKey(a)
    local cb, tb = self:canonicalNameKey(b)
    if ca == "" or ca ~= cb then return false end
    return ta == nil or tb == nil or ta == tb
end

function M:isMoreCompleteName(new_name, old_name)
    if not new_name or not old_name then return false end
    if #new_name <= #old_name then return false end
    
    local nl = new_name:lower()
    local ol = old_name:lower()
    local escaped_ol = ol:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
    if nl:find("%f[%w]" .. escaped_ol .. "%f[%W]") then
        return true
    end
    if nl:find("^" .. escaped_ol) or nl:find(escaped_ol .. "$") then
        return true
    end
    return false
end

function M:promoteName(entity, new_name)
    if not entity or not new_name then return end
    local old_name = entity.name
    if not old_name then
        entity.name = new_name
        return
    end
    
    entity.aliases = entity.aliases or {}
    local found = false
    for _, alias in ipairs(entity.aliases) do
        if type(alias) == "string" and alias:lower() == old_name:lower() then 
            found = true; break 
        end
    end
    if not found then
        table.insert(entity.aliases, old_name)
    end
    entity.name = new_name
    entity._norm_name = nil
    entity._norm_aliases = nil
end

function M:deduplicateByName(list, key, caller)
    key = key or "name"
    if not list or #list == 0 then return list end
    caller = caller or self
    local is_anthology = caller.isAnthologyMode and caller:isAnthologyMode()
    local seen = {}       -- canonical names (lowercased) -> array of items
    local alias_map = {}  -- known alias (lowercased) -> array of items
    local deduped = {}

    local function makeKey(k_str, item)
        if is_anthology and item and item.story_id then
            return tostring(item.story_id) .. "::" .. tostring(k_str)
        end
        return tostring(k_str)
    end

    local function findCompatible(bucket, title)
        if not bucket then return nil end
        for _, it in ipairs(bucket) do
            local it_title = it._dedup_title
            if it_title == nil or title == nil or it_title == title then
                return it
            end
        end
        return nil
    end

    for _, item in ipairs(list) do
        if is_anthology and not item.story_id and caller.resolveEntityStory then
            pcall(caller.resolveEntityStory, caller, item)
        end

        local raw_val = item[key] or ""
        local raw_k, title
        if key == "name" then
            raw_k, title = self:canonicalNameKey(raw_val)
        else
            raw_k = raw_val:lower()
            title = nil
        end

        if raw_k == "" then
            table.insert(deduped, item)
        else
            local k = makeKey(raw_k, item)
            -- Check 1: exact/canonical name duplicate
            local existing = findCompatible(seen[k], title)

            -- Check 2: canonical name matches a known alias of an accepted entry
            if not existing then
                existing = findCompatible(alias_map[k], title)
            end

            -- Check 3: first-name component of canonical name matches a known alias
            if not existing then
                local first = raw_k:match("^(%S+)")
                if first and first ~= raw_k and #first >= 5 then
                    existing = findCompatible(alias_map[makeKey(first, item)], title)
                end
            end

            if not existing then
                item._dedup_title = title
                seen[k] = seen[k] or {}
                table.insert(seen[k], item)
                table.insert(deduped, item)
                -- Register all aliases of this accepted entry
                if item.aliases and type(item.aliases) == "table" then
                    for _, alias in ipairs(item.aliases) do
                        if type(alias) == "string" and alias ~= "" then
                            local a_core, a_title
                            if key == "name" then
                                a_core, a_title = self:canonicalNameKey(alias)
                            else
                                a_core = alias:lower()
                                a_title = nil
                            end
                            if a_core ~= "" then
                                local ak = makeKey(a_core, item)
                                alias_map[ak] = alias_map[ak] or {}
                                table.insert(alias_map[ak], item)
                            end
                        end
                    end
                end
            else
                -- Handle duplicate: dynamically promote name if incoming is more complete
                if key == "name" and self:isMoreCompleteName(item.name, existing.name) then
                    local old_name = existing.name
                    self:promoteName(existing, item.name)
                    if caller.migrateStoryPresence then
                        caller:migrateStoryPresence(old_name, existing.name)
                    end
                    local new_k, new_title = self:canonicalNameKey(existing.name)
                    existing._dedup_title = new_title
                    local new_key = makeKey(new_k, existing)
                    seen[new_key] = seen[new_key] or {}
                    local already_in_bucket = false
                    for _, b_it in ipairs(seen[new_key]) do
                        if b_it == existing then already_in_bucket = true; break end
                    end
                    if not already_in_bucket then table.insert(seen[new_key], existing) end
                end
                
                -- Merge aliases from incoming duplicate
                if item.aliases and type(item.aliases) == "table" then
                    existing.aliases = existing.aliases or {}
                    for _, new_alias in ipairs(item.aliases) do
                        if type(new_alias) == "string" and new_alias ~= "" then
                            local found = false
                            for _, old_alias in ipairs(existing.aliases) do
                                if type(old_alias) == "string" and old_alias:lower() == new_alias:lower() then
                                    found = true; break
                                end
                            end
                            if not found and new_alias:lower() ~= existing.name:lower() then
                                table.insert(existing.aliases, new_alias)
                                existing._norm_aliases = nil
                                local a_core, a_title
                                if key == "name" then
                                    a_core, a_title = self:canonicalNameKey(new_alias)
                                else
                                    a_core = new_alias:lower()
                                    a_title = nil
                                end
                                if a_core ~= "" then
                                    local ak = makeKey(a_core, existing)
                                    alias_map[ak] = alias_map[ak] or {}
                                    table.insert(alias_map[ak], existing)
                                end
                            end
                        end
                    end
                end

                -- Merge mentions from incoming duplicate
                if item.mentions and type(item.mentions) == "table" then
                    existing.mentions = existing.mentions or {}
                    for _, new_m in ipairs(item.mentions) do
                        table.insert(existing.mentions, new_m)
                    end
                end
            end
        end
    end

    for _, it in ipairs(deduped) do
        it._dedup_title = nil
    end

    return deduped
end

function M:normalizeChapterName(name)
    if not name then return "" end
    local s = name:lower():gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    -- Replace written-out numbers with digits using word boundaries
    for word, num in pairs(word_to_num) do
        s = s:gsub("%f[%a]" .. word .. "%f[%A]", tostring(num))
    end
    -- Strip common prefixes like "chapter" so "chapter 13" and "13" both become "13"
    s = s:gsub("^chapter%s*", ""):gsub("^ch%.?%s*", "")
    s = s:gsub("^part%s*", ""):gsub("^book%s*", "")
    
    -- Try to convert Roman numerals if the remaining string is a valid Roman numeral
    -- We only do this if it's not already a digit
    if not s:match("^%d+$") and s:match("^[ivxlcdm]+$") then
        local dec = romanToDecimal(s)
        if dec then s = tostring(dec) end
    end
    
    return s
end

function M:isNonNarrativeChapter(title)
    if not title then return true end
    local lower = title:lower():gsub("^%s+", ""):gsub("%s+$", "")
    if lower == "" then return true end
    local patterns = {
        "^cover$", "^title", "^half%-title", "^copyright", "^table of contents",
        "^contents$", "^dedication", "^acknowledgment", "^also by", "^other books",
        "^about the author", "^about the", "^epigraph$", "^foreword$",
        "^preface$", "^appendix", "^glossary", "^index$", "^notes$",
        "^bibliography", "^colophon", "^frontispiece", "^books by",
        "^praise for", "^reviews", "^blurb",
    }
    for _, pat in ipairs(patterns) do
        if lower:match(pat) then return true end
    end
    return false
end

function M:assignTimelinePages(timeline, raw_toc, allow_findtext)
    if not raw_toc or not timeline or #timeline == 0 then return end

    local toc = {}
    local function flatten(nodes)
        if not nodes then return end
        for _, node in ipairs(nodes) do
            table.insert(toc, node)
            if type(node) == "table" then
                if #node > 0 then flatten(node)
                elseif node.sub_item_table then flatten(node.sub_item_table)
                elseif node.children then flatten(node.children)
                end
            end
        end
    end
    flatten(raw_toc)
    if #toc == 0 then return end

    -- Build ORDERED QUEUES (not single-value maps) for each match strategy.
    -- key → list of pages in TOC order, so the Nth event with that key gets the Nth page.
    local q_norm   = {}  -- normalized title → {page, page, ...}
    local q_number = {}  -- leading digit    → {page, page, ...}
    local q_suffix = {}  -- title-after-num  → {page, page, ...}
    local all_toc  = {}  -- flat list {norm, page, used} for substring fallback

    local function push(t, key, val)
        if not t[key] then t[key] = { list = {}, idx = 0 } end
        table.insert(t[key].list, val)
    end

    for i, entry in ipairs(toc) do
        if entry.page and entry.title then
            local p = tonumber(entry.page)
            if p then
                local toc_idx = entry.toc_index or i
                local info = { page = p, toc_index = toc_idx, entry = entry }
                local norm = self:normalizeChapterName(entry.title)
                push(q_norm, norm, info)

                local num = norm:match("^(%d+)")
                if num then push(q_number, num, info) end

                local suffix = norm:match("^%d+[%s%.%:%-]+(.+)$")
                if suffix and suffix ~= "" then push(q_suffix, suffix, info) end

                table.insert(all_toc, { norm = norm, info = info, used = false })
            end
        end
    end

    -- Pop the next unused item for a key (consumes in order)
    local function pop(q, key)
        local bucket = q[key]
        if not bucket then return nil end
        bucket.idx = bucket.idx + 1
        return bucket.list[bucket.idx]
    end

    local is_anthology = self.isAnthologyMode and self:isAnthologyMode()

    for _, ev in ipairs(timeline) do
        if ev.source ~= "series_prior" then
            local norm = self:normalizeChapterName(ev.chapter or "")
            local matched_info = nil

            -- Strategy 1: Exact normalized title (queue-based)
            if q_norm[norm] then
                matched_info = pop(q_norm, norm)
            end

            -- Strategy 2: Leading number (queue-based)
            if not matched_info then
                local num = norm:match("^(%d+)")
                if num and q_number[num] then
                    matched_info = pop(q_number, num)
                end
            end

            -- Strategy 3: AI suffix vs TOC suffix or norm (queue-based)
            if not matched_info then
                local ai_suffix = norm:match("^%d+[%s%.%:%-]+(.+)$")
                if ai_suffix then
                    if q_suffix[ai_suffix] then
                        matched_info = pop(q_suffix, ai_suffix)
                    elseif q_norm[ai_suffix] then
                        matched_info = pop(q_norm, ai_suffix)
                    end
                end
            end

            -- Strategy 4: AI title as suffix (queue-based)
            if not matched_info and q_suffix[norm] then
                matched_info = pop(q_suffix, norm)
            end

            -- Strategy 5: Substring match (linear scan, consume each TOC entry once)
            if not matched_info and #norm > 2 then
                for _, t in ipairs(all_toc) do
                    if not t.used then
                        if t.norm:find(norm, 1, true) or norm:find(t.norm, 1, true) then
                            matched_info = t.info
                            t.used = true
                            break
                        end
                    end
                end
            end

            local page = matched_info and matched_info.page or nil
            if matched_info and matched_info.toc_index then
                ev.chapter_index = tonumber(matched_info.toc_index)
            end

            -- Strategy 6: NO-TOC FALLBACK - search document text for the chapter heading.
            if allow_findtext and not page and self.ui and self.ui.document and self.ui.document.findText then
                if #norm > 3 and not norm:match("^section") then
                    local success, results = pcall(function()
                        return self.ui.document:findText(ev.chapter or "", 20)
                    end)
                    if success and results and #results > 0 then
                        page = results[1].page
                    end
                end
            end

            if page then
                ev.page = tonumber(page)
            end

            if is_anthology and self.chapter_analyzer then
                local story = nil
                if ev.page then
                    story = self.chapter_analyzer:getStoryForPage(self.ui, ev.page)
                end
                if not story and ev.chapter_index then
                    story = self.chapter_analyzer:getStoryForTocIndex(self.ui, ev.chapter_index)
                end
                if story then
                    ev.story_id = story.story_id
                    ev.story_title = story.story_title
                end
            end
        end
    end
end

function M:filterOrphanTimelineEvents(timeline, raw_toc)
    if not timeline or #timeline == 0 then return timeline end
    if not raw_toc or #raw_toc == 0 then return timeline end

    local filtered = {}
    for _, ev in ipairs(timeline) do
        if ev.source == "series_prior" or (ev.page and tonumber(ev.page)) then
            table.insert(filtered, ev)
        else
            if self.log then
                self:log("XRayPlugin: Filtering orphan/hallucinated timeline event: " .. tostring(ev.chapter))
            end
        end
    end
    return filtered
end

function M:sortTimelineByTOC(timeline)
    if not timeline or #timeline == 0 then return end
    
    -- Store original index for a stable sort (prevents shuffling events on the same page)
    for i, ev in ipairs(timeline) do ev._sort_idx = i end
    
    table.sort(timeline, function(a, b)
        -- Explicitly sort series prior events to the very top chronologically by book index
        if a.source == "series_prior" and b.source ~= "series_prior" then
            return true
        elseif a.source ~= "series_prior" and b.source == "series_prior" then
            return false
        elseif a.source == "series_prior" and b.source == "series_prior" then
            return (a.source_book or 0) < (b.source_book or 0)
        end

        -- Primary key: Page number (must be numeric)
        local ap = tonumber(a.page) or 999999
        local bp = tonumber(b.page) or 999999
        
        if ap ~= bp then
            return ap < bp
        end
        
        -- Secondary key: Original AI response order (stability)
        return (a._sort_idx or 0) < (b._sort_idx or 0)
    end)
    
    -- Clean up temporary index
    for _, ev in ipairs(timeline) do ev._sort_idx = nil end
end

function M:mergeEntryItems(list, primary, secondary, ai_merged_desc)
    if not primary or not secondary or primary == secondary then return false end
    local sec_idx = nil
    for i, item in ipairs(list) do
        if item == secondary then
            sec_idx = i
            break
        end
    end
    if not sec_idx then return false end

    local old_primary_name = primary.name

    -- 1. Check for Name Promotion (if secondary name is more complete)
    if self:isMoreCompleteName(secondary.name, primary.name) then
        self:promoteName(primary, secondary.name)
    else
        -- Absorb secondary's name as an alias of primary (if not already present)
        primary.aliases = primary.aliases or {}
        local already = false
        for _, a in ipairs(primary.aliases) do
            if type(a) == "string" and a:lower() == secondary.name:lower() then already = true; break end
        end
        if not already then table.insert(primary.aliases, secondary.name) end
    end
    primary._norm_name = nil
    primary._norm_aliases = nil

    -- 2. Absorb secondary's aliases (deduplicated)
    local existing_aliases = {}
    for _, a in ipairs(primary.aliases) do existing_aliases[a:lower()] = true end
    if secondary.aliases then
        for _, a in ipairs(secondary.aliases) do
            if type(a) == "string" and not existing_aliases[a:lower()] 
               and a:lower() ~= primary.name:lower() then
                table.insert(primary.aliases, a)
                existing_aliases[a:lower()] = true
            end
        end
    end

    -- 3. Merge description
    if ai_merged_desc and ai_merged_desc ~= "" then
        primary.description = ai_merged_desc
    elseif secondary.description and secondary.description ~= ""
       and secondary.description ~= primary.description then
        primary.description = (primary.description or "") 
            .. "\n[Also known as " .. secondary.name .. ": " .. secondary.description .. "]"
    end

    -- 4. Merge mentions from secondary into primary
    if secondary.mentions and type(secondary.mentions) == "table" then
        primary.mentions = primary.mentions or {}
        for _, m in ipairs(secondary.mentions) do
            table.insert(primary.mentions, m)
        end
    end

    -- 5. Remove secondary from list
    table.remove(list, sec_idx)
    return true, old_primary_name
end

function M:mergeEntries(list, primary_name, secondary_name, ai_merged_desc, story_id)
    local primary, secondary = nil, nil
    for _, item in ipairs(list) do
        local matches_story = not story_id or (item.story_id == story_id)
        if matches_story and item.name and item.name:lower() == primary_name:lower() and not primary then
            primary = item
        elseif matches_story and item.name and item.name:lower() == secondary_name:lower() and not secondary then
            secondary = item
        end
    end
    if not primary or not secondary then return false end
    return self:mergeEntryItems(list, primary, secondary, ai_merged_desc)
end

function M:linkEntriesAcrossStories(list, anchor, local_item)
    if not anchor or not local_item or anchor == local_item then return nil end
    local local_sid = local_item.story_id

    -- If the local story already holds an entry matching the anchor name, merge into it.
    for _, it in ipairs(list) do
        if it ~= local_item and it ~= anchor and it.story_id == local_sid
           and self:namesMatchCanonical(it.name, anchor.name) then
            self:mergeEntryItems(list, it, local_item)
            it.is_recurring = true
            anchor.is_recurring = true
            return it
        end
    end

    if (local_item.name or ""):lower() ~= (anchor.name or ""):lower() then
        self:promoteName(local_item, anchor.name) -- old name becomes alias
    end
    local_item.aliases = local_item.aliases or {}
    local existing_aliases = {}
    for _, a in ipairs(local_item.aliases) do
        if type(a) == "string" then existing_aliases[a:lower()] = true end
    end
    for _, a in ipairs(anchor.aliases or {}) do
        if type(a) == "string" and a ~= "" and not existing_aliases[a:lower()] and a:lower() ~= local_item.name:lower() then
            table.insert(local_item.aliases, a)
            existing_aliases[a:lower()] = true
        end
    end
    local_item._norm_name = nil
    local_item._norm_aliases = nil
    local_item.is_recurring = true
    anchor.is_recurring = true
    return local_item
end

function M:isNonFictionBook(props, text_sample)
    local subject = ((props and (props.subject or props.subjects or props.categories or props.category)) or ""):lower()
    local genres = {"history","science","biography","memoir","self-help","business",
        "economics","technology","psychology","politics","philosophy","true crime",
        "nature","travel","health","reference","nonfiction","non-fiction","education","textbook"}
    for _, g in ipairs(genres) do
        if subject:find(g, 1, true) then return true end
    end
    if text_sample then
        local _, ac = text_sample:gsub("%f[%u]%u%u%u%u+%f[%U]", "")
        local _, wc = text_sample:gsub("%S+", "")
        if ac / math.max(1, wc) > 0.03 then return true end
        local _, cc = text_sample:gsub("%[%d+%]", "")
        if cc > 5 then return true end
    end
    return false
end

return M
