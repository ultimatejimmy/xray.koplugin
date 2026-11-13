--[[
    xray_horizon.lua
    Horizon spoiler gating, dynamic state resolution, chapter boundaries, and character evolution dialogs for KOReader X-Ray Plugin.
--]]

local UIManager = require("ui/uimanager")
local ButtonDialog = require("ui/widget/buttondialog")

local plugin_path = ((...) or ""):match("(.-)[^%.]+$") or ""
local utils = require(plugin_path .. "xray_utils")
local Evolution = require(plugin_path .. "xray_evolution")
local SeriesManager = require(plugin_path .. "xray_seriesmanager")

local M = {}

function M:getCurrentDocPage()
    local doc_page = nil
    if self.ui then
        if type(self.ui.getCurrentPage) == "function" then
            local ok, p = pcall(function() return self.ui:getCurrentPage() end)
            if ok and p then doc_page = p end
        elseif self.ui.document and type(self.ui.document.getCurrentPage) == "function" then
            local ok, p = pcall(function() return self.ui.document:getCurrentPage() end)
            if ok and p then doc_page = p end
        elseif self.ui.view and self.ui.view.state and self.ui.view.state.page then
            doc_page = self.ui.view.state.page
        elseif self.ui.rolling and self.ui.rolling.current_page then
            doc_page = self.ui.rolling.current_page
        elseif self.ui.paging and type(self.ui.paging.getCurrentPage) == "function" then
            local ok, p = pcall(function() return self.ui.paging:getCurrentPage() end)
            if ok and p then doc_page = p end
        end
    end
    return doc_page or self.last_pageno or 1
end

function M:getCurrentChapterIndex(current_page)
    current_page = current_page or self:getCurrentDocPage()
    if not self.ui or not self.ui.document then return 1 end

    local toc_idx = nil
    pcall(function()
        if self.ui and self.ui.toc and self.ui.toc.getTocIndexByPage then
            toc_idx = self.ui.toc:getTocIndexByPage(current_page)
        end
    end)
    if toc_idx and toc_idx > 0 then return toc_idx end

    local raw_toc
    pcall(function()
        if self.ui.document.getToc then
            raw_toc = self.ui.document:getToc()
        end
    end)
    local toc = utils:flattenTOC(raw_toc)
    if not toc or #toc == 0 then return 1 end
    local best_idx = 1
    local max_page = -1
    for i, ch in ipairs(toc) do
        local p = tonumber(ch.page)
        if not p and ch.xpointer and self.ui.document.getPageFromXPointer then
            pcall(function() p = self.ui.document:getPageFromXPointer(ch.xpointer) end)
        end
        if p and p <= current_page and p >= max_page then
            max_page = p
            best_idx = i
        end
    end
    return best_idx
end

function M:hasEntityEvolution(entity)
    if not entity then return false end
    local state_count = (entity.states and type(entity.states) == "table") and #entity.states or 0
    local hist_count = (entity.history and type(entity.history) == "table") and #entity.history or 0
    if state_count == 0 and hist_count == 0 then return false end

    local ok, Evolution = pcall(require, plugin_path .. "xray_evolution")
    if not ok or not Evolution or not Evolution.build then return false end
    local all_milestones = Evolution.build(entity, { is_full_book = true })
    local key_milestones = Evolution.filterKey(all_milestones)
    return #key_milestones >= 2
end

function M:getChapterPageBounds(cur_chap)
    cur_chap = tonumber(cur_chap)
    if not cur_chap then return nil, nil end
    local toc = (self._getFlatToc and self:_getFlatToc()) or (self.ui and self.ui.document and self.ui.document.getToc and utils:flattenTOC(self.ui.document:getToc()))
    if not toc or next(toc) == nil then return nil, nil end
    local entry = toc[cur_chap]
    if not entry or not entry.page then return nil, nil end
    local start_p = tonumber(entry.page)
    local next_entry = toc[cur_chap + 1]
    local end_p = nil
    if next_entry and next_entry.page then
        end_p = tonumber(next_entry.page) - 1
    else
        local total_p = self.ui and self.ui.document and self.ui.document.getPageCount and self.ui.document:getPageCount()
        end_p = tonumber(total_p)
    end
    if end_p and start_p and end_p < start_p then
        end_p = start_p
    end
    return start_p, end_p
end

