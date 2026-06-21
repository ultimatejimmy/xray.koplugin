-- LookupManager - Core logic for text selection lookups
local logger = require("logger")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")

-- Minimum score to consider a match "high confidence" and skip the re-lookup prompt.
-- Scores 100 (exact) and 95 (alias exact) are above this; 50/40/30 are below.
local LOW_CONFIDENCE_THRESHOLD = 70

local LookupManager = {}


function LookupManager:new(plugin)
    local o = {
        plugin = plugin
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

-- Clean and normalize text for comparison
function LookupManager:normalize(text)
    if type(text) ~= "string" or text == "" then return "" end
    -- Remove non-alphanumeric characters from start/end and lowercase
    local clean = text:gsub("^[^%w]+", ""):gsub("[^%w]+$", ""):lower()
    return clean
end

-- Collect all matches from a category list using a test function.
-- Returns a list of {item, type} tables. Skips items already seen (by name).
local function collectMatches(categories, seen, testFn)
    local results = {}
    for _, cat in ipairs(categories) do
        if cat.list then
            for _, item in ipairs(cat.list) do
                if item.name then
                    local norm = item.name:lower()
                    if not seen[norm] and testFn(item.name, cat) then
                        seen[norm] = true
                        table.insert(results, { item = item, item_type = cat.type })
                    end
                end
            end
        end
    end
    return results
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

    local seen = {}  -- tracks already-added names across passes

    -- Pass 1: Exact match (using cached normalized names if available)
    local results = collectMatches(categories, seen, function(name, cat_item)
        local item = cat_item -- the specific item from the list
        -- Note: collectMatches passes (item.name, cat) where cat is {list, type}
        -- Wait, collectMatches implementation is: testFn(item.name, cat)
        -- I need the item itself to check _norm_name.
        -- Let's check collectMatches again.
        return nil -- dummy
    end)
    -- Actually, let's just rewrite the passes for performance
    
    local final_results = {}
    
    local function addIfMatch(item, item_type, score)
        local n = (item.name or ""):lower()
        if seen[n] then return end
        
        local norm = item._norm_name or self:normalize(item.name)
        
        -- Exact
        if norm == query then
            seen[n] = true
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
                    seen[n] = true
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
            seen[n] = true
            local contains_score = (item_type == "term") and 30 or 50
            table.insert(final_results, { item = item, item_type = item_type, score = contains_score })
            return
        end

        if item._norm_aliases then
            for _, anorm in ipairs(item._norm_aliases) do
                if checkContains(anorm) then
                    seen[n] = true
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
    if item_type == "character" then
        self.plugin:showCharacterDetails(item, opts)
    elseif item_type == "historical" or item_type == "historical_figure" then
        self.plugin:showHistoricalFigureDetails(item, opts)
    elseif item_type == "location" then
        self.plugin:showLocationDetails(item, opts)
    elseif item_type == "term" then
        self.plugin:showTermDetails(item, opts)
    end
end

-- Handle the UI part of the lookup, with a disambiguation picker for multiple hits
function LookupManager:handleLookup(text, pos0, pos1)
    logger.info("XRayPlugin: handleLookup called for:", text)
    if type(text) ~= "string" or text == "" then return end

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
        local prompt = self.plugin.loc:t("multiple_matches", text:sub(1, 30))
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
        local ConfirmBox = require("ui/widget/confirmbox")
        local no_data_dialog
        
        local text_to_show = text:sub(1, 30)
        local prompt_text = self.plugin.loc:t("fetch_single_word_prompt", text_to_show)
        if not prompt_text or prompt_text == "fetch_single_word_prompt" then
            prompt_text = string.format("No X-Ray data found for '%s'. Would you like to look it up?", text_to_show)
        end
        
        no_data_dialog = ConfirmBox:new{
            text       = prompt_text,
            ok_text    = self.plugin.loc:t("fetch_button") or "Fetch",
            cancel_text = self.plugin.loc:t("close") or "Close",
            ok_callback = function()
                UIManager:close(no_data_dialog)
                self.plugin:fetchSingleWord(text, pos0, pos1)
            end,
            cancel_callback = function()
                UIManager:close(no_data_dialog)
            end,
        }
        UIManager:show(no_data_dialog)
    end
end

return LookupManager
