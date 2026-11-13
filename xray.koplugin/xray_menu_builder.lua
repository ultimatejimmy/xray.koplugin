--[[
    xray_menu_builder.lua
    Main menu items, sub-menu hierarchy, and badge count computation for KOReader X-Ray Plugin.
--]]

local plugin_path = ((...) or ""):match("(.-)[^%.]+$") or ""

local M = {}

local function _t(self, key, default)
    if self and self.loc and self.loc.t then
        local res = self.loc:t(key)
        if res and res ~= key then return res end
    end
    return default
end

function M:getMenuCounts()
    if self.isAnthologyMode and self:isAnthologyMode() and not self.anthology_show_all_stories then
        local current_story = self.getCurrentStory and self:getCurrentStory()
        local function countStory(list)
            if not list then return 0 end
            local c = 0
            for _, item in ipairs(list) do
                if self:isEntityInCurrentStory(item, current_story) then
                    c = c + 1
                end
            end
            return c
        end
        return {
            characters = countStory(self.characters),
            locations = countStory(self.locations),
            timeline = countStory(self.timeline),
            historical_figures = countStory(self.historical_figures),
            terms = countStory(self.terms),
            images = self.images and #self.images or 0,
        }
    end
    return {
        characters = self.characters and #self.characters or 0,
        locations = self.locations and #self.locations or 0,
        timeline = self.timeline and #self.timeline or 0,
        historical_figures = self.historical_figures and #self.historical_figures or 0,
        terms = self.terms and #self.terms or 0,
        images = self.images and #self.images or 0,
    }
end