function M:isPositionGateUnlocked(gate, cur_chap, cur_page, opts)
    if not gate or type(gate) ~= "table" then return true end
    local is_full_book = (self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.spoiler_setting == "full_book")
    if is_full_book then return true end

    cur_page = tonumber(cur_page) or tonumber(self:getCurrentDocPage())
    cur_chap = tonumber(cur_chap) or tonumber(self:getCurrentChapterIndex(cur_page)) or 1

    local g_chap = tonumber(gate.chapter_index)
    if g_chap and cur_chap then
        if cur_chap < g_chap then
            return false
        elseif cur_chap > g_chap then
            return true
        end
    end

    local live_start, live_end = self:getChapterPageBounds(cur_chap)

    if gate.chapter_pct ~= nil then
        local g_pct = tonumber(gate.chapter_pct) or 0.0
        local is_repaginated = live_start and live_end and live_end > live_start and gate.ch_start_page and gate.ch_end_page and (live_start ~= gate.ch_start_page or live_end ~= gate.ch_end_page)
        if is_repaginated and cur_page then
            local r_pct = math.max(0, math.min(1, (cur_page - live_start) / (live_end - live_start)))
            return (r_pct + 0.0005) >= g_pct
        end

        if gate.page_hint and cur_page then
            return cur_page >= gate.page_hint
        elseif live_start and live_end and live_end > live_start and cur_page then
            local r_pct = math.max(0, math.min(1, (cur_page - live_start) / (live_end - live_start)))
            return (r_pct + 0.0005) >= g_pct
        else
            return g_pct <= 0.0
        end
    end

    -- Legacy Cache Self-Healing:
    -- If this is a state update (opts.is_state_update is true) and page_hint equals chapter start on a multi-page chapter,
    -- gate at chapter end!
    if opts and opts.is_state_update and live_start and live_end and live_end > live_start and cur_page then
        local p_hint = tonumber(gate.page_hint)
        if p_hint and p_hint == live_start then
            return cur_page >= live_end
        end
    end

    if gate.page_hint and cur_page then
        return cur_page >= gate.page_hint
    end

    return true
end

function M:getUnlockedAliases(entity, cur_chap, cur_page)
    if type(entity) ~= "table" or type(entity.aliases) ~= "table" then
        return {}
    end
    local is_full_book = (self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.spoiler_setting == "full_book")
    if is_full_book or type(entity.alias_visible_from) ~= "table" then
        return entity.aliases
    end
    cur_page = tonumber(cur_page) or tonumber(self:getCurrentDocPage())
    cur_chap = tonumber(cur_chap) or tonumber(self:getCurrentChapterIndex(cur_page)) or 1
    local unlocked = {}
    for _, a in ipairs(entity.aliases) do
        if a and a ~= "" then
            local gate = entity.alias_visible_from[a:lower()]
            if not gate or self:isPositionGateUnlocked(gate, cur_chap, cur_page, { is_state_update = true }) then
                table.insert(unlocked, a)
            end
        end
    end
    return unlocked
end

