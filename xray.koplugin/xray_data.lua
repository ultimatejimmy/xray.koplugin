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
        if not role then return 0 end
        local r = role:lower()
        if r:find("protagonist") then return 100 end
        if r:find("main") or r:find("lead") or r:find("hero") or r:find("detective") then return 90 end
        if r:find("deuteragonist") then return 80 end
        if r:find("major") or r:find("antagonist") or r:find("villain") or r:find("primary") then return 70 end
        if r:find("secondary") or r:find("supporting") then return 30 end
        if r:find("minor") or r:find("background") then return 5 end
        return 15 -- Default for other specific roles
    end

    local lower_text = text and string.lower(text) or ""

    for _, item in ipairs(list) do
        local name = item[key or "name"]
        if name then
            local lower_name = string.lower(name):gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1")

            -- Signal 1: Role weight
            local role_score = getRoleScore(item.role)

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
                freq = math.floor(count / name_len_factor)
            end

            item._sort_score = role_score * 1000 + freq
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
        item.sort_order = i
    end
    return list
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
end

function M:deduplicateByName(list, key)
    key = key or "name"
    if not list or #list == 0 then return list end
    local seen = {}       -- canonical names (lowercased) -> item ref
    local alias_map = {}  -- known alias (lowercased) -> item ref
    local deduped = {}

    for _, item in ipairs(list) do
        local k = (item[key] or ""):lower()
        if k == "" then
            table.insert(deduped, item)
        else
            -- Check 1: exact canonical name duplicate
            local existing = seen[k]

            -- Check 2: canonical name matches a known alias of an accepted entry
            if not existing then
                existing = alias_map[k]
            end

            -- Check 3: first-name component of canonical name matches a known alias
            if not existing then
                local first = k:match("^(%S+)")
                if first and first ~= k and #first >= 5 then
                    existing = alias_map[first]
                end
            end

            if not existing then
                seen[k] = item
                table.insert(deduped, item)
                -- Register all aliases of this accepted entry
                if item.aliases and type(item.aliases) == "table" then
                    for _, alias in ipairs(item.aliases) do
                        if type(alias) == "string" and alias ~= "" then
                            alias_map[alias:lower()] = item
                        end
                    end
                end
            else
                -- Handle duplicate: dynamically promote name if incoming is more complete
                if key == "name" and self:isMoreCompleteName(item.name, existing.name) then
                    self:promoteName(existing, item.name)
                    seen[item.name:lower()] = existing
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
                                alias_map[new_alias:lower()] = existing
                            end
                        end
                    end
                end
            end
        end
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

function M:assignTimelinePages(timeline, toc, allow_findtext)
    if not toc or not timeline or #timeline == 0 then return end

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

    for _, entry in ipairs(toc) do
        if entry.page and entry.title then
            local p = tonumber(entry.page)
            if p then
                local norm = self:normalizeChapterName(entry.title)
                push(q_norm, norm, p)

                local num = norm:match("^(%d+)")
                if num then push(q_number, num, p) end

                local suffix = norm:match("^%d+[%s%.%:%-]+(.+)$")
                if suffix and suffix ~= "" then push(q_suffix, suffix, p) end

                table.insert(all_toc, { norm = norm, page = p, used = false })
            end
        end
    end

    -- Pop the next unused page for a key (consumes in order)
    local function pop(q, key)
        local bucket = q[key]
        if not bucket then return nil end
        bucket.idx = bucket.idx + 1
        return bucket.list[bucket.idx]
    end

    for _, ev in ipairs(timeline) do
        local norm = self:normalizeChapterName(ev.chapter or "")
        local page = nil

        -- Strategy 1: Exact normalized title (queue-based)
        if q_norm[norm] then
            page = pop(q_norm, norm)
        end

        -- Strategy 2: Leading number (queue-based)
        if not page then
            local num = norm:match("^(%d+)")
            if num and q_number[num] then
                page = pop(q_number, num)
            end
        end

        -- Strategy 3: AI suffix vs TOC suffix or norm (queue-based)
        if not page then
            local ai_suffix = norm:match("^%d+[%s%.%:%-]+(.+)$")
            if ai_suffix then
                if q_suffix[ai_suffix] then
                    page = pop(q_suffix, ai_suffix)
                elseif q_norm[ai_suffix] then
                    page = pop(q_norm, ai_suffix)
                end
            end
        end

        -- Strategy 4: AI title as suffix (queue-based)
        if not page and q_suffix[norm] then
            page = pop(q_suffix, norm)
        end

        -- Strategy 5: Substring match (linear scan, consume each TOC entry once)
        if not page and #norm > 2 then
            for _, t in ipairs(all_toc) do
                if not t.used then
                    if t.norm:find(norm, 1, true) or norm:find(t.norm, 1, true) then
                        page = t.page
                        t.used = true
                        break
                    end
                end
            end
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
    end
end

function M:sortTimelineByTOC(timeline)
    if not timeline or #timeline == 0 then return end
    
    -- Store original index for a stable sort (prevents shuffling events on the same page)
    for i, ev in ipairs(timeline) do ev._sort_idx = i end
    
    table.sort(timeline, function(a, b)
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

function M:mergeEntries(list, primary_name, secondary_name, ai_merged_desc)
    local primary, secondary, sec_idx = nil, nil, nil
    for i, item in ipairs(list) do
        if item.name and item.name:lower() == primary_name:lower() then
            primary = item
        elseif item.name and item.name:lower() == secondary_name:lower() then
            secondary = item
            sec_idx = i
        end
    end
    if not primary or not secondary then return false end

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

    -- 4. Remove secondary from list
    table.remove(list, sec_idx)
    return true
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