function M:getSubMenuItems()
    local items = {
        {
            text = self.loc:t("menu_characters") or "Characters",
            keep_menu_open = true,
            callback = function() self:showCharacters() end,
        },
        {
            text = self.loc:t("menu_timeline") or "Timeline",
            keep_menu_open = true,
            callback = function() self:showTimeline() end,
        },
        {
            text = self.loc:t("menu_historical_figures") or "Historical Figures",
            keep_menu_open = true,
            callback = function() self:showHistoricalFigures() end,
        },
        {
            text = self.loc:t("menu_locations") or "Locations",
            keep_menu_open = true,
            callback = function() self:showLocations() end,
        },
    }

    table.insert(items, {
        text = self.loc:t("menu_terms") or "Glossary",
        keep_menu_open = true,
        callback = function() self:showTerms() end,
    })

    table.insert(items, {
        text = self.loc:t("menu_images") or "Images & Maps",
        keep_menu_open = true,
        callback = function() self:showImages() end,
    })

    table.insert(items, {
        text = self.loc:t("menu_author_info"),
        keep_menu_open = true,
        callback = function() self:showAuthorInfo() end,
        separator = true,
    })

    local has_xray_data = self:hasXRayData()
    table.insert(items, {
        text = has_xray_data and (self.loc:t("menu_update_xray") or "Update X-Ray Data (Merge)")
            or (self.loc:t("menu_fetch_xray") or "Fetch X-Ray Data"),
        text_func = function()
            if self:hasXRayData() then
                return self.loc:t("menu_update_xray") or "Update X-Ray Data (Merge)"
            else
                return self.loc:t("menu_fetch_xray") or "Fetch X-Ray Data"
            end
        end,
        keep_menu_open = true,
        callback = function()
            if self:hasXRayData() then
                self:updateFromAI()
            else
                self:fetchFromAI()
            end
        end,
        separator = true,
    })

    local function getPregenerateMenuText()
        if self.is_sequential_scan_active then
            local done = self.active_sequential_completed_chapters or self.active_sequential_completed or 0
            local total = self.active_sequential_total_chapters or self.active_sequential_total or 0
            local fmt = (self.loc and self.loc:t("pregeneration_progress")) or "Pre-generating X-Ray: Chapter %d of %d..."
            return fmt:format(done, total)
        else
            return self.loc:t("menu_pregenerate_book") or "Pre-generate Entire Book…"
        end
    end

    table.insert(items, {
        text = getPregenerateMenuText(),
        text_func = getPregenerateMenuText,
        keep_menu_open = true,
        callback = function()
            self:startFullBookPreGeneration()
        end,
        separator = true,
    })

    self.current_xray_menu_table = items
    table.insert(items, {
        text = self.loc:t("menu_settings") or "Settings",
        keep_menu_open = true,
        sub_item_table = {
            {
                text = self.loc:t("menu_display_ui_settings") or "Display & UI Settings",
                keep_menu_open = true,
                sub_item_table = {
                    {
                        text = self.loc:t("menu_ui_popup_intext") or "Use Footnote Style for In-text Lookups",
                        checked_func = function()
                            local val = self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.ui_popup_intext
                            if val == nil then return true end
                            return val
                        end,
                        callback = function()
                            if self.ai_helper and self.ai_helper.settings then
                                local current = self.ai_helper.settings.ui_popup_intext
                                if current == nil then current = true end
                                self.ai_helper:saveSettings({ ui_popup_intext = not current })
                            end
                        end,
                    },
                    {
                        text = self.loc:t("menu_ui_popup_menu") or "Use Footnote Style for Menu Lookups",
                        checked_func = function()
                            local val = self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.ui_popup_menu
                            if val == nil then return false end
                            return val
                        end,
                        callback = function()
                            if self.ai_helper and self.ai_helper.settings then
                                local current = self.ai_helper.settings.ui_popup_menu
                                if current == nil then current = false end
                                self.ai_helper:saveSettings({ ui_popup_menu = not current })
                            end
                        end,
                    },
                    {
                        text = self.loc:t("menu_popup_font_size") or "Popup & Footnote Font Size",
                        keep_menu_open = true,
                        callback = function() self:showPopupFontSizeCard() end,
                    },
                    {
                        text = self.loc:t("menu_linked_entries_settings") or "Linked Entries Settings",
                        keep_menu_open = true,
                        callback = function() self:showLinkedEntriesSettings() end,
                    },
                    {
                        text = self.loc:t("mentions_setting_title") or "Mentions Settings",
                        keep_menu_open = true,
                        callback = function() self:showMentionsSettings() end,
                    },
                    {
                        text = self.loc:t("menu_evolution_settings") or "Story Arc Settings",
                        keep_menu_open = true,
                        callback = function() self:showEvolutionSettings() end,
                    },
                }
            },
            {
                text = self.loc:t("menu_content_fetch_settings") or "Content & Fetch Settings",
                keep_menu_open = true,
                sub_item_table = {
                    {
                        text = self.loc:t("menu_auto_update_frequency") or "Auto X-Ray Settings",
                        keep_menu_open = true,
                        sub_item_table = {
                            {
                                text = self.loc:t("menu_frequency") or "Frequency",
                                keep_menu_open = true,
                                callback = function() self:showAutoUpdateSettings() end,
                            },
                            {
                                text = self.loc:t("auto_dupe_check_setting_title") or "Duplicate Check",
                                keep_menu_open = true,
                                callback = function() self:showAutoDupeCheckSettings() end,
                            },
                        }
                    },
                    {
                        text = self.loc:t("menu_book_mode") or "Book Type",
                        keep_menu_open = true,
                        callback = function() self:showBookTypeSettings() end,
                    },
                    {
                        text = self.loc:t("menu_story_toc_depth") or "Anthology Story ToC Level",
                        keep_menu_open = true,
                        enabled_func = function() return self:isAnthologyMode() end,
                        callback = function() self:showAnthologyTocDepthSettings() end,
                    },
                    {
                        text = self.loc:t("menu_desc_length_settings") or "Description Length Settings",
                        keep_menu_open = true,
                        sub_item_table = {
                            {
                                text = self.loc:t("menu_characters") or "Characters",
                                keep_menu_open = true,
                                callback = function() self:showEntityLengthPresets("char_desc_len", self.loc:t("menu_characters")) end,
                            },
                            {
                                text = self.loc:t("menu_locations") or "Locations",
                                keep_menu_open = true,
                                callback = function() self:showEntityLengthPresets("loc_desc_len", self.loc:t("menu_locations")) end,
                            },
                            {
                                text = self.loc:t("menu_timeline") or "Timeline",
                                keep_menu_open = true,
                                callback = function() self:showEntityLengthPresets("timeline_event_len", self.loc:t("menu_timeline"), true) end,
                            },
                            {
                                text = self.loc:t("menu_historical_figures") or "Historical Figures",
                                keep_menu_open = true,
                                callback = function() self:showEntityLengthPresets("hist_fig_bio_len", self.loc:t("menu_historical_figures")) end,
                            },
                            {
                                text = self.loc:t("menu_terms") or "Glossary",
                                keep_menu_open = true,
                                callback = function() self:showEntityLengthPresets("term_def_len", self.loc:t("menu_terms") or "Glossary") end,
                            },
                        }
                    },
                    {
                        text = self.loc:t("menu_series_context") or "Series Context",
                        keep_menu_open = true,
                        sub_item_table = {
                            {
                                text = self.loc:t("series_context_enabled_toggle") or "Enable Series Context",
                                checked_func = function() return self.ai_helper.settings.series_context_enabled end,
                                callback = function() self:toggleSeriesContextEnabled() end,
                            },
                            {
                                text = self.loc:t("menu_fetch_series_context") or "Fetch / Refresh Series Context",
                                keep_menu_open = true,
                                callback = function() self:manualFetchSeriesContext() end,
                            },
                            {
                                text = self.loc:t("menu_manage_series") or "Manage Series…",
                                keep_menu_open = true,
                                callback = function() self:showManageSeriesDialog() end,
                            },
                            {
                                text = self.loc:t("menu_clear_series_cache") or "Clear Series Cache",
                                keep_menu_open = true,
                                callback = function() self:clearSeriesCache() end,
                            }
                        }
                    },
                    {
                        text = self.loc:t("spoiler_preference_title") or "Spoiler Settings",
                        keep_menu_open = true,
                        callback = function() self:showSpoilerSettings() end,
                    },
                    {
                        text = self.loc:t("menu_prefetch_horizon") or "Prefetch Horizon (Offline Readers)",
                        keep_menu_open = true,
                        callback = function() self:showPrefetchHorizonSettings() end,
                    },
                }
            },
            {
                text = self.loc:t("menu_xray_mode"),
                keep_menu_open = true,
                callback = function() self:toggleXRayMode() end,
            },
            {
                is_unit_converter = true,
                text = self.loc:t("menu_unit_converter") or "Unit Converter",
                keep_menu_open = true,
                sub_item_table = {
                    {
                        text = self.loc:t("unit_conv_enabled") or "Enable Unit Converter",
                        checked_func = function()
                            return self.ai_helper.settings.unit_converter_enabled ~= false
                        end,
                        callback = function()
                            local current = self.ai_helper.settings.unit_converter_enabled ~= false
                            self.ai_helper:saveSettings({
                                unit_converter_enabled = not current,
                                unit_new_feature_prompt_seen = true,
                            })
                            if self.scanBookForUnits then self:scanBookForUnits() end
                        end
                    },
                    {
                        text = self.loc:t("unit_scan_written_numbers") or "Scan Written Numbers (e.g. 'five miles')",
                        keep_menu_open = true,
                        callback = function()
                            self:showUnitScanWrittenNumbersCard()
                        end
                    },
                    {
                        text = self.loc:t("unit_auto_scan_settings") or "Auto-Scan Settings",
                        keep_menu_open = true,
                        callback = function()
                            self:showUnitAutoScanCard()
                        end
                    },
                    {
                        text_func = function()
                            local base = self.loc:t("unit_manual_scan_button") or "Scan/Rescan"
                            if self._unit_scan_in_progress then
                                return base .. " (" .. (self.loc:t("unit_scan_running_menu") or "Scanning…") .. ")"
                            end
                            return base
                        end,
                        keep_menu_open = true,
                        callback = function()
                            if self.scanBookForUnits then self:scanBookForUnits(true) end
                        end,
                        separator = true,
                    },
                    {
                        text = self.loc:t("unit_book_type_filter") or "Book Type Filter",
                        keep_menu_open = true,
                        sub_item_table_func = function()
                            return self:getBookTypeFilterMenu()
                        end
                    },
                    {
                        text = self.loc:t("unit_conv_direction") or "Conversion Direction",
                        keep_menu_open = true,
                        callback = function()
                            self:showUnitConversionDirectionSettings()
                        end
                    },
                    {
                        text = self.loc:t("unit_conv_style_settings") or "Style & Underline Settings",
                        keep_menu_open = true,
                        callback = function()
                            self:showUnitStyleCard()
                        end
                    },
                    {
                        text = self.loc:t("menu_unit_categories") or "Unit Categories",
                        keep_menu_open = true,
                        sub_item_table = {
                            {
                                text = "Length (mile, feet, inch, m, km...)",
                                checked_func = function()
                                    return self.ai_helper.settings.unit_cat_length ~= false
                                end,
                                callback = function()
                                    local curr = self.ai_helper.settings.unit_cat_length ~= false
                                    self.ai_helper:saveSettings({ unit_cat_length = not curr })
                                    if self.scanBookForUnits then self:scanBookForUnits() end
                                end
                            },
                            {
                                text = "Weight / Mass (pound, ounce, kg, g...)",
                                checked_func = function()
                                    return self.ai_helper.settings.unit_cat_weight ~= false
                                end,
                                callback = function()
                                    local curr = self.ai_helper.settings.unit_cat_weight ~= false
                                    self.ai_helper:saveSettings({ unit_cat_weight = not curr })
                                    if self.scanBookForUnits then self:scanBookForUnits() end
                                end
                            },
                            {
                                text = "Temperature (fahrenheit, celsius)",
                                checked_func = function()
                                    return self.ai_helper.settings.unit_cat_temp ~= false
                                end,
                                callback = function()
                                    local curr = self.ai_helper.settings.unit_cat_temp ~= false
                                    self.ai_helper:saveSettings({ unit_cat_temp = not curr })
                                    if self.scanBookForUnits then self:scanBookForUnits() end
                                end
                            },
                            {
                                text = "Volume (gallon, cup, liter, ml...)",
                                checked_func = function()
                                    return self.ai_helper.settings.unit_cat_volume ~= false
                                end,
                                callback = function()
                                    local curr = self.ai_helper.settings.unit_cat_volume ~= false
                                    self.ai_helper:saveSettings({ unit_cat_volume = not curr })
                                    if self.scanBookForUnits then self:scanBookForUnits() end
                                end
                            },
                            {
                                text = "Speed (mph, km/h)",
                                checked_func = function()
                                    return self.ai_helper.settings.unit_cat_speed ~= false
                                end,
                                callback = function()
                                    local curr = self.ai_helper.settings.unit_cat_speed ~= false
                                    self.ai_helper:saveSettings({ unit_cat_speed = not curr })
                                    if self.scanBookForUnits then self:scanBookForUnits() end
                                end
                            },
                            {
                                text = "Area (acre, hectare, m², sq ft...)",
                                checked_func = function()
                                    return self.ai_helper.settings.unit_cat_area ~= false
                                end,
                                callback = function()
                                    local curr = self.ai_helper.settings.unit_cat_area ~= false
                                    self.ai_helper:saveSettings({ unit_cat_area = not curr })
                                    if self.scanBookForUnits then self:scanBookForUnits() end
                                end
                            }
                        }
                    }
                },
                separator = true,
            },
            {
                is_entity_footnotes = true,
                text = self.loc:t("menu_entity_footnotes") or "Entity Underlining",
                keep_menu_open = true,
                sub_item_table = {
                    {
                        text = self.loc:t("entity_footnotes_enabled") or "Enable Entity Underlining",
                        checked_func = function()
                            return self.ai_helper.settings.entity_footnotes_enabled == true
                        end,
                        callback = function()
                            local current = self.ai_helper.settings.entity_footnotes_enabled == true
                            self.ai_helper:saveSettings({
                                entity_footnotes_enabled = not current,
                                entity_new_feature_prompt_seen = true,
                            })
                            if not current then
                                if self.scanBookForEntities then self:scanBookForEntities(true) end
                            else
                                if self.clearEntityUnderlines then self:clearEntityUnderlines() end
                            end
                        end
                    },
                    {
                        text_func = function()
                            local base = self.loc:t("entity_manual_scan_button") or "Scan/Rescan"
                            if self._entity_scan_in_progress then
                                return base .. " (" .. (self.loc:t("unit_scan_running_menu") or "Scanning…") .. ")"
                            end
                            return base
                        end,
                        keep_menu_open = true,
                        callback = function()
                            if self.scanBookForEntities then self:scanBookForEntities(true) end
                        end,
                        separator = true,
                    },
                    {
                        text = self.loc:t("entity_style_settings") or "Style & Underline Settings",
                        keep_menu_open = true,
                        callback = function()
                            self:showEntityStyleCard()
                        end
                    },
                    {
                        text = self.loc:t("entity_popup_style_title") or "Popup Display Style",
                        keep_menu_open = true,
                        callback = function()
                            self:showEntityPopupStyleCard()
                        end
                    },
                    {
                        text = self.loc:t("entity_mention_mode_title") or "Mention Display Mode",
                        keep_menu_open = true,
                        callback = function()
                            self:showEntityMentionModeCard()
                        end
                    },
                    {
                        text = self.loc:t("menu_entity_categories") or "Entity Categories",
                        keep_menu_open = true,
                        sub_item_table = {
                            {
                                text = self.loc:t("entity_cat_characters") or "Characters",
                                checked_func = function()
                                    return self.ai_helper.settings.entity_cat_characters ~= false
                                end,
                                callback = function()
                                    local curr = self.ai_helper.settings.entity_cat_characters ~= false
                                    self.ai_helper:saveSettings({ entity_cat_characters = not curr })
                                    if self.scanBookForEntities then self:scanBookForEntities(true) end
                                end
                            },
                            {
                                text = self.loc:t("entity_cat_historical_figures") or "Historical Figures",
                                checked_func = function()
                                    return self.ai_helper.settings.entity_cat_historical_figures ~= false
                                end,
                                callback = function()
                                    local curr = self.ai_helper.settings.entity_cat_historical_figures ~= false
                                    self.ai_helper:saveSettings({ entity_cat_historical_figures = not curr })
                                    if self.scanBookForEntities then self:scanBookForEntities(true) end
                                end
                            },
                            {
                                text = self.loc:t("entity_cat_locations") or "Locations",
                                checked_func = function()
                                    return self.ai_helper.settings.entity_cat_locations ~= false
                                end,
                                callback = function()
                                    local curr = self.ai_helper.settings.entity_cat_locations ~= false
                                    self.ai_helper:saveSettings({ entity_cat_locations = not curr })
                                    if self.scanBookForEntities then self:scanBookForEntities(true) end
                                end
                            },
                            {
                                text = self.loc:t("entity_cat_terms") or "Terms",
                                checked_func = function()
                                    return self.ai_helper.settings.entity_cat_terms ~= false
                                end,
                                callback = function()
                                    local curr = self.ai_helper.settings.entity_cat_terms ~= false
                                    self.ai_helper:saveSettings({ entity_cat_terms = not curr })
                                    if self.scanBookForEntities then self:scanBookForEntities(true) end
                                end
                            },
                        }
                    }
                },
                separator = true,
            },
            {
                text = self.loc:t("menu_ai_settings"),
                keep_menu_open = true,
                sub_item_table = {
                    {
                        text = self.loc:t("menu_primary_ai_model") or "Primary AI Model",
                        keep_menu_open = true,
                        sub_item_table_func = function() return self:getAIModelSelectionMenu("primary") end
                    },
                    {
                        text = self.loc:t("menu_secondary_ai_model") or "Secondary AI Model",
                        keep_menu_open = true,
                        sub_item_table_func = function() return self:getAIModelSelectionMenu("secondary") end,
                    },
                    {
                        text = self.loc:t("menu_reasoning_effort") or "AI Reasoning Effort",
                        keep_menu_open = true,
                        callback = function() self:showReasoningEffortSettings() end,
                        separator = true,
                    },
                    {
                        is_api_keys = true,
                        text = self.loc:t("menu_api_keys") or "API Keys & Providers", 
                        keep_menu_open = true,
                        sub_item_table_func = function() return self:getAPIKeysMenu() end,
                        separator = true,
                    },
                    {
                        text = self.loc:t("menu_view_config") or "View All Config Values", 
                        keep_menu_open = true,
                        callback = function() self:showConfigSummary() end,
                    },
                }
            },
            {
                text = self.loc:t("menu_language") or "Language",
                keep_menu_open = true,
                callback = function() self:showLanguageSelection() end,
            }
        }
    })

    table.insert(items, {
        text = self.loc:t("menu_maintenance") or "Maintenance",
        keep_menu_open = true,
        sub_item_table = {
            {
                text = self.loc:t("menu_rebuild_xray") or "Rebuild X-Ray Data (Clean Fetch)",
                keep_menu_open = true,
                callback = function() self:confirmAndRebuildXRay() end,
                separator = true,
            },
            {
                text = self.loc:t("menu_clear_cache"),
                keep_menu_open = true,
                callback = function() self:clearCache() end,
            },
            {
                text = self.loc:t("menu_clear_logs") or "Clear Logs",
                keep_menu_open = true,
                callback = function() self:clearLogs() end,
            },
            {
                text = self.loc:t("menu_view_log") or "View Log",
                keep_menu_open = true,
                callback = function() self:viewLog() end,
            },
            {
                text = self.loc:t("menu_beta_channel") or "Beta Channel Settings",
                keep_menu_open = true,
                callback = function() self:showBetaChannelSettings() end,
            },
            {
                text = self.loc:t("updater_check") or "Check for Updates",
                keep_menu_open = true,
                callback = function()
                    local updater = require(plugin_path .. "xray_updater")
                    updater.checkForUpdates(self.loc, self.ai_helper.settings.beta_channel_enabled)
                end,
            },
        }
    })

    table.insert(items, {
        text = _t(self, "menu_about", "About X-Ray"),
        keep_menu_open = true,
        callback = function() self:showAbout() end,
    })

    self.current_xray_menu_table = items
    return items
end



function M:addToMainMenu(menu_items)
    menu_items.xray = {
        is_xray = true,
        text = _t(self, "menu_xray", "X-Ray"),

        sorting_hint = "tools",
        callback = function() self:showQuickXRayMenu() end,
        hold_callback = function() self:showFullXRayMenu() end,
        sub_item_table_func = function() return self:getSubMenuItems() end,
    }
end




return M