function M:getUnlockedStateCount(entity, cur_chap, cur_page, is_full_book)
    if not entity then return 0 end
    local has_states = (entity.states and type(entity.states) == "table" and #entity.states > 0)
    local has_history = (entity.history and type(entity.history) == "table" and #entity.history > 0)
    if not has_states and not has_history then return 0 end

    if is_full_book == nil then
        is_full_book = (self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.spoiler_setting == "full_book")
    end
    if is_full_book then
        return has_states and #entity.states or #entity.history
    end

    cur_page = tonumber(cur_page) or tonumber(self:getCurrentDocPage()) or 1
    cur_chap = tonumber(cur_chap) or tonumber(self:getCurrentChapterIndex(cur_page)) or 1

    if has_states then
        local count = 0
        for idx, s in ipairs(entity.states) do
            local is_upd = (idx > 1) or has_history or (entity.is_series == true) or (entity.from_series == true)
            if self:isPositionGateUnlocked(s, cur_chap, cur_page, { is_state_update = is_upd }) then
                count = count + 1
            end
        end
        return count
    else
        local count = 0
        for _, h in ipairs(entity.history) do
            local applies = false
            local h_chap = tonumber(h.chapter_index or h.chapter)
            local h_page = tonumber(h.page_hint or h.page)
            if h_chap then
                if h_chap < cur_chap then
                    applies = true
                elseif h_chap == cur_chap then
                    if h_page and cur_page then
                        applies = (cur_page >= h_page)
                    else
                        applies = true
                    end
                end
            elseif h_page and cur_page then
                applies = (cur_page >= h_page)
            else
                applies = true
            end
            if applies then
                count = count + 1
            end
        end
        return count
    end
end

function M:isEntityVisibleAtCurrentPosition(entity, current_chapter_idx, current_page)
    if not entity then return false end
    local is_full_book = (self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.spoiler_setting == "full_book")
    if is_full_book then return true end

    current_page = current_page or self:getCurrentDocPage()
    current_chapter_idx = current_chapter_idx or self:getCurrentChapterIndex(current_page)

    if entity.is_series or entity.from_series then
        local b_desc = entity.description or entity.definition or ""
        if type(b_desc) == "string" and b_desc:find("%[From Book [%d%.]+%]") then
            return true
        end
    end

    if entity.visible_from then
        if not self:isPositionGateUnlocked(entity.visible_from, current_chapter_idx, current_page, { is_state_update = false }) then
            return false
        end
    end

    if entity.states and #entity.states > 0 then
        local any_unlocked = false
        for idx, st in ipairs(entity.states) do
            local has_prior_history = (type(entity.history) == "table" and #entity.history > 0)
            local is_upd = (idx > 1) or has_prior_history or (entity.is_series == true) or (entity.from_series == true)
            if self:isPositionGateUnlocked(st, current_chapter_idx, current_page, { is_state_update = is_upd }) then
                any_unlocked = true
                break
            end
        end
        if not any_unlocked then
            if entity.history and #entity.history > 0 then
                for _, h in ipairs(entity.history) do
                    if h.page and current_page and h.page <= current_page then
                        any_unlocked = true
                        break
                    end
                end
            end
            if not any_unlocked then
                return false
            end
        end
    end

    return true
end

function M:resolveEntityState(entity, current_chapter_idx, current_page)
    if not entity then return nil, nil, nil end
    local is_full_book = (self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.spoiler_setting == "full_book")
    current_page = current_page or self:getCurrentDocPage()
    current_chapter_idx = current_chapter_idx or self:getCurrentChapterIndex(current_page)

    local desc_key = (entity.biography and "biography") or (entity.definition and "definition") or "description"
    local base_desc = entity[desc_key] or entity.description

    local prior_sections = {}
    if base_desc and type(base_desc) == "string" and base_desc:find("%[From Book [%d%.]+%]") then
        for sec in (base_desc .. "\n\n"):gmatch("(.-)\n%s*\n+") do
            local trimmed = sec:match("^%s*(.-)%s*$")
            if trimmed and trimmed:find("^%[From Book [%d%.]+%]") then
                table.insert(prior_sections, trimmed)
            end
        end
    end

    local function combineWithPrior(raw_text)
        if not raw_text or raw_text == "" or raw_text == "---" then
            if #prior_sections > 0 then
                return SeriesManager.reorderSeriesDescription(table.concat(prior_sections, "\n\n"))
            end
            return raw_text
        end
        if #prior_sections > 0 and not raw_text:find("%[From Book [%d%.]+%]") then
            return SeriesManager.reorderSeriesDescription(raw_text .. "\n\n" .. table.concat(prior_sections, "\n\n"))
        end
        return SeriesManager.reorderSeriesDescription(raw_text)
    end

    if not entity.states or #entity.states == 0 then
        return entity.role or entity.category, entity.status or "alive", combineWithPrior(base_desc)
    end

    if is_full_book then
        local latest_state = entity.states[#entity.states]
        local raw_d = latest_state.description or base_desc
        return latest_state.role or entity.role or entity.category, latest_state.status or entity.status or "alive", combineWithPrior(raw_d)
    end

    local best_state = nil
    for idx, s in ipairs(entity.states) do
        local has_prior_history = (type(entity.history) == "table" and #entity.history > 0)
        local is_upd = (idx > 1) or has_prior_history or (entity.is_series == true) or (entity.from_series == true)
        local applies = self:isPositionGateUnlocked(s, current_chapter_idx, current_page, { is_state_update = is_upd })
        if applies then
            if not best_state then
                best_state = s
            else
                local best_chap = best_state.chapter_index or 1
                local s_chap = s.chapter_index or 1
                if s_chap > best_chap then
                    best_state = s
                elseif s_chap == best_chap then
                    local p1, p2 = s.page_hint or 0, best_state.page_hint or 0
                    if p1 > p2 then
                        best_state = s
                    elseif p1 == p2 and (s.chapter_pct or 0) >= (best_state.chapter_pct or 0) then
                        best_state = s
                    end
                end
            end
        end
    end

    if best_state then
        local raw_d = best_state.description or base_desc
        return best_state.role or entity.role or entity.category, best_state.status or entity.status or "alive", combineWithPrior(raw_d)
    end

    -- If reader is earlier than all states: do NOT return future states!
    -- Consult history first
    if entity.history and #entity.history > 0 and current_page then
        local best_hist = nil
        for _, h in ipairs(entity.history) do
            if h.page and h.page <= current_page then
                if not best_hist or h.page > best_hist.page then
                    best_hist = h
                end
            end
        end
        if best_hist then
            local raw_h = best_hist[desc_key] or best_hist.description or best_hist.event or ""
            return best_hist.role or entity.role or entity.category, best_hist.status or entity.status or "alive", combineWithPrior(raw_h)
        end
    end

    -- If prior series section exists, show that
    if #prior_sections > 0 then
        return entity.role or entity.category, entity.status or "alive", combineWithPrior(nil)
    end

    return nil, nil, nil
end

function M:resolveDescriptionForPage(entity, current_page)
    if not entity then return "---" end
    local desc_key = (entity.biography and "biography") or (entity.definition and "definition") or "description"

    -- Route through state resolution if states exist
    if entity.states and #entity.states > 0 then
        local _, _, r_desc = self:resolveEntityState(entity, nil, current_page)
        if r_desc and r_desc ~= "" and r_desc ~= "---" then
            return SeriesManager.reorderSeriesDescription(r_desc)
        end
        return "---"
    end

    -- If there's no history table, return the default description/biography/definition
    if not entity.history or #entity.history == 0 then
        local raw_d = entity[desc_key] or entity.description or entity.definition
        return raw_d and SeriesManager.reorderSeriesDescription(raw_d) or "---"
    end

    -- Default current_page fallback
    current_page = current_page or self:getCurrentDocPage()

    -- Traverse history and find the latest entry where entry.page <= current_page
    local best_entry = nil
    for _, entry in ipairs(entity.history) do
        if entry.page and entry.page <= current_page then
            if not best_entry or entry.page > best_entry.page then
                best_entry = entry
            end
        end
    end

    if best_entry then
        local raw_d = best_entry[desc_key] or best_entry.description or best_entry.definition
        local base_d = entity[desc_key] or entity.description or entity.definition
        if raw_d and base_d and not raw_d:find("%[From Book [%d%.]+%]") and base_d:find("%[From Book [%d%.]+%]") then
            raw_d = raw_d .. "\n\n" .. base_d
        end
        return raw_d and SeriesManager.reorderSeriesDescription(raw_d) or "---"
    end

    -- Fallback to the first history entry only if spoiler_setting is full_book
    local is_full_book = (self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.spoiler_setting == "full_book")
    if is_full_book and #entity.history > 0 then
        local raw_d = entity.history[1][desc_key] or entity.history[1].description or entity.history[1].definition
        local base_d = entity[desc_key] or entity.description or entity.definition
        if raw_d and base_d and not raw_d:find("%[From Book [%d%.]+%]") and base_d:find("%[From Book [%d%.]+%]") then
            raw_d = raw_d .. "\n\n" .. base_d
        end
        return raw_d and SeriesManager.reorderSeriesDescription(raw_d) or "---"
    end

    return "---"
end

function M:showPastEvolution(entity, opts)
    if not entity then return end
    local ok, err = pcall(function()
        if self.active_evolution_menu then
            UIManager:close(self.active_evolution_menu)
            self.active_evolution_menu = nil
        end
        local EntityListOverlay = require(plugin_path .. "xray_entity_list")
        self.active_evolution_menu = EntityListOverlay:new{
            plugin = self,
            mode = "evolution",
            entity = entity,
            opts = opts or {},
            on_close_callback = function()
                self.active_evolution_menu = nil
            end,
        }
        UIManager:show(self.active_evolution_menu, "ui")
    end)
    if not ok then
        logger.warn("XRayPlugin: showPastEvolution error: " .. tostring(err))
        local InfoMessage = require("ui/widget/infomessage")
        UIManager:show(InfoMessage:new{
            text = "Could not display story arc: " .. tostring(err),
            timeout = 3,
        })
    end
end


return M
