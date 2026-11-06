-- xray_evolution.lua — Milestone extraction, novelty diffing, and key change filtering for KOReader X-Ray
-- Pure logic module with no UI dependencies.

local Evolution = {}

-- Novelty thresholds
Evolution.MIN_TOKEN_LENGTH = 4
Evolution.MIN_NOVEL_TOKENS = 5
Evolution.NOVEL_RATIO_THRESHOLD = 0.25
Evolution.MAX_NOVEL_TERMS = 5
Evolution.MAX_NOVEL_SENTENCES = 3

-- Stop words for novelty diffing to avoid false positives on common English connectors
local STOP_WORDS = {
    ["that"] = true, ["this"] = true, ["with"] = true, ["from"] = true,
    ["they"] = true, ["them"] = true, ["their"] = true, ["theirs"] = true,
    ["have"] = true, ["been"] = true, ["were"] = true, ["what"] = true,
    ["when"] = true, ["where"] = true, ["which"] = true, ["there"] = true,
    ["about"] = true, ["after"] = true, ["before"] = true, ["other"] = true,
    ["some"] = true, ["such"] = true, ["than"] = true, ["then"] = true,
    ["into"] = true, ["only"] = true, ["also"] = true, ["most"] = true,
    ["over"] = true, ["even"] = true, ["will"] = true, ["would"] = true,
    ["could"] = true, ["should"] = true, ["more"] = true, ["much"] = true,
    ["very"] = true, ["each"] = true, ["both"] = true, ["down"] = true,
    ["under"] = true, ["while"] = true, ["during"] = true, ["through"] = true,
    ["does"] = true, ["doing"] = true, ["having"] = true, ["these"] = true,
    ["those"] = true, ["being"] = true, ["again"] = true, ["further"] = true,
    ["because"] = true, ["until"] = true,
}

local function safe_str(val)
    if val == nil then return "" end
    if type(val) == "string" then return val end
    if type(val) == "number" or type(val) == "boolean" then return tostring(val) end
    if type(val) == "table" then
        local acc = {}
        for _, item in ipairs(val) do
            if type(item) == "string" or type(item) == "number" then
                table.insert(acc, tostring(item))
            end
        end
        return table.concat(acc, ", ")
    end
    return tostring(val)
end

local function tokenize(text)
    if not text or type(text) ~= "string" or text == "" then
        return {}, {}
    end
    local lower_tokens = {}
    local orig_tokens = {}
    local seen = {}
    for word in text:gmatch("[%a\128-\255]+") do
        if #word >= Evolution.MIN_TOKEN_LENGTH then
            local lword = word:lower()
            if not STOP_WORDS[lword] then
                table.insert(lower_tokens, lword)
                if not seen[lword] then
                    seen[lword] = true
                    table.insert(orig_tokens, word)
                end
            end
        end
    end
    return lower_tokens, orig_tokens
end

local function extract_sentences(text)
    if not text or type(text) ~= "string" or text == "" then return {} end
    local sentences = {}
    for s in text:gmatch("[^.!?\n\r]+[.!?]?") do
        s = s:gsub("^%s+", ""):gsub("%s+$", "")
        if #s > 10 then
            table.insert(sentences, s)
        end
    end
    if #sentences == 0 and #text > 0 then
        table.insert(sentences, text)
    end
    return sentences
end

local function find_novel_sentences(sentences, novel_set, max_count)
    local results = {}
    for _, s in ipairs(sentences) do
        local has_novel = false
        for word in s:gmatch("[%a\128-\255]+") do
            if novel_set[word:lower()] then
                has_novel = true
                break
            end
        end
        if has_novel then
            table.insert(results, s)
            if #results >= max_count then break end
        end
    end
    return results
end

local function sort_novel_terms(orig_tokens, novel_set)
    local proper = {}
    local common = {}
    local seen = {}
    for _, orig in ipairs(orig_tokens) do
        local lword = orig:lower()
        if novel_set[lword] and not seen[lword] then
            seen[lword] = true
            -- Proper noun check: starts with an uppercase letter
            if orig:match("^[A-Z\192-\222]") then
                table.insert(proper, orig)
            else
                table.insert(common, orig)
            end
        end
    end
    local combined = {}
    for _, w in ipairs(proper) do
        table.insert(combined, w)
        if #combined >= Evolution.MAX_NOVEL_TERMS then return combined end
    end
    for _, w in ipairs(common) do
        table.insert(combined, w)
        if #combined >= Evolution.MAX_NOVEL_TERMS then return combined end
    end
    return combined
end

