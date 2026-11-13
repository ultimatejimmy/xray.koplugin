-- xray_entityscanner.lua - Native Entity Footnotes with Asynchronous Background Scanning
-- Underlines AI-identified entities (characters, historical figures, locations, terms)
-- directly in the reading text and shows footnote-style popup or compact tooltip on tap.
-- Matches against entities already extracted into self.characters / self.historical_figures /
-- self.locations / self.terms without freezing reading or page turns.

local UIManager = require("ui/uimanager")
local Screen = require("device").screen
local Blitbuffer = require("ffi/blitbuffer")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local TextBoxWidget = require("ui/widget/textboxwidget")
local ProgressBarDialog = require("ui/widget/progressbardialog")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local DocSettings = require("docsettings")
local OverlapGroup = require("ui/widget/overlapgroup")
local Widget = require("ui/widget/widget")

local plugin_path = ((...) or ""):match("(.-)[^%.]+$") or ""
local XRayLogger = require(plugin_path .. "xray_logger")
local xray_utils = require(plugin_path .. "xray_utils")
local xray_theme = require(plugin_path .. "xray_theme")

local function log(msg)
    XRayLogger:log("EntityScanner: " .. tostring(msg))
end

local M = {}

-- Idempotency flag for Dukko's user patch: if 2-xray-entity-footnotes.lua is installed,
-- its userpatch hook checks this flag and exits immediately, preventing conflicts.
M.__entity_footnotes_patched = true

local ENTITY_SCAN_POLL_INTERVAL = 0.1   -- 100ms poll for child process
local ENTITY_SCAN_TIMEOUT = 300         -- 5 minutes watchdog
local ENTITY_SCAN_SLICE = 0.03          -- 30ms coroutine slice for in-process fallback
local MIN_TERM_LEN = 3                  -- Minimum character length for entity terms
local MAX_REGEX_LEN = 3000              -- SRELL regex engine safe chunk size

local CATEGORY_LABELS = {
    character = "Character",
    historical_figure = "Historical Figure",
    location = "Location",
    term = "Term",
}

local function _getFFIUtil()
    if _G.XRAY_DISABLE_ENTITY_SUBPROCESS then return nil end
    local ok, ffiutil = pcall(require, "ffi/util")
    if not ok or type(ffiutil) ~= "table" then return nil end
    if type(ffiutil.runInSubProcess) ~= "function"
        or type(ffiutil.isSubProcessDone) ~= "function"
        or type(ffiutil.terminateSubProcess) ~= "function"
        or type(ffiutil.readAllFromFD) ~= "function"
        or type(ffiutil.writeToFD) ~= "function" then
        return nil
    end
    return ffiutil
end
M._getFFIUtil = _getFFIUtil

local function _getCurrentPage(plugin)
    if plugin and plugin.last_pageno then return plugin.last_pageno end
    return xray_utils:getCurrentPage(plugin) or 1
end

-- SRELL ECMAScript regex escaping: escape only ^ $ . * + ? ( ) [ ] { } | \
-- Explicitly do NOT escape '-' or '%' because SRELL returns error_escape (102).
local function escape_pattern(s)
    local esc = s:gsub("([%^%$%.%*%+%?%(%)%[%]%{%}|\\])", "\\%1")
    esc = esc:gsub("%s+", "\\s+")
    return esc
end

