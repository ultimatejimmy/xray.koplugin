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

        local norm = item._norm_name
        if not norm then
            norm = self:normalize(item.name)
            item._norm_name = norm
        end
        if norm == "" then return end

        -- Exact
        if norm == query then
            seen[item] = true
            table.insert(final_results, { item = item, item_type = item_type, score = 100 })
            return
        end

        -- Lazily build _norm_aliases if not yet cached
        if item.aliases and not item._norm_aliases then
            item._norm_aliases = {}
            for _, alias in ipairs(item.aliases) do
                if type(alias) == "string" and alias ~= "" then
                    local anorm = self:normalize(alias)
                    if anorm ~= "" then
                        table.insert(item._norm_aliases, anorm)
                    end
                end
            end
        end

        -- Aliases Exact
        if item._norm_aliases then
            for _, anorm in ipairs(item._norm_aliases) do
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
            return query:find(text_norm, 1, true) or text_norm:find(query, 1, true)
        end

        if checkContains(norm) then
            seen[item] = true
            local contains_score = (item_type == "term") and 30 or 50
            table.insert(final_results, { item = item, item_type = item_type, score = contains_score })
            return
        end

        if item._norm_aliases then
            for _, anorm in ipairs(item._norm_aliases) do
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

    if #final_results > 0 then
        table.sort(final_results, function(a, b) return a.score > b.score end)

        -- If we have direct match(es) (exact or alias exact), filter out partial/fuzzy matches
        local best_score = final_results[1].score
        if best_score >= 95 then
            local filtered = {}
            for _, candidate in ipairs(final_results) do
                if candidate.score >= 95 then
                    table.insert(filtered, candidate)
                end
            end
            final_results = filtered
        end
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
