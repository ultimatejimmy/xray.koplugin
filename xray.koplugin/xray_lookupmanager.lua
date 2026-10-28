-- LookupManager - Core logic for text selection lookups
local logger = require("logger")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local plugin_path = ((...) or ""):match("(.-)[^%.]+$") or ""
local utils = require(plugin_path .. "xray_utils")

-- Minimum score to consider a match "high confidence" and skip the re-lookup prompt.
-- Scores 100 (exact) and 95 (alias exact) are above this; 50/40/30 are below.
local LOW_CONFIDENCE_THRESHOLD = 70

local LookupManager = {}


local function _truncateSafe(text, limit)
    return (utils:getTruncatedText(text, limit))
end

local function _utf8CharLen(s)
    if not s or s == "" then return 0 end
    local _, count = s:gsub("[%z\1-\127\194-\244][\128-\191]*", "")
    return count
end

local function _isWordBreakChar(c)
    if not c or c == "" then return true end
    local b = c:byte(1)
    if b <= 127 then
        return c:match("[%s%p]") ~= nil
    end
    -- Multibyte Unicode punctuation / whitespace
    if c:match("^\194[\160\171\183\187\191\161]") then return true end
    if c:match("^\226\128[\128-\191]") then return true end
    if c:match("^\226\136\146") then return true end
    if c:match("^\227\128[\128-\191]") then return true end
    if c:match("^\239\188[\128-\191]") then return true end
    return false
end

-- Find start of UTF-8 character ending at pos in str
local function _getPrevChar(str, pos)
    if pos < 1 then return nil end
    local b = str:byte(pos)
    if b <= 127 then
        return str:sub(pos, pos)
    end
    -- Multibyte continuation: search back for lead byte
    local start_pos = pos
    while start_pos > 1 and str:byte(start_pos) >= 128 and str:byte(start_pos) <= 191 do
        start_pos = start_pos - 1
    end
    return str:sub(start_pos, pos)
end

local function _isUnsegmentedOrPrefixScript(s)
    if not s or s == "" then return false end
    -- CJK: U+3000-U+9FFF etc.
    if s:find("[\227-\234][\128-\191][\128-\191]") then return true end
    -- Arabic
    if s:find("[\216-\219][\128-\191]") or s:find("\221[\144-\191]")
        or s:find("\224[\162-\163][\128-\191]") or s:find("\239[\173-\187][\128-\191]") then
        return true
    end
    -- Hebrew: U+0590-U+05FF
    if s:find("[\214-\215][\128-\191]") then return true end
    -- Thai: U+0E00-U+0E7F
    if s:find("\224[\184-\185][\128-\191]") then return true end
    return false
end

local function _matchShorterInLonger(shorter, longer)
    if not shorter or not longer or #shorter == 0 or #longer == 0 then return false end
    if #shorter > #longer then return false end

    local shorter_char_len = _utf8CharLen(shorter)
    local max_run_on = (shorter_char_len < 3) and 0 or 3

    local init = 1
    while true do
        local s, e = longer:find(shorter, init, true)
        if not s then break end

        -- Check 1: Does shorter start a word in longer?
        local starts_word = false
        if s == 1 then
            starts_word = true
        else
            local prev_char = _getPrevChar(longer, s - 1)
            starts_word = _isWordBreakChar(prev_char)
        end

        if starts_word then
            -- Check 2: How many characters does the word run on after e?
            local rest = longer:sub(e + 1)
            local run_on = 0
            local valid = true

            for c in rest:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
                if _isWordBreakChar(c) then
                    break
                else
                    run_on = run_on + 1
                    if run_on > max_run_on then
                        valid = false
                        break
                    end
                end
            end

            if valid and run_on <= max_run_on then
                return true
            end
        end

        init = s + 1
    end

    return false
end