local function _normalize(s)
    return (s or ""):gsub("\194\160", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

local function _parseXPointerOffset(xp)
    if not xp then return nil, nil end
    local node_path, off_str = xp:match("^(.*)%.([0-9]+)$")
    if node_path and off_str then
        return node_path, tonumber(off_str)
    end
    return xp, 0
end

local function _deduplicateEntityHits(hits)
    if not hits or #hits == 0 then return {} end

    -- 1. Deduplicate by exact end_xp and start_xp, keeping the longest match
    local by_end = {}
    for _, hit in ipairs(hits) do
        local key = hit.end_xp or ""
        if not by_end[key] or #hit.matched_text > #by_end[key].matched_text then
            by_end[key] = hit
        end
    end

    local by_start = {}
    for _, hit in pairs(by_end) do
        local key = hit.start_xp or ""
        if not by_start[key] or #hit.matched_text > #by_start[key].matched_text then
            by_start[key] = hit
        end
    end

    -- 2. Group by text node and deduplicate overlapping character intervals [start_offset, end_offset)
    local by_node = {}
    local non_node_hits = {}
    for _, hit in pairs(by_start) do
        local start_node, start_off = _parseXPointerOffset(hit.start_xp)
        local end_node, end_off = _parseXPointerOffset(hit.end_xp)
        if start_node and end_node and start_node == end_node and start_off and end_off then
            hit._start_off = math.min(start_off, end_off)
            hit._end_off = math.max(start_off, end_off)
            by_node[start_node] = by_node[start_node] or {}
            table.insert(by_node[start_node], hit)
        else
            table.insert(non_node_hits, hit)
        end
    end

    local final_hits = {}
    for _, node_hits in pairs(by_node) do
        -- Sort primarily by length descending so longer phrases win over sub-tokens
        table.sort(node_hits, function(a, b)
            local len_a = #a.matched_text
            local len_b = #b.matched_text
            if len_a ~= len_b then return len_a > len_b end
            return (a._start_off or 0) < (b._start_off or 0)
        end)

        local accepted_intervals = {}
        for _, hit in ipairs(node_hits) do
            local s0, s1 = hit._start_off, hit._end_off
            local overlaps = false
            for _, intv in ipairs(accepted_intervals) do
                -- Overlap condition for half-open intervals [s0, s1) and [intv[1], intv[2])
                if not (s1 <= intv[1] or s0 >= intv[2]) then
                    overlaps = true
                    break
                end
            end
            if not overlaps then
                table.insert(accepted_intervals, { s0, s1 })
                hit._start_off = nil
                hit._end_off = nil
                table.insert(final_hits, hit)
            end
        end
    end

    for _, hit in ipairs(non_node_hits) do
        hit._start_off = nil
        hit._end_off = nil
        table.insert(final_hits, hit)
    end

    table.sort(final_hits, function(a, b)
        if a.page and b.page and a.page ~= b.page then
            return a.page < b.page
        end
        return (a.start_xp or "") < (b.start_xp or "")
    end)

    return final_hits
end

local PERSON_HONORIFICS = {
    mr = true, mrs = true, ms = true, miss = true, master = true, dr = true,
    sir = true, lady = true, lord = true, dame = true, captain = true, capt = true,
    general = true, colonel = true, col = true, major = true, father = true,
    mother = true, brother = true, sister = true, uncle = true, aunt = true,
    cousin = true, king = true, queen = true, prince = true, princess = true,
    professor = true, prof = true, reverend = true, rev = true, saint = true, st = true,
}

local PERSON_STOP_WORDS = {
    ["the"] = true, ["of"] = true, ["and"] = true, ["in"] = true, ["at"] = true,
    ["to"] = true, ["for"] = true, ["from"] = true, ["with"] = true, ["by"] = true,
    ["on"] = true, ["old"] = true, ["young"] = true, ["little"] = true, ["great"] = true,
    ["first"] = true, ["second"] = true, ["third"] = true, ["ghost"] = true,
    ["spirit"] = true, ["man"] = true, ["woman"] = true, ["boy"] = true,
    ["girl"] = true, ["child"] = true, ["yet"] = true, ["come"] = true,
    ["present"] = true, ["past"] = true, ["future"] = true,
}

local function _stripPossessive(token)
    if not token then return "" end
    return token:gsub("['’][sS]$", ""):gsub("^%p+", ""):gsub("%p+$", "")
end

local function _derivePersonSubNames(phrase)
    if type(phrase) ~= "string" or phrase == "" then return {} end
    local clean = _normalize(phrase)
    local raw_tokens = {}
    for word in clean:gmatch("%S+") do
        local stripped = _stripPossessive(word)
        if stripped ~= "" then
            table.insert(raw_tokens, stripped)
        end
    end

    local n = #raw_tokens
    if n < 2 then return {} end

    -- Check if name has connecting conjunctions/prepositions like "of", "the", "and"
    for _, tok in ipairs(raw_tokens) do
        local low = tok:lower()
        if low == "of" or low == "the" or low == "and" or low == "van" or low == "von" or low == "de" or low == "da" then
            return {}
        end
    end

    local derived = {}
    local seen = {}
    local function addCandidate(candidate)
        if not candidate or #candidate < MIN_TERM_LEN then return end
        local low = candidate:lower()
        if PERSON_HONORIFICS[low] or PERSON_STOP_WORDS[low] then return end
        if not seen[low] then
            seen[low] = true
            table.insert(derived, candidate)
        end
    end

    local first_low = raw_tokens[1]:lower()
    local has_honorific = PERSON_HONORIFICS[first_low] == true

    if has_honorific and n >= 3 then
        -- e.g. "Master Peter Cratchit" -> "<Title> <FirstName>" ("Master Peter")
        addCandidate(raw_tokens[1] .. " " .. raw_tokens[2])
        -- Core name stripped of honorific: e.g. "Peter", "Cratchit"
        addCandidate(raw_tokens[2])
        addCandidate(raw_tokens[n])
    elseif not has_honorific then
        -- Given name and surname (e.g. "Martha Cratchit" -> "Martha", "Cratchit")
        addCandidate(raw_tokens[1])
        addCandidate(raw_tokens[n])
    end

    return derived
end

local function _collectEntityTerms(self, settings)
    local groups = {
        { list = self.characters, category = "character", enabled = settings.entity_cat_characters ~= false, is_person = true },
        { list = self.historical_figures, category = "historical_figure", enabled = settings.entity_cat_historical_figures ~= false, is_person = true },
        { list = self.locations, category = "location", enabled = settings.entity_cat_locations ~= false, is_person = false },
        { list = self.terms, category = "term", enabled = settings.entity_cat_terms ~= false, is_person = false },
    }

    local lookup = {}
    local terms = {}
    local seen_terms = {}

    local function add_term(t)
        if t and #t >= MIN_TERM_LEN and not seen_terms[t] then
            seen_terms[t] = true
            table.insert(terms, t)
        end
    end

    local function register_term_variants(clean, info)
        local lower = clean:lower()
        if not lookup[lower] then
            lookup[lower] = info
        end
        add_term(clean)
        local upper = clean:upper()
        if upper ~= clean then
            add_term(upper)
        end
        local title = clean:gsub("(%a)([%w_']*)", function(first, rest)
            return first:upper() .. rest
        end)
        if title ~= clean and title ~= upper then
            add_term(title)
        end
    end

    -- Pass 1: Register explicit full names first, then unambiguous aliases
    local explicit_registered = {}
    local person_entities = {}
    local explicit_alias_claims = {} -- lower_alias -> list of { entity, category, clean }

    local function isGenericPersonSingleWord(clean_phrase)
        if clean_phrase:find("%s") then return false end
        local low = _stripPossessive(clean_phrase):lower()
        return low == "" or PERSON_HONORIFICS[low] == true or PERSON_STOP_WORDS[low] == true
    end

    for _, group in ipairs(groups) do
        if group.enabled and group.list then
            for _, entity in ipairs(group.list) do
                local names = {}
                if entity.name and entity.name ~= "" then
                    table.insert(names, entity.name)
                    local clean = _normalize(entity.name)
                    if #clean >= MIN_TERM_LEN then
                        local lower = clean:lower()
                        explicit_registered[lower] = true
                        register_term_variants(clean, { entity = entity, category = group.category, canonical = entity.name })
                    end
                end
                if entity.aliases and type(entity.aliases) == "table" then
                    for _, alias in ipairs(entity.aliases) do
                        if type(alias) == "string" and alias ~= "" then
                            table.insert(names, alias)
                            local clean = _normalize(alias)
                            if #clean >= MIN_TERM_LEN then
                                local lower = clean:lower()
                                if group.is_person and isGenericPersonSingleWord(clean) then
                                    -- Skip generic single-word stopword/honorific aliases (e.g. "Spirit", "Ghost")
                                elseif not explicit_registered[lower] then
                                    if group.is_person and not clean:find("%s") then
                                        explicit_alias_claims[lower] = explicit_alias_claims[lower] or {}
                                        table.insert(explicit_alias_claims[lower], {
                                            entity = entity,
                                            category = group.category,
                                            clean = clean,
                                        })
                                    else
                                        explicit_registered[lower] = true
                                        register_term_variants(clean, { entity = entity, category = group.category, canonical = entity.name })
                                    end
                                end
                            end
                        end
                    end
                end
                if group.is_person then
                    table.insert(person_entities, { entity = entity, category = group.category, names = names })
                end
            end
        end
    end

    for lower, claims in pairs(explicit_alias_claims) do
        if #claims == 1 and not explicit_registered[lower] then
            local c = claims[1]
            explicit_registered[lower] = true
            register_term_variants(c.clean, { entity = c.entity, category = c.category, canonical = c.entity.name })
        end
    end

    -- Pass 2: Derive unambiguous sub-names for characters and historical figures
    -- Candidate sub-names (e.g. "Martha", "Peter", "Master Peter") are only registered
    -- if they map uniquely to exactly one entity across the book.
    local candidate_claims = {} -- lower_candidate -> list of { entity, category, candidate }
    for _, pinfo in ipairs(person_entities) do
        local entity_candidates = {}
        local seen_cand = {}
        for _, n in ipairs(pinfo.names) do
            local sub_names = _derivePersonSubNames(n)
            for _, cand in ipairs(sub_names) do
                local cand_low = cand:lower()
                if not explicit_registered[cand_low] and not seen_cand[cand_low] then
                    seen_cand[cand_low] = true
                    table.insert(entity_candidates, cand)
                end
            end
        end
        for _, cand in ipairs(entity_candidates) do
            local cand_low = cand:lower()
            candidate_claims[cand_low] = candidate_claims[cand_low] or {}
            table.insert(candidate_claims[cand_low], {
                entity = pinfo.entity,
                category = pinfo.category,
                candidate = cand,
            })
        end
    end

    for cand_low, claims in pairs(candidate_claims) do
        if #claims == 1 and not explicit_registered[cand_low] then
            local claim = claims[1]
            register_term_variants(claim.candidate, {
                entity = claim.entity,
                category = claim.category,
                canonical = claim.entity.name,
                is_derived = true,
            })
        end
    end

    return terms, lookup
end

local function _buildChunks(terms)
    table.sort(terms, function(a, b) return #a > #b end)

    local boundary_both = {}
    local boundary_none = {}
    for _, t in ipairs(terms) do
        local esc = escape_pattern(t)
        if t:match("^[%w]") and t:match("[%w]$") then
            table.insert(boundary_both, esc)
        else
            table.insert(boundary_none, esc)
        end
    end

    local function chunk_list(list, wrap_both)
        local chunks = {}
        local current = {}
        local current_len = 0
        for _, esc in ipairs(list) do
            if current_len + #esc + 1 > MAX_REGEX_LEN and #current > 0 then
                table.insert(chunks, current)
                current = {}
                current_len = 0
            end
            table.insert(current, esc)
            current_len = current_len + #esc + 1
        end
        if #current > 0 then table.insert(chunks, current) end

        local patterns = {}
        for _, c in ipairs(chunks) do
            local body = table.concat(c, "|")
            table.insert(patterns, wrap_both and ("\\b(" .. body .. ")\\b") or ("(" .. body .. ")"))
        end
        return patterns
    end

    local patterns = {}
    for _, p in ipairs(chunk_list(boundary_both, true)) do table.insert(patterns, p) end
    for _, p in ipairs(chunk_list(boundary_none, false)) do table.insert(patterns, p) end
    return patterns
end

M._collectEntityTerms = _collectEntityTerms
M._buildChunks = _buildChunks
M._deduplicateEntityHits = _deduplicateEntityHits

-- ===== Cache Management =====

function M:_getEntityCachePath(resolved_dir)
    if resolved_dir then
        return resolved_dir .. "/xray_entity_cache.cache"
    end
    if not self.ui or not self.ui.document or not self.ui.document.file then return nil end
    local sidecar = DocSettings:getSidecarDir(self.ui.document.file)
    if not sidecar then return nil end
    return sidecar .. "/xray_entity_cache.cache"
end

local function _getEntitySettingsSignature(self, settings)
    local function sig_list(list)
        local parts = {}
        if list then
            for _, e in ipairs(list) do
                local name = e.name or ""
                local alias_str = ""
                if e.aliases and type(e.aliases) == "table" then
                    local al = {}
                    for _, a in ipairs(e.aliases) do
                        if type(a) == "string" and a ~= "" then
                            table.insert(al, a)
                        end
                    end
                    table.sort(al)
                    alias_str = ":" .. table.concat(al, ";")
                end
                table.insert(parts, name .. alias_str)
            end
        end
        return table.concat(parts, ",")
    end

    local cat_c = settings.entity_cat_characters ~= false
    local cat_h = settings.entity_cat_historical_figures ~= false
    local cat_l = settings.entity_cat_locations ~= false
    local cat_t = settings.entity_cat_terms ~= false

    return table.concat({
        "v5",
        tostring(cat_c), tostring(cat_h), tostring(cat_l), tostring(cat_t),
        sig_list(self.characters), sig_list(self.historical_figures),
        sig_list(self.locations), sig_list(self.terms),
    }, "|")
end

function M:saveEntityCache(resolved_dir, matches, suffix, signature)
    local cache_file = self:_getEntityCachePath(resolved_dir)
    if not cache_file then return false end

    local settings = self.ai_helper and self.ai_helper.settings or {}
    signature = signature or _getEntitySettingsSignature(self, settings)

    local dir = cache_file:match("^(.+)/[^/]+$")
    if dir then
        local ok_util, util = pcall(require, "util")
        if ok_util and util and util.makePath then
            pcall(util.makePath, dir)
        else
            local ok_lfs, lfs = pcall(require, "libs/libkoreader-lfs")
            if not ok_lfs or not lfs then ok_lfs, lfs = pcall(require, "lfs") end
            if ok_lfs and lfs and lfs.attributes and lfs.attributes(dir, "mode") ~= "directory" then
                pcall(lfs.mkdir, dir)
            end
        end
    end

    local tmp_file = cache_file .. ".tmp." .. tostring(suffix or os.time())
    local ok, err = pcall(function()
        local f, open_err = io.open(tmp_file, "w")
        if not f then
            log("saveEntityCache: failed to open temp file: " .. tostring(open_err))
            return false
        end
        f:write(signature .. "\n")
        for _, m in ipairs(matches or {}) do
            local matched_clean = (m.matched_text or ""):gsub("[\r\n\t]", " ")
            local name_clean = (m.entity_name or ""):gsub("[\r\n\t]", " ")
            local cat_clean = (m.category or ""):gsub("[\r\n\t]", " ")
            local page_str = tostring(m.page or "")
            f:write(string.format("%s\t%s\t%s\t%s\t%s\t%s\n",
                tostring(m.start_xp or ""),
                tostring(m.end_xp or ""),
                matched_clean,
                cat_clean,
                name_clean,
                page_str))
        end
        f:close()

        local renamed, ren_err = os.rename(tmp_file, cache_file)
        if not renamed then
            -- Fallback remove + rename
            pcall(os.remove, cache_file)
            renamed, ren_err = os.rename(tmp_file, cache_file)
        end
        if not renamed then
            log("saveEntityCache: rename failed: " .. tostring(ren_err))
            pcall(os.remove, tmp_file)
            return false
        end
        return true
    end)
    return ok and err == true
end

function M:loadEntityCache(resolved_dir, expected_sig)
    local cache_file = self:_getEntityCachePath(resolved_dir)
    if not cache_file then return false end

    local f = io.open(cache_file, "r")
    if not f then return false end

    local signature = f:read("*l")
    if not signature then
        f:close()
        return false
    end
    signature = signature:gsub("%s+$", "")

    local settings = self.ai_helper and self.ai_helper.settings or {}
    expected_sig = expected_sig or _getEntitySettingsSignature(self, settings)
    if signature ~= expected_sig then
        f:close()
        log("loadEntityCache: signature mismatch, cache invalidated")
        return false
    end

    local matches = {}
    local by_page = {}
    local doc = self.ui and self.ui.document

    for line in f:lines() do
        line = line:gsub("\r", "")
        local start_xp, end_xp, matched_text, category, entity_name, page_str =
            line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t?([^\t\r\n]*)$")
        if start_xp and start_xp ~= "" then
            local pg = tonumber(page_str)
            if not pg and doc and doc.getPageFromXPointer then
                local ok_p, computed_pg = pcall(doc.getPageFromXPointer, doc, start_xp)
                if ok_p and computed_pg then pg = computed_pg end
            end
            local match_item = {
                start_xp = start_xp,
                end_xp = end_xp,
                matched_text = matched_text,
                category = category,
                entity_name = entity_name,
                page = pg,
            }
            table.insert(matches, match_item)
            if pg then
                by_page[pg] = by_page[pg] or {}
                table.insert(by_page[pg], match_item)
            end
        end
    end
    f:close()

    self.entity_xp_matches = matches
    self.entity_matches_by_page = by_page
    self._entity_bucket_page_count = doc and doc.getPageCount and doc:getPageCount()
    self._entity_bucket_render_hash = doc and doc.getDocumentRenderingHash and doc:getDocumentRenderingHash(true)
    self._entity_box_cache_sig = nil
    log("loadEntityCache: loaded " .. tostring(#matches) .. " matches from cache")
    if self.ui and self.ui.view then
        if self.ui.view.dialog then
            UIManager:setDirty(self.ui.view.dialog, "ui")
        end
        UIManager:setDirty(nil, "ui")
    end
    return true
end

function M:_rebuildEntityPageBuckets()
    local doc = self.ui and self.ui.document
    if not doc or not self.entity_xp_matches then return end
    local by_page = {}
    for _, hit in ipairs(self.entity_xp_matches) do
        if doc.getPageFromXPointer then
            local ok, pg = pcall(doc.getPageFromXPointer, doc, hit.start_xp)
            if ok and pg then hit.page = pg end
        end
        if hit.page then
            by_page[hit.page] = by_page[hit.page] or {}
            table.insert(by_page[hit.page], hit)
        end
    end
    self.entity_matches_by_page = by_page
    self._entity_bucket_page_count = doc.getPageCount and doc:getPageCount()
    self._entity_bucket_render_hash = doc.getDocumentRenderingHash and doc:getDocumentRenderingHash(true)
    self._entity_box_cache_sig = nil
end

-- ===== Pure Computation (Child-Safe) =====

function M:_computeEntityMatches(settings, opts)
    opts = opts or {}
    if self.destroyed or not self.ui or not self.ui.document then return {} end
    log("scanBookForEntities: starting whole book entity scan")

    local terms, lookup = _collectEntityTerms(self, settings)
    if #terms == 0 then
        log("scanBookForEntities: no terms to scan")
        return {}
    end

    local patterns = _buildChunks(terms)
    local total_patterns = math.max(1, #patterns)
    local hits = {}
    local doc = self.ui.document

    for idx, pattern in ipairs(patterns) do
        if opts.yield_fn then opts.yield_fn() end
        if opts.on_progress then
            opts.on_progress(math.floor(((idx - 1) / total_patterns) * 100))
        end

        local ok, chunk_hits = pcall(function()
            -- CreDocument:findAllText(pattern, case_insensitive, nb_context_words, max_hits, regex)
            return doc:findAllText(pattern, false, 0, 50000, true)
        end)

        if not ok then
            log("scanBookForEntities: findAllText failed: " .. tostring(chunk_hits))
        elseif chunk_hits and type(chunk_hits) == "table" then
            log(string.format("scanBookForEntities: chunk %d/%d returned %d raw hits", idx, total_patterns, #chunk_hits))
            for _, hit in ipairs(chunk_hits) do
                local start_xp = hit.start or hit.start0
                local end_xp = hit["end"]
                local raw_text = hit.matched_text or hit.text
                if start_xp and end_xp and raw_text then
                    local matched_text = _normalize(raw_text)
                    local info = lookup[matched_text:lower()]
                    if info then
                        table.insert(hits, {
                            start_xp = start_xp,
                            end_xp = end_xp,
                            matched_text = matched_text,
                            category = info.category,
                            entity_name = info.canonical or matched_text,
                        })
                    end
                end
            end
        end
    end

    -- Deduplicate overlapping hits by end/start and interval overlap, keeping longest match
    local deduped_hits = _deduplicateEntityHits(hits)

    local final_matches = {}
    for _, hit in ipairs(deduped_hits) do
        -- Pre-compute page number in child process so UI thread never needs to compute it
        local page = nil
        if doc.getPageFromXPointer then
            local ok_p, pg = pcall(doc.getPageFromXPointer, doc, hit.start_xp)
            if ok_p and pg then page = pg end
        end
        hit.page = page
        table.insert(final_matches, hit)
    end

    if opts.on_progress then opts.on_progress(100) end
    log("scanBookForEntities: finished scan, found " .. tostring(#final_matches) .. " unique matches")
    return final_matches
end

-- ===== Subprocess & Async Management =====

function M:_cancelEntityScanChild(reason)
    if self._entity_scan_pid then
        local ffiutil = _getFFIUtil()
        if ffiutil and ffiutil.terminateSubProcess then
            pcall(ffiutil.terminateSubProcess, self._entity_scan_pid)
        end
        self._entity_scan_pid = nil
    end
    self._entity_scan_read_fd = nil
    self._entity_scan_started_at = nil
    self._entity_scan_in_progress = nil
    self._entity_scan_poll_fn = nil
    pcall(function() require("device"):enableCPUCores(1) end)
    if self.active_entity_scan_dialog then
        pcall(function() self.active_entity_scan_dialog:close() end)
        self.active_entity_scan_dialog = nil
    end
    log("Subprocess cancelled: " .. tostring(reason))
end

function M:_onEntityScanFinished(resolved_dir, ok, manual)
    self._entity_scan_in_progress = nil
    self._entity_scan_pid = nil
    self._entity_scan_read_fd = nil
    self._entity_scan_poll_fn = nil

    if self.active_entity_scan_dialog then
        pcall(function() self.active_entity_scan_dialog:close() end)
        self.active_entity_scan_dialog = nil
    end

    local loaded = false
    if ok then
        loaded = self:loadEntityCache(resolved_dir)
        if loaded then
            log("Entity scan finished successfully")
            if manual then
                local Notification = require("ui/widget/notification")
                local count = self.entity_xp_matches and #self.entity_xp_matches or 0
                UIManager:show(Notification:new{
                    text = string.format("X-Ray: Found %d entity underline(s).", count),
                    timeout = 3
                })
            end
        end
    end

    if not loaded then
        log("Entity scan failed or was cancelled")
        if not self._entity_scan_fallback_used and not self.destroyed and self.ui and self.ui.document then
            self._entity_scan_fallback_used = true
            log("Entity scan: attempting in-process fallback scan")
            local settings = self.ai_helper and self.ai_helper.settings or {}
            self:_runEntityScanInProcess(resolved_dir, settings, manual)
            return
        end
    end

    if self.ui and self.ui.view and self.ui.view.dialog then
        UIManager:setDirty(self.ui.view.dialog, "ui")
    end
    UIManager:setDirty(nil, "ui")
end

function M:_startEntityScanSubprocess(resolved_dir, settings, manual)
    local ffiutil = _getFFIUtil()
    if not ffiutil then return false end
    pcall(function() XRayLogger:flush() end)

    local plugin = self
    local pid, read_fd = ffiutil.runInSubProcess(function(_child_pid, write_fd)
        XRayLogger._buf, XRayLogger._buf_count = {}, 0
        local result = "err"
        local ok, err = pcall(function()
            local matches = plugin:_computeEntityMatches(settings, {
                on_progress = function(pct)
                    if write_fd then
                        ffiutil.writeToFD(write_fd, string.format("p:%d\n", math.floor(pct or 0)))
                    end
                end,
            })
            local saved = plugin:saveEntityCache(resolved_dir, matches, "child_" .. tostring(_child_pid))
            if saved then
                result = "ok:" .. tostring(#matches) .. "\n"
            end
        end)
        if not ok then
            log("child scan error: " .. tostring(err))
        end
        pcall(function() XRayLogger:flush() end)
        if write_fd then
            ffiutil.writeToFD(write_fd, result, true)
        end
    end, true)

    if not pid then
        log("runInSubProcess failed: " .. tostring(read_fd))
        return false
    end

    self._entity_scan_pid = pid
    self._entity_scan_read_fd = read_fd
    self._entity_scan_started_at = os.time()
    pcall(function() require("device"):enableCPUCores(2) end)

    local progress_buf = ""
    local function poll()
        self._entity_scan_poll_fn = nil
        if self.destroyed or not self.ui or not self.ui.document then
            self:_cancelEntityScanChild("document closed")
            return
        end
        if os.time() - self._entity_scan_started_at > ENTITY_SCAN_TIMEOUT then
            self:_cancelEntityScanChild("timeout")
            return
        end

        if read_fd and ffiutil.getNonBlockingReadSize and ffiutil.getNonBlockingReadSize(read_fd) > 0 then
            local chunk = ffiutil.readFromFD and ffiutil.readFromFD(read_fd, 512)
            if chunk and chunk ~= "" then
                progress_buf = progress_buf .. chunk
                for p_str in progress_buf:gmatch("p:(%d+)\n") do
                    local pct = tonumber(p_str)
                    if pct and self.active_entity_scan_dialog and self.active_entity_scan_dialog.reportProgress then
                        self.active_entity_scan_dialog:reportProgress(pct)
                    end
                end
            end
        end

        local ok_done, done = pcall(ffiutil.isSubProcessDone, pid)
        if ok_done and not done then
            self._entity_scan_poll_fn = poll
            UIManager:scheduleIn(ENTITY_SCAN_POLL_INTERVAL, poll)
            return
        end

        local out = progress_buf
        if read_fd then
            local ok_r, s = pcall(ffiutil.readAllFromFD, read_fd)
            if ok_r and type(s) == "string" then out = out .. s end
        end
        self._entity_scan_pid, self._entity_scan_read_fd = nil, nil
        pcall(function() require("device"):enableCPUCores(1) end)

        local success = out:find("ok:") ~= nil
        self:_onEntityScanFinished(resolved_dir, success, manual)
    end

    self._entity_scan_poll_fn = poll
    UIManager:scheduleIn(ENTITY_SCAN_POLL_INTERVAL, poll)
    return true
end

function M:_runEntityScanInProcess(resolved_dir, settings, manual)
    local co
    local last_yield = os.clock()
    local function yield_fn()
        if os.clock() - last_yield > ENTITY_SCAN_SLICE then
            coroutine.yield()
            last_yield = os.clock()
        end
    end

    local function step()
        if self.destroyed or not self.ui or not self.ui.document then
            self._entity_scan_in_progress = nil
            if self.active_entity_scan_dialog then
                pcall(function() self.active_entity_scan_dialog:close() end)
                self.active_entity_scan_dialog = nil
            end
            return
        end
        local ok, res = coroutine.resume(co)
        if not ok then
            log("In-process scan error: " .. tostring(res))
            self:_onEntityScanFinished(resolved_dir, false, manual)
        elseif coroutine.status(co) == "suspended" then
            UIManager:scheduleIn(0, step)
        else
            local matches = res or {}
            self:saveEntityCache(resolved_dir, matches, "inproc")
            self:_onEntityScanFinished(resolved_dir, true, manual)
        end
    end

    co = coroutine.create(function()
        return self:_computeEntityMatches(settings, {
            yield_fn = yield_fn,
            on_progress = function(pct)
                if self.active_entity_scan_dialog and self.active_entity_scan_dialog.reportProgress then
                    self.active_entity_scan_dialog:reportProgress(pct)
                end
            end
        })
    end)

    UIManager:scheduleIn(0, step)
end

function M:scanBookForEntities(force)
    if self.destroyed or not self.ui or not self.ui.document then return end

    local settings = self.ai_helper and self.ai_helper.settings or {}
    if settings.entity_footnotes_enabled ~= true then
        self:clearEntityUnderlines()
        return
    end

    local terms, _ = _collectEntityTerms(self, settings)
    if #terms == 0 then
        log("scanBookForEntities: no terms to scan, clearing entity matches")
        self.entity_xp_matches = {}
        self.entity_matches_by_page = {}
        self._entity_box_cache_sig = nil
        return
    end

    self._entity_scan_attempted = true

    if self._entity_scan_in_progress then
        log("scanBookForEntities: scan already in progress")
        return
    end

    -- Process coordination: defer if unit scanner child or AI helper child is active
    if (self._unit_scan_pid and self._unit_scan_pid > 0) or
       (self.ai_helper and self.ai_helper._async_child_pid and self.ai_helper._async_child_pid > 0) then
        log("scanBookForEntities: child process active, deferring scan")
        UIManager:scheduleIn(5, function()
            if not self.destroyed and not self._entity_scan_in_progress then
                self:scanBookForEntities(force)
            end
        end)
        return
    end

    local sidecar = DocSettings:getSidecarDir(self.ui.document.file)
    if not sidecar then return end

    local expected_sig = _getEntitySettingsSignature(self, settings)
    if not force then
        local cache_loaded = self:loadEntityCache(sidecar, expected_sig)
        if cache_loaded then
            log("scanBookForEntities: cache is up-to-date, skipping scan")
            return
        end
    end

    -- Memory safety guard on Kindle hardware (device-aware threshold via xray_utils)
    if xray_utils.isLowMemory and xray_utils:isLowMemory() and not force then
        log("scanBookForEntities: low memory condition detected, skipping auto scan")
        return
    end

    local manual = force and true or false
    self._entity_scan_in_progress = true

    if manual then
        local progress_msg = ProgressBarDialog:new{
            title = self.loc:t("entity_scanning_title") or "X-Ray: Entity Underlining",
            text = self.loc:t("entity_scanning_book") or "Scanning book for underlines...",
            dismissable = true,
            onDismiss = function()
                self:_cancelEntityScanChild("user dismissed")
            end
        }
        self.active_entity_scan_dialog = progress_msg
        progress_msg:show()
        UIManager:forceRePaint()
    end

    if self:_startEntityScanSubprocess(sidecar, settings, manual) then
        return
    end

    if _getFFIUtil() and not manual then
        -- Fork failed at runtime on auto scan: skip silently without blocking UI
        log("scanBookForEntities: subprocess fork failed, deferring auto scan")
        self._entity_scan_in_progress = nil
        return
    end

    self:_runEntityScanInProcess(sidecar, settings, manual)
end

-- ===== Box Resolution & Dynamic Visibility =====

local function _getEntityCacheSig(self)
    local doc = self.ui and self.ui.document
    if not doc then return "" end
    local page = _getCurrentPage(self)
    local pos = ""
    if doc.getCurrentPos then
        pcall(function() pos = doc:getCurrentPos() end)
    end
    local hash = ""
    if doc.getDocumentRenderingHash then
        pcall(function() hash = doc:getDocumentRenderingHash() end)
    end
    local sw = Screen:getWidth()
    local sh = Screen:getHeight()
    return table.concat({ tostring(page), tostring(pos), tostring(hash), tostring(sw), tostring(sh) }, "|")
end

function M:_isEntityAllowedByVisibility(entity, category, matched_text)
    if not entity then return false end
    -- 1. Check if category is enabled in settings
    local settings = self.ai_helper and self.ai_helper.settings or {}
    if category == "character" and settings.entity_cat_characters == false then return false end
    if category == "historical_figure" and settings.entity_cat_historical_figures == false then return false end
    if category == "location" and settings.entity_cat_locations == false then return false end
    if category == "term" and settings.entity_cat_terms == false then return false end

    -- 2. Progressive Spoiler & Horizon Gate
    local spoiler_setting = settings.spoiler_setting or "spoiler_free"
    if spoiler_setting ~= "full_book" then
        if self.isEntityVisibleAtCurrentPosition and not self:isEntityVisibleAtCurrentPosition(entity) then
            return false
        end
        if matched_text and self.getUnlockedAliases and entity.alias_visible_from and next(entity.alias_visible_from) then
            local n_match = matched_text:lower()
            if entity.alias_visible_from[n_match] then
                local unlocked_aliases = self:getUnlockedAliases(entity)
                local is_alias_unlocked = false
                for _, a in ipairs(unlocked_aliases) do
                    if a:lower() == n_match then
                        is_alias_unlocked = true
                        break
                    end
                end
                if not is_alias_unlocked then
                    return false
                end
            end
        end
    end

    -- 3. Anthology Mode Scoping
    if self.isAnthologyMode and self:isAnthologyMode() then
        if self.isEntityInCurrentStory and not self:isEntityInCurrentStory(entity) then
            return false
        end
    end

    return true
end

function M:_resolveEntityHighlightBoxes()
    if self.destroyed or not self.ui or not self.ui.document then
        self.entity_boxes = {}
        return
    end

    local sig = _getEntityCacheSig(self)
    if self._entity_box_cache_sig == sig and self.entity_boxes then
        return
    end

    self._entity_box_cache_sig = sig
    local doc = self.ui.document
    if not self.entity_xp_matches or #self.entity_xp_matches == 0 then
        self.entity_boxes = {}
        return
    end

    local page_count = doc.getPageCount and doc:getPageCount()
    local render_hash = doc.getDocumentRenderingHash and doc:getDocumentRenderingHash(true)
    if (self._entity_bucket_page_count and page_count and self._entity_bucket_page_count ~= page_count)
        or (self._entity_bucket_render_hash and render_hash and self._entity_bucket_render_hash ~= render_hash) then
        self:_rebuildEntityPageBuckets()
    end

    local settings = self.ai_helper and self.ai_helper.settings or {}
    local current_page = _getCurrentPage(self)

    -- Page window: resolve only matches near current page
    local matches_to_resolve = self.entity_xp_matches
    if self.entity_matches_by_page and next(self.entity_matches_by_page) then
        matches_to_resolve = {}
        for _, pg in ipairs({ current_page - 1, current_page, current_page + 1 }) do
            local bucket = self.entity_matches_by_page[pg]
            if bucket then
                for _, m in ipairs(bucket) do
                    table.insert(matches_to_resolve, m)
                end
            end
        end
    end

    local groups = {}
    for _, match in ipairs(matches_to_resolve) do
        local entity = self:_findEntityByNameAndCategory(match.entity_name, match.category)
        if entity and self:_isEntityAllowedByVisibility(entity, match.category, match.matched_text) then
            local ok, boxes = pcall(doc.getScreenBoxesFromPositions, doc, match.start_xp, match.end_xp, true)
            if ok and boxes and #boxes > 0 then
                local group_boxes = {}
                local top_y, top_x = nil, nil
                for _, box in ipairs(boxes) do
                    table.insert(group_boxes, {
                        x = box.x,
                        y = box.y,
                        w = box.w,
                        h = box.h,
                        matched_text = match.matched_text,
                        category = match.category,
                        entity_name = match.entity_name,
                    })
                    if not top_y or box.y < top_y or (box.y == top_y and box.x < top_x) then
                        top_y, top_x = box.y, box.x
                    end
                end
                table.insert(groups, {
                    key = (match.category or "") .. "|" .. (match.entity_name or ""),
                    sort_y = top_y or 0,
                    sort_x = top_x or 0,
                    boxes = group_boxes,
                })
            end
        end
    end

    -- Sort in reading order (top-to-bottom, then left-to-right)
    table.sort(groups, function(a, b)
        if a.sort_y ~= b.sort_y then return a.sort_y < b.sort_y end
        return a.sort_x < b.sort_x
    end)

    -- Mention mode deduplication
    local mention_mode = settings.entity_mention_mode or "all"
    local seen = {}
    local resolved = {}
    for _, group in ipairs(groups) do
        if mention_mode ~= "first" or not seen[group.key] then
            seen[group.key] = true
            for _, box in ipairs(group.boxes) do
                table.insert(resolved, box)
            end
        end
    end

    self.entity_boxes = resolved
    log(string.format("_resolveEntityHighlightBoxes: page=%s, candidates=%d, resolved_boxes=%d", tostring(current_page), #matches_to_resolve, #resolved))
end

function M:addEntityToUnderlines(entity, category)
    if self.destroyed or not self.ui or not self.ui.document then return end
    if not entity or not entity.name or entity.name == "" then return end

    local settings = self.ai_helper and self.ai_helper.settings or {}
    if settings.entity_footnotes_enabled ~= true then return end

    -- Check if this category is enabled in settings
    local cat_enabled = true
    if category == "character" and settings.entity_cat_characters == false then cat_enabled = false
    elseif category == "historical_figure" and settings.entity_cat_historical_figures == false then cat_enabled = false
    elseif category == "location" and settings.entity_cat_locations == false then cat_enabled = false
    elseif category == "term" and settings.entity_cat_terms == false then cat_enabled = false
    end
    if not cat_enabled then return end

    -- If no matches exist yet, trigger full scan
    if not self.entity_xp_matches then
        if self.scanBookForEntities then
            self:scanBookForEntities()
        end
        return
    end

    local doc = self.ui.document

    -- Collect all name/alias variants for this entity
    local names = { entity.name }
    if entity.aliases and type(entity.aliases) == "table" then
        for _, a in ipairs(entity.aliases) do
            if type(a) == "string" and a ~= "" then
                table.insert(names, a)
            end
        end
    end

    local is_person = (category == "character" or category == "historical_figure")
    if is_person then
        local sub_names = _derivePersonSubNames(entity.name)
        for _, a in ipairs(entity.aliases or {}) do
            for _, sn in ipairs(_derivePersonSubNames(a)) do
                table.insert(sub_names, sn)
            end
        end
        for _, cand in ipairs(sub_names) do
            local cand_low = cand:lower()
            local conflict = false
            local check_lists = { self.characters, self.historical_figures }
            for _, list in ipairs(check_lists) do
                if list then
                    for _, other in ipairs(list) do
                        if other ~= entity then
                            if (other.name and other.name:lower() == cand_low) then
                                conflict = true
                                break
                            end
                            for _, oa in ipairs(other.aliases or {}) do
                                if oa:lower() == cand_low then
                                    conflict = true
                                    break
                                end
                            end
                        end
                    end
                end
                if conflict then break end
            end
            if not conflict then
                table.insert(names, cand)
            end
        end
    end

    local terms = {}
    local seen_terms = {}
    local function add_term(t)
        if t and #t >= MIN_TERM_LEN and not seen_terms[t] then
            seen_terms[t] = true
            table.insert(terms, t)
        end
    end

    for _, n in ipairs(names) do
        local clean = _normalize(n)
        if #clean >= MIN_TERM_LEN then
            add_term(clean)
            local upper = clean:upper()
            if upper ~= clean then
                add_term(upper)
            end
            local title = clean:gsub("(%a)([%w_']*)", function(first, rest)
                return first:upper() .. rest
            end)
            if title ~= clean and title ~= upper then
                add_term(title)
            end
        end
    end

    if #terms == 0 then return end

    local patterns = _buildChunks(terms)
    local new_hits = {}
    for _, pattern in ipairs(patterns) do
        local ok, chunk_hits = pcall(function()
            return doc:findAllText(pattern, false, 0, 50000, true)
        end)
        if ok and chunk_hits and type(chunk_hits) == "table" then
            for _, hit in ipairs(chunk_hits) do
                local start_xp = hit.start or hit.start0
                local end_xp = hit["end"]
                local raw_text = hit.matched_text or hit.text
                if start_xp and end_xp and raw_text then
                    local matched_text = _normalize(raw_text)
                    local page = nil
                    if doc.getPageFromXPointer then
                        local ok_p, pg = pcall(doc.getPageFromXPointer, doc, start_xp)
                        if ok_p and pg then page = pg end
                    end
                    table.insert(new_hits, {
                        start_xp = start_xp,
                        end_xp = end_xp,
                        matched_text = matched_text,
                        category = category,
                        entity_name = entity.name,
                        page = page,
                    })
                end
            end
        end
    end

    if #new_hits == 0 then return end

    local combined = {}
    for _, m in ipairs(self.entity_xp_matches or {}) do
        table.insert(combined, m)
    end
    for _, m in ipairs(new_hits) do
        table.insert(combined, m)
    end
    self.entity_xp_matches = _deduplicateEntityHits(combined)
    self:_rebuildEntityPageBuckets()

    -- Invalidate bounding box cache so current page immediately recalculates
    self._entity_box_cache_sig = nil
    self:_resolveEntityHighlightBoxes()

    -- Save updated cache to disk with updated signature
    local sidecar = DocSettings:getSidecarDir(doc.file)
    if sidecar then
        local expected_sig = _getEntitySettingsSignature(self, settings)
        self:saveEntityCache(sidecar, self.entity_xp_matches, nil, expected_sig)
    end

    -- Refresh view
    if self.ui and self.ui.view then
        if self.ui.view.dialog then
            UIManager:setDirty(self.ui.view.dialog, "ui")
        end
        UIManager:setDirty(nil, "ui")
    end
    log(string.format("addEntityToUnderlines: added matches for '%s'", entity.name))
end

-- ===== Overlay Underline Drawing =====

function M:clearEntityUnderlines()
    self.entity_boxes = nil
    self.entity_xp_matches = nil
    self.entity_matches_by_page = nil
    self._entity_box_cache_sig = nil
    if self.ui and self.ui.view and self.ui.view.view_modules then
        self.ui.view.view_modules["xray_entity_underlines"] = nil
    end
    if self.ui and self.ui.view and self.ui.view.dialog then
        UIManager:setDirty(self.ui.view.dialog, "ui")
    end
end

function M:mountEntityUnderlineOverlay()
    local view = self.ui and self.ui.view
    if not view then return end

    local plugin = self
    if view.registerViewModule then
        view:registerViewModule("xray_entity_underlines", {
            paintTo = function(_this, bb, _x, _y)
                if plugin.destroyed or not plugin.ui or not plugin.ui.document then return end
                local ok, err = pcall(function() plugin:_drawEntityUnderlines(bb) end)
                if not ok then
                    log("Entity draw error: " .. tostring(err))
                end
            end
        })
        log("mountEntityUnderlineOverlay: registered view module xray_entity_underlines")
        return
    end

    if self._entity_paintTo_wrapped then return end
    local orig = view.paintTo
    view.paintTo = function(view_self, bb, x, y)
        orig(view_self, bb, x, y)
        if plugin.destroyed or not plugin.ui or not plugin.ui.document then return end
        local ok, err = pcall(function() plugin:_drawEntityUnderlines(bb) end)
        if not ok then
            log("Entity draw error: " .. tostring(err))
        end
    end
    self._entity_paintTo_wrapped = true
    log("mountEntityUnderlineOverlay: wrapped view.paintTo")
end

function M:_drawEntityUnderlines(bb)
    local settings = self.ai_helper and self.ai_helper.settings or {}
    if settings.entity_footnotes_enabled ~= true then return end

    if not self.entity_xp_matches and not self._entity_scan_in_progress and not self._entity_scan_attempted then
        local sidecar = DocSettings:getSidecarDir(self.ui.document.file)
        if sidecar and not self:loadEntityCache(sidecar) then
            self:scanBookForEntities()
        end
    end

    self:_resolveEntityHighlightBoxes()
    if not self.entity_boxes or #self.entity_boxes == 0 then return end

    local underline_style = settings.entity_underline_style or "wavy"
    if underline_style == "invisible" then return end

    local raw_thickness = tonumber(settings.entity_underline_thickness) or 2
    local thickness = Screen:scaleBySize(raw_thickness)
    local intensity = settings.entity_underline_intensity or "light"

    local grey = 150
    if intensity == "light" then
        grey = 200
    elseif intensity == "dark" then
        grey = 30
    end

    local draw_fn = self._draw_underline or (require(plugin_path .. "xray_unitscanner")._draw_underline)
    if draw_fn then
        for _, box in ipairs(self.entity_boxes) do
            if box.x and box.y and box.w and box.h then
                draw_fn(bb, box, underline_style, grey, thickness, raw_thickness, self.path)
            end
        end
    end
end

-- ===== Tap Handling & Tooltips =====

function M:_findEntityByNameAndCategory(name, category)
    local list
    if category == "character" then list = self.characters
    elseif category == "historical_figure" then list = self.historical_figures
    elseif category == "location" then list = self.locations
    elseif category == "term" then list = self.terms
    end
    if not list then return nil end

    local lower = (name or ""):lower()
    for _, e in ipairs(list) do
        if (e.name or ""):lower() == lower then return e end
        if e.aliases and type(e.aliases) == "table" then
            for _, alias in ipairs(e.aliases) do
                if type(alias) == "string" and alias:lower() == lower then return e end
            end
        end
    end
    return nil
end

local EntityTooltip = InputContainer:extend{
    box = nil,
    entity = nil,
    category = nil,
    title_text = nil,
    description_text = nil,
    plugin = nil,
    timeout = 8,
}

function EntityTooltip:init()
    local sc = function(val) return Screen:scaleBySize(val) end
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    local pad_v = sc(8)
    local pad_h = sc(12)
    local card_w = math.min(sw - sc(30), sc(340))

    local fs = 20
    if G_reader_settings then
        fs = G_reader_settings:readSetting("cre_font_size") or 20
    end
    local title_fs = math.max(14, math.min(fs + 2, 22))
    local body_fs = math.max(12, math.min(fs - 2, 17))
    local cat_fs = math.max(10, math.min(fs - 5, 14))

    local category_label = CATEGORY_LABELS[self.category] or self.category or "Entity"

    local vg = VerticalGroup:new{ align = "left", width = card_w - pad_h * 2 }
    table.insert(vg, TextBoxWidget:new{
        text = self.title_text or "",
        face = Font:getFace("cfont", title_fs),
        bold = true,
        width = card_w - pad_h * 2,
    })
    table.insert(vg, VerticalSpan:new{ width = sc(2) })
    table.insert(vg, TextBoxWidget:new{
        text = category_label:upper(),
        face = Font:getFace("infofont", cat_fs),
        fgcolor = Blitbuffer.Color8(120),
        width = card_w - pad_h * 2,
    })
    table.insert(vg, VerticalSpan:new{ width = sc(6) })
    table.insert(vg, TextBoxWidget:new{
        text = self.description_text or "",
        face = Font:getFace("cfont", body_fs),
        width = card_w - pad_h * 2,
    })

    local card = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = sc(2),
        color = Blitbuffer.COLOR_BLACK,
        radius = sc(4),
        padding_top = pad_v,
        padding_bottom = pad_v,
        padding_left = pad_h,
        padding_right = pad_h,
        width = card_w,
        vg,
    }

    local card_size = card:getSize()
    card_w = card_size.w
    local card_h = math.min(card_size.h, sh - sc(40))

    local margin = sc(10)
    local box = self.box
    local ref_x = box.x + box.w / 2
    local ref_bottom = box.y + box.h
    local ref_top = box.y

    local arrow_w = sc(16)
    local arrow_h = sc(8)
    local border_px = sc(2)

    local popup_x = math.max(0, math.min(sw - card_w, math.floor(ref_x - card_w / 2)))
    local popup_y
    local popup_below_word
    if ref_bottom + margin + card_h <= sh then
        popup_y = ref_bottom + margin
        popup_below_word = true
    else
        popup_y = ref_top - margin - card_h - arrow_h + border_px
        popup_below_word = false
    end

    if popup_below_word then
        popup_y = math.max(arrow_h - border_px, math.min(sh - card_h, popup_y))
    else
        popup_y = math.max(0, math.min(sh - card_h - arrow_h + border_px, popup_y))
    end
    card.overlap_offset = { popup_x, popup_y }

    local apex_min = popup_x + arrow_w / 2 + sc(4)
    local apex_max = popup_x + card_w - arrow_w / 2 - sc(4)
    local apex_x = (apex_min <= apex_max) and math.max(apex_min, math.min(apex_max, ref_x)) or (popup_x + card_w / 2)

    local arrow_x = math.floor(apex_x - arrow_w / 2)
    local arrow_y = popup_below_word and (popup_y - arrow_h + border_px) or (popup_y + card_h - border_px)
    local arrow_dir = popup_below_word and "up" or "down"

    local PointerArrowClass = self.plugin and self.plugin._PointerArrow or (require(plugin_path .. "xray_unitscanner")._PointerArrow)
    local arrow
    if PointerArrowClass then
        arrow = PointerArrowClass:new{
            width = arrow_w,
            height = arrow_h,
            direction = arrow_dir,
            apex_offset = arrow_w / 2,
            border_size = border_px,
            border_color = Blitbuffer.COLOR_DARK_GRAY,
            fill_color = Blitbuffer.COLOR_WHITE,
        }
        arrow.overlap_offset = { arrow_x, arrow_y }
    end

    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    self.ges_events = {
        TapOutside = {
            GestureRange:new{
                ges = "tap",
                range = Geom:new{ x = 0, y = 0, w = sw, h = sh }
            }
        }
    }

    local children = { dimen = Geom:new{ w = sw, h = sh }, card }
    if arrow then table.insert(children, arrow) end
    self[1] = OverlapGroup:new(children)
end

function EntityTooltip:onTapOutside()
    self:dismiss()
    return true
end

function EntityTooltip:onClose()
    self:dismiss()
    return true
end

function EntityTooltip:dismiss()
    if self.timer_handle then
        pcall(function() UIManager:unschedule(self.timer_handle) end)
        self.timer_handle = nil
    end
    if not self._closed then
        self._closed = true
        UIManager:close(self)
    end
end

function EntityTooltip:onShow()
    if self.timeout and self.timeout > 0 then
        local this = self
        self.timer_handle = UIManager:scheduleIn(self.timeout, function()
            if not this._closed then
                this:dismiss()
            end
        end)
    end
    UIManager:setDirty(self, "ui")
    return true
end

-- Non-touch hardware key dismissal (per ui_style_guide.md)
function EntityTooltip:handleEvent(ev)
    if ev.action == "press" then
        local key = ev.key
        if key == "Back" or key == "Escape" or key == "Select" or key == "Return" or key == "Space" then
            self:dismiss()
            return true
        end
    end
    return InputContainer.handleEvent(self, ev)
end

function M:showEntityFootnote(box)
    if not box then return end
    local entity = self:_findEntityByNameAndCategory(box.entity_name, box.category)
    if not entity then return end

    local settings = self.ai_helper and self.ai_helper.settings or {}
    local popup_style = settings.entity_popup_style or "footnote"

    if popup_style == "footnote" then
        if self.lookup_manager and self.lookup_manager.handleLookup then
            self.lookup_manager:handleLookup(box.entity_name)
            return
        end
        if box.category == "character" and self.showCharacterDetails then
            self:showCharacterDetails(entity)
            return
        elseif box.category == "location" and self.showLocationDetails then
            self:showLocationDetails(entity)
            return
        elseif box.category == "term" and self.showTermDetails then
            self:showTermDetails(entity)
            return
        elseif box.category == "historical_figure" and self.showHistoricalFigureDetails then
            self:showHistoricalFigureDetails(entity)
            return
        end
    end

    -- Compact tooltip bubble
    local desc
    if box.category == "term" then
        if self.resolveDescriptionForPage then
            local current_page = _getCurrentPage(self)
            desc = self:resolveDescriptionForPage(entity, current_page)
        end
        if not desc or desc == "" or desc == "---" then
            desc = entity.definition or entity.expanded or entity.description
        end
    else
        if self.resolveDescriptionForPage then
            local current_page = _getCurrentPage(self)
            desc = self:resolveDescriptionForPage(entity, current_page)
        end
        if not desc or desc == "" or desc == "---" then
            local desc_key = (box.category == "historical_figure") and "biography" or "description"
            local first_hist = entity.history and entity.history[1]
            desc = (first_hist and (first_hist[desc_key] or first_hist.description))
                or entity.description or entity.biography
        end
    end
    if not desc or desc == "" or desc == "---" then
        desc = self.loc:t("entity_no_description") or "No description available yet."
    end

    local timeout = tonumber(settings.entity_tooltip_timeout) or 8
    local tooltip = EntityTooltip:new{
        box = box,
        entity = entity,
        category = box.category,
        title_text = entity.name or box.matched_text or "",
        description_text = desc,
        plugin = self,
        timeout = timeout,
    }
    UIManager:show(tooltip)
end

function M:mountEntityTapHandler()
    if self._entityTapHandler_wrapped then return end
    local plugin = self
    local hl = self.ui and self.ui.highlight
    if not hl then return end
    local orig_tap = hl.onTap
    hl.onTap = function(hl_self, _, ges)
        if ges and plugin:_handleEntityTap(ges) then return true end
        if orig_tap then return orig_tap(hl_self, _, ges) end
    end
    self._entityTapHandler_wrapped = true
    log("mountEntityTapHandler: wrapped hl.onTap")
end

function M:_handleEntityTap(ges)
    local settings = self.ai_helper and self.ai_helper.settings or {}
    if settings.entity_footnotes_enabled ~= true then return false end

    if not self.entity_boxes or #self.entity_boxes == 0 then
        return false
    end

    local tx, ty = ges.pos.x, ges.pos.y
    for _, box in ipairs(self.entity_boxes) do
        if tx >= box.x and tx <= box.x + box.w
           and ty >= box.y - 6 and ty <= box.y + box.h + 6 then
            self:showEntityFootnote(box)
            return true
        end
    end
    return false
end

-- Friendly check for legacy patch in patches/
pcall(function()
    local ok_lfs, lfs = pcall(require, "libs/libkoreader-lfs")
    if ok_lfs and lfs and lfs.attributes and lfs.attributes("patches/2-xray-entity-footnotes.lua", "mode") == "file" then
        log("Notice: Legacy 2-xray-entity-footnotes.lua patch detected in patches/. Native Entity Footnotes is active; the patch file can now be safely removed.")
    end
end)

M.EntityTooltip = EntityTooltip
return M