function Evolution.build(entity, ctx)
    if not entity or type(entity) ~= "table" then return {} end
    ctx = ctx or {}
    local plugin = ctx.plugin
    local cur_chap = tonumber(ctx.cur_chap)
    local cur_page = tonumber(ctx.cur_page)
    local is_full_book = (ctx.is_full_book == true)
    local show_all = (ctx.show_all == true) or is_full_book
    local resolveChapter = type(ctx.resolveChapter) == "function" and ctx.resolveChapter or nil

    local raw_items = {}

    -- 1. Ingest entity.states
    if entity.states and type(entity.states) == "table" then
        for _, s in ipairs(entity.states) do
            if type(s) == "table" then
                local ch_idx = tonumber(s.chapter_index)
                local ch_title = (type(s.chapter_title) == "string" and s.chapter_title ~= "") and s.chapter_title or nil
                if not ch_idx and ch_title then
                    local num_in_title = tonumber(ch_title:match("(%d+)"))
                    if num_in_title then ch_idx = num_in_title end
                end
                local pg = tonumber(s.page_hint or s.page)
                if resolveChapter then
                    ch_idx, ch_title = resolveChapter(pg, ch_title, ch_idx)
                end
                table.insert(raw_items, {
                    source = "state",
                    chapter_index = ch_idx,
                    chapter_title = ch_title,
                    page = pg,
                    chapter_pct = s.chapter_pct,
                    ch_start_page = s.ch_start_page,
                    ch_end_page = s.ch_end_page,
                    role = safe_str(s.role),
                    status = safe_str(s.status),
                    description = safe_str(s.description),
                    evidence = safe_str(s.evidence),
                    change = safe_str(s.change),
                })
            end
        end
    end

    -- 2. Ingest entity.history
    if entity.history and type(entity.history) == "table" then
        for _, h in ipairs(entity.history) do
            if type(h) == "table" then
                local ch_idx = tonumber(h.chapter_index)
                local ch_title = (type(h.chapter_title) == "string" and h.chapter_title ~= "") and h.chapter_title or nil
                if not ch_idx and h.chapter ~= nil then
                    local num = tonumber(h.chapter)
                    if num then
                        ch_idx = num
                    elseif type(h.chapter) == "string" and h.chapter ~= "" then
                        ch_title = h.chapter
                        local num_in_title = tonumber(h.chapter:match("(%d+)"))
                        if num_in_title then ch_idx = num_in_title end
                    end
                end
                if not ch_idx and ch_title then
                    local num_in_title = tonumber(ch_title:match("(%d+)"))
                    if num_in_title then ch_idx = num_in_title end
                end
                local pg = tonumber(h.page_hint or h.page)
                if resolveChapter then
                    ch_idx, ch_title = resolveChapter(pg, ch_title, ch_idx)
                end
                table.insert(raw_items, {
                    source = "history",
                    chapter_index = ch_idx,
                    chapter_title = ch_title,
                    page = pg,
                    role = safe_str(h.role),
                    status = safe_str(h.status),
                    description = safe_str(h.description or h.biography or h.definition),
                    evidence = safe_str(h.evidence),
                    change = safe_str(h.change),
                })
            end
        end
    end

    if #raw_items == 0 then
        -- Fallback: if no states or history, but entity has base fields, create a single baseline milestone
        local base_desc = safe_str(entity.description or entity.biography or entity.definition)
        if base_desc ~= "" and base_desc ~= "---" then
            table.insert(raw_items, {
                source = "base",
                chapter_index = 1,
                chapter_title = nil,
                page = tonumber(entity.page),
                role = safe_str(entity.role),
                status = safe_str(entity.status or "alive"),
                description = base_desc,
                evidence = "",
                change = "",
            })
        end
    end

    -- 3. De-duplicate entries that point to the same chapter and page
    -- or have identical description at the same chapter/page
    local deduped = {}
    local seen_keys = {}
    for _, it in ipairs(raw_items) do
        local key = string.format("c:%s_p:%s_d:%s",
            tostring(it.chapter_index or it.chapter_title or ""),
            tostring(it.page or ""),
            it.description:sub(1, 40))
        local existing = seen_keys[key]
        if existing then
            -- Merge: prefer state over history, adopt missing non-empty fields
            if existing.source == "history" and it.source == "state" then
                it.evidence = (it.evidence ~= "" and it.evidence) or existing.evidence
                it.role = (it.role ~= "" and it.role) or existing.role
                it.status = (it.status ~= "" and it.status) or existing.status
                it.change = (it.change ~= "" and it.change) or existing.change
                deduped[existing._idx] = it
                it._idx = existing._idx
                seen_keys[key] = it
            else
                existing.evidence = (existing.evidence ~= "" and existing.evidence) or it.evidence
                existing.role = (existing.role ~= "" and existing.role) or it.role
                existing.status = (existing.status ~= "" and existing.status) or it.status
                existing.change = (existing.change ~= "" and existing.change) or it.change
            end
        else
            it._idx = #deduped + 1
            table.insert(deduped, it)
            seen_keys[key] = it
        end
    end
    for _, it in ipairs(deduped) do it._idx = nil end

    -- 4. Sort chronologically by chapter, then page
    table.sort(deduped, function(a, b)
        local ca = a.chapter_index or 0
        local cb = b.chapter_index or 0
        if ca > 0 and cb > 0 and ca ~= cb then
            return ca < cb
        end
        local pa = a.page or 0
        local pb = b.page or 0
        if pa > 0 and pb > 0 and pa ~= pb then
            return pa < pb
        end
        if ca ~= cb then return ca < cb end
        return pa < pb
    end)

    -- 5. Diffing & Novelty Analysis
    local cumulative_vocab = {}
    local prev_role = nil
    local prev_status = nil
    local milestones = {}

    for i, it in ipairs(deduped) do
        local m = {
            idx = i,
            source = it.source,
            chapter_index = it.chapter_index,
            chapter_title = it.chapter_title,
            page = it.page,
            role = it.role,
            status = it.status,
            description = it.description,
            evidence = it.evidence,
            change = it.change,
            chapter_pct = it.chapter_pct,
            ch_start_page = it.ch_start_page,
            ch_end_page = it.ch_end_page,
            new_terms = {},
            new_sentences = {},
        }

        local ltokens, otokens = tokenize(m.description)
        local sentences = extract_sentences(m.description)

        if i == 1 then
            m.kind = "first"
            for _, t in ipairs(ltokens) do
                cumulative_vocab[t] = true
            end
            prev_role = (m.role ~= "" and m.role) or (entity.role and safe_str(entity.role) ~= "" and safe_str(entity.role)) or nil
            prev_status = (m.status ~= "" and m.status) or (entity.status and safe_str(entity.status) ~= "" and safe_str(entity.status)) or nil
            if m.role == "" and prev_role then m.role = prev_role end
            if m.status == "" and prev_status then m.status = prev_status end
        else
            local role_changed = false
            if m.role ~= "" then
                if prev_role and m.role ~= prev_role then
                    role_changed = true
                    m.role_from = prev_role
                    prev_role = m.role
                elseif not prev_role then
                    role_changed = true
                    prev_role = m.role
                end
            elseif prev_role then
                m.role = prev_role
            end

            local status_changed = false
            if m.status ~= "" then
                if prev_status and m.status ~= prev_status then
                    status_changed = true
                    m.status_from = prev_status
                    prev_status = m.status
                elseif not prev_status then
                    status_changed = true
                    prev_status = m.status
                end
            elseif prev_status then
                m.status = prev_status
            end

            local novel_set = {}
            local novel_count = 0
            for _, t in ipairs(ltokens) do
                if not cumulative_vocab[t] then
                    if not novel_set[t] then
                        novel_count = novel_count + 1
                    end
                    novel_set[t] = true
                end
            end

            local ratio = novel_count / math.max(1, #ltokens)
            local has_change = (m.change and m.change ~= "" and m.change ~= "---")
            local is_vocab_key = (novel_count >= Evolution.MIN_NOVEL_TOKENS and ratio >= Evolution.NOVEL_RATIO_THRESHOLD)

            if role_changed or status_changed or has_change or is_vocab_key then
                m.kind = "key"
            else
                m.kind = "reworded"
            end

            m.new_terms = sort_novel_terms(otokens, novel_set)
            m.new_sentences = find_novel_sentences(sentences, novel_set, Evolution.MAX_NOVEL_SENTENCES)

            for _, t in ipairs(ltokens) do
                cumulative_vocab[t] = true
            end
        end

        table.insert(milestones, m)
    end

    -- 6. Spoiler lock & is_current
    local best_unlocked_idx = nil
    for idx, m in ipairs(milestones) do
        if show_all then
            m.is_locked = false
        elseif plugin and plugin.isPositionGateUnlocked then
            local is_upd = (idx > 1) or (entity and (entity.is_series or entity.from_series))
            local gate = {
                chapter_index = m.chapter_index,
                page_hint = m.page,
                chapter_pct = m.chapter_pct,
                ch_start_page = m.ch_start_page,
                ch_end_page = m.ch_end_page,
            }
            m.is_locked = not plugin:isPositionGateUnlocked(gate, cur_chap, cur_page, { is_state_update = is_upd })
        else
            local locked = false
            if m.chapter_index and cur_chap then
                if m.chapter_index > cur_chap then
                    locked = true
                elseif m.chapter_index == cur_chap then
                    if m.page and cur_page and m.page > cur_page then
                        locked = true
                    end
                end
            elseif m.page and cur_page then
                if m.page > cur_page then
                    locked = true
                end
            end
            m.is_locked = locked
        end

        if not m.is_locked then
            best_unlocked_idx = idx
        end
    end

    if best_unlocked_idx then
        milestones[best_unlocked_idx].is_current = true
    end

    return milestones
end

function Evolution.filterKey(milestones)
    if not milestones or type(milestones) ~= "table" then return {} end
    local filtered = {}
    local best_unlocked_idx = nil

    for _, m in ipairs(milestones) do
        if m.kind ~= "reworded" then
            local copy = {}
            for k, v in pairs(m) do copy[k] = v end
            copy.is_current = false
            copy.idx = #filtered + 1
            table.insert(filtered, copy)
            if not copy.is_locked then
                best_unlocked_idx = copy.idx
            end
        end
    end

    if best_unlocked_idx and filtered[best_unlocked_idx] then
        filtered[best_unlocked_idx].is_current = true
    end

    return filtered
end

return Evolution