function LookupManager:new(plugin)
    local o = {
        plugin = plugin
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

-- Clean and normalize text for comparison across all languages (Cyrillic, CJK, Latin, Greek, etc.)
function LookupManager:normalize(text)
    if type(text) ~= "string" or text == "" then return "" end
    local clean = utils:trimPunctuation(text)
    return utils:utf8Lower(clean)
end

function LookupManager:getNormName(item)
    if not item or not item.name then return "" end
    local norm = item._norm_name
    if not norm or item._norm_name_src ~= item.name then
        norm = self:normalize(item.name)
        item._norm_name = norm
        item._norm_name_src = item.name
    end
    return norm
end

function LookupManager:getNormAliases(item)
    if not item or not item.aliases or #item.aliases == 0 then
        item._norm_aliases = nil
        return nil
    end

    local norm_list = item._norm_aliases
    local needs_rebuild = not norm_list

    if not needs_rebuild then
        local valid_idx = 0
        for _, alias in ipairs(item.aliases) do
            if type(alias) == "string" and alias ~= "" then
                local anorm = self:normalize(alias)
                if anorm ~= "" then
                    valid_idx = valid_idx + 1
                    if norm_list[valid_idx] ~= anorm then
                        needs_rebuild = true
                        break
                    end
                end
            end
        end
        if not needs_rebuild and valid_idx ~= #norm_list then
            needs_rebuild = true
        end
    end

    if needs_rebuild then
        norm_list = {}
        for _, alias in ipairs(item.aliases) do
            if type(alias) == "string" and alias ~= "" then
                local anorm = self:normalize(alias)
                if anorm ~= "" then
                    table.insert(norm_list, anorm)
                end
            end
        end
        item._norm_aliases = norm_list
    end

    return norm_list
end

-- Perform a robust lookup and return ALL matching candidates, prioritised by
-- pass quality (exact → contains query → query contained in name → keyword).
-- Returns a list of {item, item_type}, which may be empty.
function LookupManager:lookupAll(text)
    if not text or text == "" then return {} end
    local query = self:normalize(text)
    if #query < 2 then return {} end

    local categories = {
        { list = self.plugin.characters,        type = "character"  },
        { list = self.plugin.historical_figures, type = "historical" },
        { list = self.plugin.locations,         type = "location"   },
        { list = self.plugin.terms,             type = "term"       },
    }

    local seen = {}  -- tracks already-added items
    local final_results = {}

    local function addIfMatch(item, item_type)
        if not item or not item.name then return end
        if seen[item] then return end

        local norm = self:getNormName(item)
        if norm == "" then return end

        -- Exact
        if norm == query then
            seen[item] = true
            table.insert(final_results, { item = item, item_type = item_type, score = 100 })
            return
        end

        local norm_aliases = self:getNormAliases(item)

        -- Aliases Exact
        if norm_aliases then
            for _, anorm in ipairs(norm_aliases) do
                if anorm == query then
                    seen[item] = true
                    table.insert(final_results, { item = item, item_type = item_type, score = 95 })
                    return
                end
            end
        end

        -- Contains / Contained (Pass 2 & 3 combined)
        local function checkContains(text_norm)
            if not text_norm or #text_norm < 2 then return false end
            if _isUnsegmentedOrPrefixScript(query) or _isUnsegmentedOrPrefixScript(text_norm) then
                return query:find(text_norm, 1, true) ~= nil or text_norm:find(query, 1, true) ~= nil
            end
            if #query <= #text_norm then
                return _matchShorterInLonger(query, text_norm)
            else
                return _matchShorterInLonger(text_norm, query)
            end
        end

        if checkContains(norm) then
            seen[item] = true
            local contains_score = (item_type == "term") and 30 or 50
            table.insert(final_results, { item = item, item_type = item_type, score = contains_score })
            return
        end

        if norm_aliases then
            for _, anorm in ipairs(norm_aliases) do
                if checkContains(anorm) then
                    seen[item] = true
                    local alias_score = (item_type == "term") and 25 or 40
                    table.insert(final_results, { item = item, item_type = item_type, score = alias_score })
                    return
                end
            end
        end
    end

    for _, cat in ipairs(categories) do
        if cat.list then
            for _, item in ipairs(cat.list) do
                addIfMatch(item, cat.type)
            end
        end
    end

    -- Declension fallback (Slovak/Czech): "Petra" or "Bratislave" should still find
    -- "Peter" or "Bratislava". Only used when nothing else matched.
    if #final_results == 0 and utils:usesInflection(self.plugin) then
        local query_words = {}
        for w in query:gmatch("%S+") do table.insert(query_words, w) end

        local function itemWords(item)
            local words = {}
            for w in self:getNormName(item):gmatch("%S+") do table.insert(words, w) end
            for _, anorm in ipairs(self:getNormAliases(item) or {}) do
                for w in anorm:gmatch("%S+") do table.insert(words, w) end
            end
            return words
        end

        local fallback_seen = {}
        for _, cat in ipairs(categories) do
            if cat.list then
                for _, item in ipairs(cat.list) do
                    if item and item.name and not fallback_seen[item] and self:getNormName(item) ~= "" then
                        local words = itemWords(item)
                        local all_matched = #query_words > 0
                        for _, qw in ipairs(query_words) do
                            local found = false
                            for _, iw in ipairs(words) do
                                if utils:isInflectedForm(iw, qw) then
                                    found = true
                                    break
                                end
                            end
                            if not found then
                                all_matched = false
                                break
                            end
                        end
                        if all_matched then
                            fallback_seen[item] = true
                            table.insert(final_results, { item = item, item_type = cat.type, score = 35 })
                        end
                    end
                end
            end
        end
    end

    if #final_results > 0 then
        -- If we have direct match(es) (exact or alias exact), filter out partial/fuzzy matches
        local best_score = 0
        for _, candidate in ipairs(final_results) do
            if candidate.score > best_score then best_score = candidate.score end
        end
        if best_score >= 95 then
            local filtered = {}
            for _, candidate in ipairs(final_results) do
                if candidate.score >= 95 then
                    table.insert(filtered, candidate)
                end
            end
            final_results = filtered
        end

        local is_anthology = self.plugin and self.plugin.isAnthologyMode and self.plugin:isAnthologyMode()
        local cur_story = is_anthology and self.plugin.getCurrentStory and self.plugin:getCurrentStory() or nil

        table.sort(final_results, function(a, b)
            if is_anthology and cur_story then
                local a_cur = self.plugin:isEntityInCurrentStory(a.item, cur_story)
                local b_cur = self.plugin:isEntityInCurrentStory(b.item, cur_story)
                if a_cur ~= b_cur then
                    return a_cur
                end
            end
            return a.score > b.score
        end)
    end

    return final_results
end

-- Convenience single-result wrapper used by callers that don't need disambiguation
function LookupManager:lookup(text)
    local all = self:lookupAll(text)
    if #all == 0 then return nil, nil end
    return all[1].item, all[1].item_type
end

function LookupManager:showResult(item, item_type, opts)
    opts = opts or {}
    opts.source = "in_text"
    local norm_type = tostring(item_type or ""):lower():gsub("%s+", "_")
    if norm_type == "character" then
        self.plugin:showCharacterDetails(item, opts)
    elseif norm_type == "historical" or norm_type == "historical_figure" or norm_type == "historicalfigure" then
        self.plugin:showHistoricalFigureDetails(item, opts)
    elseif norm_type == "location" then
        self.plugin:showLocationDetails(item, opts)
    elseif norm_type == "term" then
        self.plugin:showTermDetails(item, opts)
    end
end

-- Handle the UI part of the lookup, with a disambiguation picker for multiple hits
function LookupManager:handleLookup(text, pos0, pos1)
    if type(text) == "table" then
        text = text.text or text.word or text.selection_text or ""
    end
    if type(text) ~= "string" or text == "" then return end

    -- Check for unit conversion first
    local settings = self.plugin.ai_helper and self.plugin.ai_helper.settings or {}
    if settings.unit_converter_enabled ~= false then
        local ui_popup_intext = settings.ui_popup_intext
        if ui_popup_intext == nil then ui_popup_intext = true end
        if ui_popup_intext then
            if self.plugin.handleUnitConversionLookup and self.plugin:handleUnitConversionLookup(text) then
                return
            end
        end
    end

    local all = self:lookupAll(text)

    if #all == 1 then
        -- Unambiguous — show directly
        local match = all[1]
        if match.item_type == "term" and match.score < LOW_CONFIDENCE_THRESHOLD then
            self:showResult(match.item, match.item_type, {
                low_confidence = true,
                original_text  = text,
                pos0           = pos0,
                pos1           = pos1,
                score          = match.score,
            })
        else
            self:showResult(match.item, match.item_type)
        end

    elseif #all > 1 then
        -- Multiple candidates — let the user pick
        local ButtonDialog = require("ui/widget/buttondialog")
        local prompt = self.plugin.loc:t("multiple_matches", _truncateSafe(text, 30))
        local buttons = {}
        local dialog

        for _, candidate in ipairs(all) do
            local display_name = candidate.item.name or "???"
            if self.plugin and self.plugin.isAnthologyMode and self.plugin:isAnthologyMode() then
                local st_title = candidate.item.story_title
                if not st_title and self.plugin.resolveEntityStory then
                    st_title = select(2, self.plugin:resolveEntityStory(candidate.item))
                end
                if st_title and st_title ~= "" then
                    display_name = string.format("%s (%s)", display_name, st_title)
                end
            end
            -- Capture loop vars for the closure
            local captured_item = candidate.item
            local captured_type = candidate.item_type
            table.insert(buttons, {
                {
                    text = display_name,
                    callback = function()
                        UIManager:close(dialog)
                        self:showResult(captured_item, captured_type)
                    end,
                }
            })
        end

        -- Cancel row
        table.insert(buttons, {
            {
                text = self.plugin.loc:t("close") or "Close",
                callback = function()
                    UIManager:close(dialog)
                end,
            }
        })

        dialog = ButtonDialog:new{
            title = prompt,
            buttons = buttons,
        }
        UIManager:show(dialog)

    else
        -- No match found
        local ButtonDialog = require("ui/widget/buttondialog")
        local no_data_dialog
        
        local text_to_show = _truncateSafe(text, 30)
        local prompt_text = self.plugin.loc:t("fetch_single_word_prompt", text_to_show)
        if not prompt_text or prompt_text == "fetch_single_word_prompt" then
            prompt_text = string.format("No X-Ray data found for '%s'. Would you like to look it up?", text_to_show)
        end
        
        no_data_dialog = ButtonDialog:new{
            title = prompt_text,
            buttons = {{
                {
                    text = self.plugin.loc:t("close") or "Close",
                    callback = function()
                        UIManager:close(no_data_dialog)
                    end,
                },
                {
                    text = self.plugin.loc:t("fetch_button") or "Fetch",
                    is_enter_default = true,
                    callback = function()
                        UIManager:close(no_data_dialog)
                        if self.plugin and not self.plugin.destroyed then
                            self.plugin:fetchSingleWord(text, pos0, pos1)
                        end
                    end,
                },
            }},
        }
        UIManager:show(no_data_dialog)
    end
end

return LookupManager
