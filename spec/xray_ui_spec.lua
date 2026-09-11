-- xray_ui_spec.lua
require("spec/spec_helper")
local xray_ui = require("xray_ui")

describe("xray_ui", function()
    local plugin

    before_each(function()
        plugin = createMockPlugin()
        -- Mix in UI methods
        for k, v in pairs(xray_ui) do
            plugin[k] = v
        end
        -- Reset UI tracker
        _G.ui_tracker.shown = {}
        _G.ui_tracker.last_shown = nil
        _G.ui_tracker.closed = {}
    end)

    describe("showLanguageSelection", function()
        it("should show a Menu with language options and correctly marked default checkbox", function()
            plugin:showLanguageSelection()
            local last = _G.ui_tracker.last_shown
            assert.is_not_nil(last)
            assert.are.equal("Menu", last.type)
            assert.are.equal("menu_language", last.args.title)
            
            -- Verify that the default option (Follow System) is checked [✓] and others are unchecked [  ]
            local follow_system_option = last.args.item_table[1]
            assert.truthy(follow_system_option.text:find("^%[✓%]"))
            
            local english_option
            for _, item in ipairs(last.args.item_table) do
                if item.text:find("English") then english_option = item; break end
            end
            assert.is_not_nil(english_option)
            assert.truthy(english_option.text:find("^%[%s*%]"))
        end)
    end)

    describe("closeAllMenus", function()
        it("should close active menus and set them to nil", function()
            plugin.char_menu = { type = "MockMenu" }
            plugin.xray_menu = { type = "MockMenu" }
            
            plugin:closeAllMenus()
            
            assert.is_nil(plugin.char_menu)
            assert.is_nil(plugin.xray_menu)
            -- Should have called UIManager:close twice for our menus
            -- Plus others in the list
            assert.is_true(#_G.ui_tracker.closed >= 2)
        end)
    end)

    describe("showCharacters", function()
        it("should show EntityListOverlay even if no characters", function()
            plugin.characters = {}
            plugin:showCharacters()
            local last = _G.ui_tracker.last_shown
            assert.are.equal("InputContainer", last.type)
            assert.truthy(last.title:find("menu_characters"))
            assert.are.equal(0, #last.raw_items)
        end)

        it("should show EntityListOverlay if characters exist", function()
            plugin.characters = { { name = "Alice", description = "Test" } }
            plugin:showCharacters()
            local last = _G.ui_tracker.last_shown
            assert.are.equal("InputContainer", last.type)
            assert.truthy(last.title:find("menu_characters"))
            -- Verify Alice is in items
            local found = false
            for _, item in ipairs(last.items or {}) do
                if (item.name or ""):find("Alice") then found = true; break end
            end
            assert.is_true(found)
        end)
    end)

    describe("showCharacterDetails", function()
        it("should show details dialog when popup toggles are false", function()
            plugin.ai_helper.settings.ui_popup_intext = false
            plugin.ai_helper.settings.ui_popup_menu = false
            plugin.ai_helper.settings.entity_ui_mode = nil
            local char = { name = "Bob", description = "A builder" }
            plugin:showCharacterDetails(char)
            local last = _G.ui_tracker.last_shown
            assert.is_not_nil(last)
            assert.are.equal("ButtonDialog", last.type)
            
            local function find_texts(w)
                local texts = {}
                local seen = {}
                local function traverse(node)
                    if not node or type(node) ~= "table" or seen[node] then return end
                    seen[node] = true
                    if node.type == "TextBoxWidget" and node.args and node.args.text then
                        table.insert(texts, node.args.text)
                    end
                    for k, v in pairs(node) do
                        if type(v) == "table" and k ~= "parent" then traverse(v) end
                    end
                    if node.args and type(node.args) == "table" then
                        for _, v in ipairs(node.args) do
                            if type(v) == "table" then traverse(v) end
                        end
                    end
                end
                traverse(w)
                return texts
            end

            local texts = find_texts(last)
            local name_found = false
            local desc_found = false
            for _, t in ipairs(texts) do
                if t:find("Bob") then name_found = true end
                if t:find("A builder") then desc_found = true end
            end
            assert.is_true(name_found)
            assert.is_true(desc_found)
        end)

        it("should show bottom popup when ui_popup toggles are true", function()
            plugin.ai_helper.settings.ui_popup_intext = true
            plugin.ai_helper.settings.ui_popup_menu = true
            plugin.ai_helper.settings.entity_ui_mode = nil
            local char = { name = "Bob", description = "A builder" }
            plugin:showCharacterDetails(char)
            local last = _G.ui_tracker.last_shown
            assert.is_not_nil(last)
            assert.are.equal("InputContainer", last.type)
        end)

        it("should show bottom popup and buttons when both linked_entries and mentions are enabled", function()
            plugin.ai_helper.settings.ui_popup_intext = true
            plugin.ai_helper.settings.ui_popup_menu = true
            plugin.ai_helper.settings.linked_entries_enabled = true
            plugin.ai_helper.settings.mentions_enabled = true
            plugin.findRelatedEntities = function() return { { name = "Related" } } end
            
            local char = { name = "Bob", description = "A builder" }
            -- This should not crash (RightContainer bug)
            plugin:showCharacterDetails(char)
            local last = _G.ui_tracker.last_shown
            assert.is_not_nil(last)
            assert.are.equal("InputContainer", last.type)
        end)

        it("should migrate legacy entity_ui_mode setting properly", function()
            plugin.ai_helper.settings.ui_popup_intext = nil
            plugin.ai_helper.settings.ui_popup_menu = nil
            plugin.ai_helper.settings.entity_ui_mode = "both"
            local char = { name = "Bob", description = "A builder" }
            plugin:showCharacterDetails(char)
            assert.is_true(plugin.ai_helper.settings.ui_popup_intext)
            assert.is_true(plugin.ai_helper.settings.ui_popup_menu)
            assert.is_nil(plugin.ai_helper.settings.entity_ui_mode)
        end)

        it("should format attributes horizontally without labels, except Alias", function()
            -- 1. Test modern footnote popup layout
            plugin.ai_helper.settings.ui_popup_intext = true
            plugin.ai_helper.settings.ui_popup_menu = true
            local char = {
                name = "Bob",
                aliases = { "Bobby" },
                role = "Protagonist",
                occupation = "Detective",
                gender = "Female",
                description = "A builder"
            }
            plugin:showCharacterDetails(char, { source = "in_text" })
            local last = _G.ui_tracker.last_shown
            assert.is_not_nil(last)
            
            -- Traverse and find text labels
            local function find_texts(w)
                local texts = {}
                local seen = {}
                local function traverse(node)
                    if not node or type(node) ~= "table" or seen[node] then return end
                    seen[node] = true
                    if node.type == "TextBoxWidget" and node.args and node.args.text then
                        table.insert(texts, node.args.text)
                    end
                    for k, v in pairs(node) do
                        if type(v) == "table" and k ~= "parent" then traverse(v) end
                    end
                    if node.args and type(node.args) == "table" then
                        for _, v in ipairs(node.args) do
                            if type(v) == "table" then traverse(v) end
                        end
                    end
                end
                traverse(w)
                return texts
            end

            local texts = find_texts(last)
            local combined_found = false
            local aliases_found = false
            for _, t in ipairs(texts) do
                if t:find("Protagonist | Detective | Female") then combined_found = true end
                if t:find("label_aliases: Bobby") then aliases_found = true end
                -- Verify individual labels are NOT present
                assert.is_nil(t:find("ROLE:"))
                assert.is_nil(t:find("GENDER:"))
                assert.is_nil(t:find("OCCUPATION:"))
            end
            assert.is_true(combined_found)
            assert.is_true(aliases_found)

            -- 2. Test classic full-screen dialog details view layout
            plugin.ai_helper.settings.ui_popup_menu = false
            plugin:showCharacterDetails(char, { source = "menu" })
            local dialog = _G.ui_tracker.last_shown
            assert.is_not_nil(dialog)
            assert.are.equal("ButtonDialog", dialog.type)
            
            local texts_classic = find_texts(dialog)
            local combined_found_classic = false
            local aliases_found_classic = false
            for _, t in ipairs(texts_classic) do
                if t:find("Protagonist | Detective | Female") then combined_found_classic = true end
                if t:find("label_aliases: Bobby") then aliases_found_classic = true end
                -- Verify individual labels are NOT present
                assert.is_nil(t:find("ROLE:"))
                assert.is_nil(t:find("GENDER:"))
                assert.is_nil(t:find("OCCUPATION:"))
            end
            assert.is_true(combined_found_classic)
            assert.is_true(aliases_found_classic)
        end)
    end)

    describe("showMergeFlow", function()
        it("should show primary picker dialog with modal = true and support back navigation", function()
            plugin.characters = { { name = "A" }, { name = "B" } }
            plugin:showMergeFlow(plugin.characters, "characters")
            local primary = _G.ui_tracker.last_shown
            assert.are.equal("ButtonDialog", primary.type)
            assert.are.equal("merge_pick_primary", primary.args.title)
            assert.is_true(primary.args.modal)
            assert.are.equal("left", primary.buttons[1][1].align)

            -- Pick primary item 'A' -> should show secondary dialog with modal = true
            local a_callback = primary.buttons[1][1].callback
            a_callback()
            local secondary = _G.ui_tracker.last_shown
            assert.are.equal("ButtonDialog", secondary.type)
            assert.are.equal("merge_pick_secondary", secondary.args.title)
            assert.is_true(secondary.args.modal)
            assert.are.equal("left", secondary.buttons[1][1].align)

            -- Click Back button in secondary dialog -> should re-show primary dialog with modal = true
            local back_callback = secondary.buttons[#secondary.buttons][1].callback
            back_callback()
            local re_primary = _G.ui_tracker.last_shown
            assert.are.equal("ButtonDialog", re_primary.type)
            assert.are.equal("merge_pick_primary", re_primary.args.title)
            assert.is_true(re_primary.args.modal)

            -- Pick 'A' again, then pick 'B' -> should show confirmation dialog with modal = true
            re_primary.buttons[1][1].callback()
            local secondary2 = _G.ui_tracker.last_shown
            local b_callback = secondary2.buttons[1][1].callback
            b_callback()
            local confirm = _G.ui_tracker.last_shown
            assert.are.equal("ButtonDialog", confirm.type)
            assert.is_true(confirm.args.modal)
        end)
    end)

    describe("showAIFindDuplicatesFlow", function()
        before_each(function()
            plugin.ai_helper = {
                hasApiKey = function() return true end,
                findDuplicates = function()
                    return {
                        { primary = "Jon", secondary = "John", reason = "Similar spelling" },
                        { primary = "Alice", secondary = "Bob", reason = "Different" }
                    }
                end,
                settings = {}
            }
            plugin.characters = {
                { name = "Jon", description = "Character 1" },
                { name = "John", description = "Character 2" },
                { name = "Alice", description = "Character 3" },
                { name = "Bob", description = "Character 4" }
            }
            plugin.ui = {
                document = {
                    file = "test_book.epub",
                    getProps = function() return { title = "Test", authors = "Author" } end,
                    getPageCount = function() return 100 end
                }
            }
            plugin.ui.getCurrentPage = function() return 10 end
            plugin.book_data = {}
            local loc_xray = require("localization_xray")
            plugin.loc = {
                t = function(self, key, ...)
                    return loc_xray:t(key, ...)
                end
            }
        end)

        it("should show ButtonDialog for duplicate pairs and support Reject", function()
            plugin:showAIFindDuplicatesFlow(plugin.characters, "characters", "characters")
            local last = _G.ui_tracker.last_shown
            assert.are.equal("ButtonDialog", last.type)
            assert.is_true(last.args.modal)
            
            -- Verify buttons: Merge, Skip, Reject, Stop
            local buttons = last.args.buttons[1]
            assert.are.equal(4, #buttons)
            assert.are.equal("Merge", buttons[1].text)
            assert.are.equal("Skip", buttons[2].text)
            assert.are.equal("Reject", buttons[3].text)
            assert.are.equal("Stop", buttons[4].text)

            -- Tap Reject
            local reject_cb = buttons[3].callback
            reject_cb()

            -- Verify it added the pair to rejected_merge_pairs in book_data
            assert.is_not_nil(plugin.book_data.rejected_merge_pairs)
            assert.is_true(plugin.book_data.rejected_merge_pairs["john|jon"])

            -- Run duplicate check again, the rejected pair should be filtered out
            _G.ui_tracker.shown = {}
            plugin:showAIFindDuplicatesFlow(plugin.characters, "characters", "characters")
            
            -- Only Alice vs Bob should be shown
            local dialog = _G.ui_tracker.last_shown
            assert.are.equal("ButtonDialog", dialog.type)
            assert.truthy(dialog.args.title:find("Alice") and dialog.args.title:find("Bob"))
        end)

        it("should walk pre-scanned duplicate pairs directly without calling AI", function()
            local called_ai = false
            plugin.ai_helper.findDuplicates = function()
                called_ai = true
                return {}
            end
            
            local pairs = {
                { primary = "Jon", secondary = "John", reason = "Similar spelling" }
            }
            plugin:walkDuplicatePairs(plugin.characters, "characters", pairs)
            
            assert.is_false(called_ai)
            local last = _G.ui_tracker.last_shown
            assert.are.equal("ButtonDialog", last.type)
            assert.truthy(last.args.title:find("Jon") and last.args.title:find("John"))
        end)
    end)

    describe("showTerms", function()
        it("should show EntityListOverlay even if no terms", function()
            plugin.terms = {}
            plugin:showTerms()
            local last = _G.ui_tracker.last_shown
            assert.are.equal("InputContainer", last.type)
            assert.truthy(last.title:find("menu_terms"))
            assert.are.equal(0, #last.raw_items)
        end)

        it("should show EntityListOverlay if terms exist", function()
            plugin.terms = { { name = "Muggle", definition = "Non-magical person" } }
            plugin:showTerms()
            local last = _G.ui_tracker.last_shown
            assert.are.equal("InputContainer", last.type)
            assert.truthy(last.title:find("menu_terms"))
            -- Verify Muggle is in items
            local found = false
            for _, item in ipairs(last.items or {}) do
                if (item.name or ""):find("Muggle") then found = true; break end
            end
            assert.is_true(found)
        end)
    end)

    describe("checkSeriesContext", function()
        it("should show ButtonDialog with three options if online and series detected", function()
            -- Mock NetworkMgr
            package.loaded["ui/network/manager"] = {
                isConnected = function() return true end,
                isOnline = function() return true end
            }
            -- Mock series manager detectSeries
            plugin.series_manager = {
                detectSeries = function()
                    return { name = "Mistborn", index = 2, slug = "mistborn" }
                end
            }
            plugin.ai_helper = {
                settings = {
                    series_context_enabled = true
                }
            }
            plugin.book_data = {}

            plugin:checkSeriesContext()

            local last = _G.ui_tracker.last_shown
            assert.is_not_nil(last)
            assert.are.equal("ButtonDialog", last.type)
            assert.is_true(last.args.title:find("series_context_prompt_title") ~= nil)
            
            -- Verify buttons structure (three options: Yes, Later, Don't ask again)
            local buttons = last.args.buttons[1]
            assert.are.equal(3, #buttons)
            assert.are.equal("yes", buttons[1].text)
            assert.are.equal("later", buttons[2].text)
            assert.are.equal("dont_ask_again", buttons[3].text)
        end)

        it("should cache check outcome and not show prompt if series index is 1", function()
            -- Mock NetworkMgr
            package.loaded["ui/network/manager"] = {
                isConnected = function() return true end,
                isOnline = function() return true end
            }
            -- Mock series manager detectSeries
            plugin.series_manager = {
                detectSeries = function()
                    return { name = "Mistborn", index = 1, slug = "mistborn" }
                end
            }
            plugin.ai_helper = {
                settings = {
                    series_context_enabled = true
                }
            }
            plugin.book_data = {}

            -- Mock cache_manager
            local asyncSave_called = false
            plugin.cache_manager = {
                loadCache = function() return {} end,
                asyncSaveCache = function(self_cm, file, data)
                    asyncSave_called = true
                end
            }

            plugin:checkSeriesContext()

            -- Dialog shouldn't have been shown since index <= 1
            local last = _G.ui_tracker.last_shown
            assert.is_nil(last)
            -- Verify cache was saved with series_context_dismissed = true
            assert.is_true(asyncSave_called)
            assert.is_true(plugin.book_data.series_context_dismissed)
        end)

        it("should automatically merge series context offline if all prior books are cached", function()
            -- Mock NetworkMgr as offline
            package.loaded["ui/network/manager"] = {
                isConnected = function() return false end,
                isOnline = function() return false end
            }
            local merge_called = false
            plugin.mergeSeriesContext = function(self_p, cache_data, series_info)
                merge_called = true
            end
            plugin.series_manager = {
                detectSeries = function()
                    return { name = "Mistborn", index = 2, slug = "mistborn" }
                end,
                loadSeriesCache = function(self_sm, slug)
                    return {
                        books = {
                            [1] = {
                                title = "The Final Empire",
                                timeline = { { chapter = "Ch 1", event = "Kelsier" } }
                            }
                        }
                    }
                end
            }
            plugin.ai_helper = {
                settings = {
                    series_context_enabled = true
                }
            }
            plugin.book_data = {}

            plugin:checkSeriesContext()

            assert.is_true(merge_called)
            -- Verify no popup prompt shown because it was merged automatically offline
            local last = _G.ui_tracker.last_shown
            assert.is_nil(last)
        end)
    end)

    describe("clearCache and clearSeriesCache", function()
        it("should reset all in-memory tables and flags on clearCache", function()
            plugin.characters = { { name = "Vin" } }
            plugin.locations = { { name = "Luthadel" } }
            plugin.timeline = { { chapter = "Ch 1", event = "Event" } }
            plugin.historical_figures = { { name = "Person" } }
            plugin.terms = { { name = "Allomancy" } }
            plugin.terms_fetched = true
            plugin.author_info = { name = "Author" }
            plugin.book_data = { series_context_loaded = true, series_slug = "mistborn" }
            plugin.series_context_loaded = true
            plugin.xray_mode_enabled = true

            local clear_file_called = false
            plugin.cache_manager = {
                clearCache = function(self_cm, file)
                    clear_file_called = true
                    return true
                end
            }

            plugin:clearCache()

            assert.is_true(clear_file_called)
            assert.are.equal(0, #plugin.characters)
            assert.are.equal(0, #plugin.locations)
            assert.are.equal(0, #plugin.timeline)
            assert.are.equal(0, #plugin.historical_figures)
            assert.are.equal(0, #plugin.terms)
            assert.is_false(plugin.terms_fetched)
            assert.is_nil(plugin.author_info)
            assert.is_false(plugin.series_context_loaded)
            assert.is_false(plugin.xray_mode_enabled)
            assert.are.same({}, plugin.book_data)
        end)

        it("should clear series cache file and flags on clearSeriesCache", function()
            plugin.series_manager = {
                detectSeries = function()
                    return { name = "Mistborn", index = 2, slug = "mistborn" }
                end,
                getSeriesCachePath = function(self_sm, slug)
                    return "/tmp/koreader/settings/xray/series/mistborn.lua"
                end
            }
            plugin.book_data = {
                series_context_loaded = true,
                series_context_dismissed = true,
                series_slug = "mistborn"
            }
            plugin.series_context_loaded = true

            plugin:clearSeriesCache()

            assert.is_false(plugin.series_context_loaded)
            assert.is_nil(plugin.book_data.series_context_loaded)
            assert.is_nil(plugin.book_data.series_context_dismissed)
        end)
    end)

    describe("scanBookForUnits", function()
        before_each(function()
            os.remove("spec/test_book.epub.sdr/xray_unit_cache.cache")
        end)

        after_each(function()
            os.remove("spec/test_book.epub.sdr/xray_unit_cache.cache")
        end)

        it("should successfully scan document and populate unit_xp_matches", function()
            local xray_unitscanner = require("xray_unitscanner")
            for k, v in pairs(xray_unitscanner) do
                plugin[k] = v
            end
            
            plugin.ai_helper = {
                settings = {
                    unit_converter_enabled = true,
                    unit_underline_enabled = true,
                    unit_underline_style = "solid",
                    unit_conversion_direction = "to_imperial",
                }
            }
            
            local mock_hits = {
                {
                    matched_text = "meters",
                    start = "xp1",
                    ["end"] = "xp2",
                    prev_text = "he walked five ",
                    next_text = " today."
                }
            }
            plugin.ui.document.findAllText = function(self_doc, pat, regex, contextWords, maxResults, returnXPointers)
                -- Only match when it queries the exact meters/metres batch regex pattern
                if pat:find("met") then
                    return mock_hits
                end
                return {}
            end
            plugin.ui.document.getPrevVisibleWordStart = function(self_doc, cand)
                if cand == "xp1" then return "xp_five" end
                return cand
            end
            plugin.ui.document.getTextFromXPointers = function(self_doc, cand, unit_end)
                if cand == "xp_five" and unit_end == "xp2" then return "five meters" end
                if cand == "xp_five" then return "five" end
                return ""
            end
            
            plugin:scanBookForUnits()
            assert.are.equal(1, #plugin.unit_xp_matches)
            assert.are.equal("xp_five", plugin.unit_xp_matches[1].start_xp)
            assert.are.equal("xp2", plugin.unit_xp_matches[1].end_xp)
            assert.are.equal("five meters", plugin.unit_xp_matches[1].original)
        end)

        it("should NOT match false positive '4 will' as a unit conversion", function()
            local xray_unitscanner = require("xray_unitscanner")
            for k, v in pairs(xray_unitscanner) do
                plugin[k] = v
            end
            
            plugin.ai_helper = {
                settings = {
                    unit_converter_enabled = true,
                    unit_underline_enabled = true,
                    unit_underline_style = "solid",
                    unit_conversion_direction = "to_imperial",
                }
            }
            
            local mock_hits = {
                {
                    matched_text = "l",
                    start = "xp1",
                    ["end"] = "xp2",
                    prev_text = "4 wil",
                    next_text = " "
                }
            }
            plugin.ui.document.findAllText = function(self_doc, pat, regex, contextWords, maxResults, returnXPointers)
                return mock_hits
            end
            plugin.ui.document.getPrevVisibleWordStart = function(self_doc, cand)
                if cand == "xp1" then return "xp_four" end
                return cand
            end
            plugin.ui.document.getTextFromXPointers = function(self_doc, cand, unit_end)
                if cand == "xp_four" and unit_end == "xp2" then return "4 will" end
                if cand == "xp_four" then return "4" end
                return ""
            end
            
            plugin:scanBookForUnits()
            assert.are.equal(0, #plugin.unit_xp_matches)
        end)

        it("should successfully scan '80 degrees Celcius' and populate unit_xp_matches", function()
            local xray_unitscanner = require("xray_unitscanner")
            for k, v in pairs(xray_unitscanner) do
                plugin[k] = v
            end
            
            plugin.ai_helper = {
                settings = {
                    unit_converter_enabled = true,
                    unit_underline_enabled = true,
                    unit_underline_style = "solid",
                    unit_conversion_direction = "to_imperial",
                }
            }
            
            local mock_hits = {
                {
                    matched_text = "degrees Celcius",
                    start = "xp1",
                    ["end"] = "xp2",
                    prev_text = "The liquid is at 80 ",
                    next_text = " today."
                }
            }
             plugin.ui.document.findAllText = function(self_doc, pat, regex, contextWords, maxResults, returnXPointers)
                 return mock_hits
             end
            plugin.ui.document.getPrevVisibleWordStart = function(self_doc, cand)
                if cand == "xp1" then return "xp_80" end
                return cand
            end
            plugin.ui.document.getTextFromXPointers = function(self_doc, cand, unit_end)
                if cand == "xp_80" and unit_end == "xp2" then return "80 degrees Celcius" end
                if cand == "xp_80" then return "80" end
                return ""
            end
            
            plugin:scanBookForUnits()
            assert.are.equal(1, #plugin.unit_xp_matches)
            assert.are.equal("xp_80", plugin.unit_xp_matches[1].start_xp)
            assert.are.equal("xp2", plugin.unit_xp_matches[1].end_xp)
            assert.are.equal("80 degrees Celcius", plugin.unit_xp_matches[1].original)
            assert.are.equal("176 °F", plugin.unit_xp_matches[1].converted)
        end)

        it("should successfully scan 'Two 25-liter' and treat it as 25 liters, not 2 liters", function()
            local xray_unitscanner = require("xray_unitscanner")
            for k, v in pairs(xray_unitscanner) do
                plugin[k] = v
            end
            
            plugin.ai_helper = {
                settings = {
                    unit_converter_enabled = true,
                    unit_underline_enabled = true,
                    unit_underline_style = "solid",
                    unit_conversion_direction = "to_imperial",
                }
            }
            
            local mock_hits = {
                {
                    matched_text = "liter",
                    start = "xp1",
                    ["end"] = "xp2",
                    prev_text = "He bought Two 25-",
                    next_text = " bottles."
                }
            }
            plugin.ui.document.findAllText = function(self_doc, pat, regex, contextWords, maxResults, returnXPointers)
                if pat:find("liter") or pat:find("litre") or pat:find("l") then
                    return mock_hits
                end
                return {}
            end
            plugin.ui.document.getPrevVisibleWordStart = function(self_doc, cand)
                if cand == "xp1" then return "xp_25" end
                return cand
            end
            plugin.ui.document.getTextFromXPointers = function(self_doc, cand, unit_end)
                if cand == "xp_25" and unit_end == "xp2" then return "25-liter" end
                if cand == "xp_25" then return "25" end
                return ""
            end
            
            plugin:scanBookForUnits()
            assert.are.equal(1, #plugin.unit_xp_matches)
            assert.are.equal("25-liter", plugin.unit_xp_matches[1].original)
            assert.are.equal("6.6 gallons", plugin.unit_xp_matches[1].converted)
        end)

        it("should successfully scan '37°C' with degree symbol", function()
            local xray_unitscanner = require("xray_unitscanner")
            for k, v in pairs(xray_unitscanner) do
                plugin[k] = v
            end
            
            plugin.ai_helper = {
                settings = {
                    unit_converter_enabled = true,
                    unit_underline_enabled = true,
                    unit_underline_style = "solid",
                    unit_conversion_direction = "to_imperial",
                }
            }
            
            local mock_hits = {
                {
                    matched_text = "°C",
                    start = "xp1",
                    ["end"] = "xp2",
                    prev_text = "The temperature is 37",
                    next_text = "."
                }
            }
            plugin.ui.document.findAllText = function(self_doc, pat, regex, contextWords, maxResults, returnXPointers)
                -- Verify regex pattern allows °C matching without leading word boundary
                assert.is_true(pat:find("°c") ~= nil)
                return mock_hits
            end
            plugin.ui.document.getPrevVisibleWordStart = function(self_doc, cand)
                if cand == "xp1" then return "xp_37" end
                return cand
            end
            plugin.ui.document.getTextFromXPointers = function(self_doc, cand, unit_end)
                if cand == "xp_37" and unit_end == "xp2" then return "37°C" end
                if cand == "xp_37" then return "37" end
                return ""
            end
            
            plugin:scanBookForUnits()
            assert.are.equal(1, #plugin.unit_xp_matches)
            assert.are.equal("37°C", plugin.unit_xp_matches[1].original)
            assert.are.equal("98.6 °F", plugin.unit_xp_matches[1].converted)
        end)

        it("should successfully scan and underline negative temperatures: '-37°C', '−37°C', '- 37°C'", function()
            local xray_unitscanner = require("xray_unitscanner")
            for k, v in pairs(xray_unitscanner) do
                plugin[k] = v
            end
            
            plugin.ai_helper = {
                settings = {
                    unit_converter_enabled = true,
                    unit_underline_enabled = true,
                    unit_underline_style = "solid",
                    unit_conversion_direction = "to_imperial",
                }
            }
            
            -- Test 1: ASCII minus
            local mock_hits1 = {
                {
                    matched_text = "°C",
                    start = "xp1",
                    ["end"] = "xp2",
                    prev_text = "The temperature is -37",
                    next_text = "."
                }
            }
            plugin.ui.document.findAllText = function(self_doc, pat)
                if pat:find("°c") then
                    return mock_hits1
                end
                return {}
            end
            plugin.ui.document.getPrevVisibleWordStart = function(self_doc, cand)
                if cand == "xp1" then return "xp_minus37" end
                return cand
            end
            plugin.ui.document.getTextFromXPointers = function(self_doc, cand, unit_end)
                if cand == "xp_minus37" and unit_end == "xp2" then return "-37°C" end
                if cand == "xp_minus37" then return "-37" end
                return ""
            end
            plugin:scanBookForUnits()
            assert.are.equal(1, #plugin.unit_xp_matches)
            assert.are.equal("-37°C", plugin.unit_xp_matches[1].original)
            assert.are.equal("-34.6 °F", plugin.unit_xp_matches[1].converted)

            -- Test 2: Unicode minus
            local mock_hits2 = {
                {
                    matched_text = "°C",
                    start = "xp1",
                    ["end"] = "xp2",
                    prev_text = "The temperature is −37",
                    next_text = "."
                }
            }
            plugin.ui.document.findAllText = function(self_doc, pat)
                if pat:find("°c") then
                    return mock_hits2
                end
                return {}
            end
            plugin.ui.document.getPrevVisibleWordStart = function(self_doc, cand)
                if cand == "xp1" then return "xp_uni37" end
                return cand
            end
            plugin.ui.document.getTextFromXPointers = function(self_doc, cand, unit_end)
                if cand == "xp_uni37" and unit_end == "xp2" then return "−37°C" end
                if cand == "xp_uni37" then return "−37" end
                return ""
            end
            plugin:scanBookForUnits()
            assert.are.equal(1, #plugin.unit_xp_matches)
            assert.are.equal("−37°C", plugin.unit_xp_matches[1].original)
            assert.are.equal("-34.6 °F", plugin.unit_xp_matches[1].converted)

            -- Test 3: Space after minus
            local mock_hits3 = {
                {
                    matched_text = "°C",
                    start = "xp1",
                    ["end"] = "xp2",
                    prev_text = "The temperature is - 37",
                    next_text = "."
                }
            }
            plugin.ui.document.findAllText = function(self_doc, pat)
                if pat:find("°c") then
                    return mock_hits3
                end
                return {}
            end
            plugin.ui.document.getPrevVisibleWordStart = function(self_doc, cand)
                if cand == "xp1" then return "xp_space37" end
                return cand
            end
            plugin.ui.document.getTextFromXPointers = function(self_doc, cand, unit_end)
                if cand == "xp_space37" and unit_end == "xp2" then return "- 37°C" end
                if cand == "xp_space37" then return "- 37" end
                return ""
            end
            plugin:scanBookForUnits()
            assert.are.equal(1, #plugin.unit_xp_matches)
            assert.are.equal("- 37°C", plugin.unit_xp_matches[1].original)
            assert.are.equal("-34.6 °F", plugin.unit_xp_matches[1].converted)
        end)

        it("should successfully convert 100 kg and 100 g correctly without collisions", function()
            local xray_unitscanner = require("xray_unitscanner")
            for k, v in pairs(xray_unitscanner) do
                plugin[k] = v
            end
            
            plugin.ai_helper = {
                settings = {
                    unit_converter_enabled = true,
                    unit_underline_enabled = true,
                    unit_underline_style = "solid",
                    unit_conversion_direction = "to_imperial",
                }
            }
            
            local mock_hits = {
                {
                    matched_text = "kg",
                    start = "xp1",
                    ["end"] = "xp2",
                    prev_text = "The package weighs 100 ",
                    next_text = " on scale."
                }
            }
            plugin.ui.document.findAllText = function(self_doc, pat, regex, contextWords, maxResults, returnXPointers)
                if pat:find("kg") or pat:find("kilo") then
                    return mock_hits
                end
                if pat:find("g\\b") or pat:find("gram") then
                    return {
                        {
                            matched_text = "g",
                            start = "xp_g",
                            ["end"] = "xp2",
                            prev_text = "The package weighs 100 k",
                            next_text = " on scale."
                        }
                    }
                end
                return {}
            end
            plugin.ui.document.getPrevVisibleWordStart = function(self_doc, cand)
                if cand == "xp1" then return "xp_100" end
                if cand == "xp_g" then return "xp_100_k" end
                return cand
            end
            plugin.ui.document.getTextFromXPointers = function(self_doc, cand, unit_end)
                if cand == "xp_100" and unit_end == "xp2" then return "100 kg" end
                if cand == "xp_100" then return "100" end
                if cand == "xp_100_k" and unit_end == "xp2" then return "100 kg" end
                if cand == "xp_100_k" then return "100 k" end
                return ""
            end
            
            plugin:scanBookForUnits()
            assert.are.equal(1, #plugin.unit_xp_matches)
            assert.are.equal("100 kg", plugin.unit_xp_matches[1].original)
            assert.are.equal("220.46 lb", plugin.unit_xp_matches[1].converted)
        end)

        it("should successfully convert 10 centimetres and .965 kg/l correctly", function()
            local xray_unitscanner = require("xray_unitscanner")
            for k, v in pairs(xray_unitscanner) do
                plugin[k] = v
            end
            
            plugin.ai_helper = {
                settings = {
                    unit_converter_enabled = true,
                    unit_underline_enabled = true,
                    unit_underline_style = "solid",
                    unit_conversion_direction = "to_imperial",
                }
            }
            
            plugin.ui.document.findAllText = function(self_doc, pat, regex, contextWords, maxResults, returnXPointers)
                return {
                    {
                        matched_text = "centimetres",
                        start = "xp_cm_start",
                        ["end"] = "xp_cm_end",
                        prev_text = "The line is 10 ",
                        next_text = " long."
                    },
                    {
                        matched_text = "kg",
                        start = "xp_kg_start",
                        ["end"] = "xp_kg_end",
                        prev_text = "The density is .965 ",
                        next_text = "/l."
                    }
                }
            end
            plugin.ui.document.getPrevVisibleWordStart = function(self_doc, cand)
                if cand == "xp_cm_start" then return "xp_10" end
                if cand == "xp_kg_start" then return "xp_965" end
                return cand
            end
            plugin.ui.document.compareXPointers = function(self_doc, xp1, xp2)
                if xp1 == xp2 then return 0 end
                local pos = {
                    xp_10 = 30,
                    xp_cm_end = 40,
                    xp_965 = 50,
                    xp_kg_end = 60,
                }
                local p1 = pos[xp1] or 0
                local p2 = pos[xp2] or 0
                if p1 < p2 then return 1 end
                if p1 > p2 then return -1 end
                if xp1 < xp2 then return 1 end
                return -1
            end
            plugin.ui.document.getTextFromXPointers = function(self_doc, cand, unit_end)
                if cand == "xp_10" and unit_end == "xp_cm_end" then return "10 centimetres" end
                if cand == "xp_10" then return "10" end
                if cand == "xp_965" and unit_end == "xp_kg_end" then return ".965 kg" end
                if cand == "xp_965" then return ".965" end
                return ""
            end
            
            plugin:scanBookForUnits()
            
            assert.are.equal(2, #plugin.unit_xp_matches)
            
            table.sort(plugin.unit_xp_matches, function(a, b) return a.original < b.original end)
            
            assert.are.equal(".965 kg", plugin.unit_xp_matches[1].original)
            assert.are.equal("2.13 lb", plugin.unit_xp_matches[1].converted)
            
            assert.are.equal("10 centimetres", plugin.unit_xp_matches[2].original)
            assert.are.equal("3.94 inches", plugin.unit_xp_matches[2].converted)
        end)
    end)
    describe("cache operations", function()
        local test_cache_file = "spec/tmp_test_cache.cache"

        before_each(function()
            os.remove(test_cache_file .. "_to_imperial")
            os.remove(test_cache_file .. "_to_metric")
        end)

        after_each(function()
            os.remove(test_cache_file .. "_to_imperial")
            os.remove(test_cache_file .. "_to_metric")
        end)

        it("should correctly save and load the tab-separated cache format", function()
            local xray_unitscanner = require("xray_unitscanner")
            for k, v in pairs(xray_unitscanner) do
                plugin[k] = v
            end

            plugin.ai_helper = {
                settings = {
                    unit_converter_enabled = true,
                    unit_underline_enabled = true,
                    unit_conversion_direction = "to_imperial",
                }
            }

            -- Mock _getUnitCachePath
            local original_getUnitCachePath = plugin._getUnitCachePath
            rawset(plugin, "_getUnitCachePath", function(this, resolved_dir)
                resolved_dir = resolved_dir or _getResolvedDirection(this)
                return test_cache_file .. "_" .. resolved_dir
            end)

            plugin.unit_xp_matches = {
                {
                    start_xp = "xp_1",
                    end_xp = "xp_2",
                    original = "10 cm",
                    converted = "3.94 inches",
                    category = "length"
                },
                {
                    start_xp = "xp_3",
                    end_xp = "xp_4",
                    original = "100\nkg",
                    converted = "220.46\r\nlb",
                    category = "weight"
                }
            }

            -- Save cache
            plugin:saveUnitCache()

            -- Verify file contents exist
            local f = io.open(test_cache_file .. "_to_imperial", "r")
            assert.is_not_nil(f)
            local lines = {}
            for line in f:lines() do
                table.insert(lines, line)
            end
            f:close()

            -- Signature version 31 + settings categories + 2 entries
            assert.are.equal(3, #lines)
            assert.is_true(lines[1]:find("^v30|") ~= nil)
            assert.are.equal("xp_1\txp_2\t10 cm\t3.94 inches\tlength", lines[2])
            assert.are.equal("xp_3\txp_4\t100 kg\t220.46  lb\tweight", lines[3])

            -- Clear and load cache
            plugin.unit_xp_matches = {}
            local loaded = plugin:loadUnitCache()
            assert.is_true(loaded)
            assert.are.equal(2, #plugin.unit_xp_matches)
            assert.are.equal("xp_1", plugin.unit_xp_matches[1].start_xp)
            assert.are.equal("3.94 inches", plugin.unit_xp_matches[1].converted)
            assert.are.equal("100 kg", plugin.unit_xp_matches[2].original)
            assert.are.equal("220.46  lb", plugin.unit_xp_matches[2].converted)
            assert.are.equal("weight", plugin.unit_xp_matches[2].category)

            -- Test signature mismatch invalidation (by checking file path mismatch)
            plugin.ai_helper.settings.unit_conversion_direction = "to_metric"
            local loaded_invalid = plugin:loadUnitCache()
            assert.is_false(loaded_invalid)
        end)
    end)

    describe("showAbout", function()
        it("should successfully initialize M.showAbout card overlay without throwing errors", function()
            local xray_settings_card = require("xray_settings_card")
            local success, err = pcall(function()
                xray_settings_card.showAbout(plugin, "Test Title", "This is a [B]test[/B] about text.")
            end)
            if not success then
                error(err)
            end
            
        end)
    end)

    describe("getAIModelSelectionMenu", function()
        it("should include new models at top of their provider lists", function()
            local menu_items = plugin:getAIModelSelectionMenu("primary")
            assert.is_not_nil(menu_items)
            assert.is_true(#menu_items > 0)

            -- Check for provider sub-menus
            local gemini_item, chatgpt_item, claude_item
            for _, item in ipairs(menu_items) do
                if item.text and item.text:find("Gemini") then gemini_item = item end
                if item.text and item.text:find("ChatGPT") then chatgpt_item = item end
                if item.text and item.text:find("Claude") then claude_item = item end
            end

            assert.is_not_nil(gemini_item)
            assert.is_not_nil(chatgpt_item)
            assert.is_not_nil(claude_item)

            local gemini_menu = gemini_item.sub_item_table_func()
            assert.is_not_nil(gemini_menu[1].text:find("gemini%-3%.7%-flash"))
            assert.is_not_nil(gemini_menu[2].text:find("gemini%-3%.6%-flash"))

            local chatgpt_menu = chatgpt_item.sub_item_table_func()
            assert.is_not_nil(chatgpt_menu[1].text:find("gpt%-5%.6%-terra"))
            assert.is_not_nil(chatgpt_menu[2].text:find("gpt%-5%.6%-luna"))

            local claude_menu = claude_item.sub_item_table_func()
            assert.is_not_nil(claude_menu[1].text:find("claude%-sonnet%-5"))
        end)
    end)

    describe("Welcome Screen & Onboarding Flow", function()
        it("should route showQuickXRayMenu to showWelcomeCard when no API key is set and cache is empty", function()
            plugin.ai_helper.hasApiKey = function() return false end
            plugin.book_data = nil
            plugin:showQuickXRayMenu()
            local last = _G.ui_tracker.last_shown
            assert.is_not_nil(last)
            assert.are.equal("InputContainer", last.type)
        end)

        it("should route showQuickXRayMenu to showFullXRayMenu when key is present", function()
            plugin.ai_helper.hasApiKey = function() return true end
            plugin:showQuickXRayMenu()
            local last = _G.ui_tracker.last_shown
            assert.is_not_nil(last)
            assert.are.equal("Menu", last.type)
        end)

        it("should render showConfigFileGuide dialog with import and wiki options", function()
            plugin:showConfigFileGuide()
            local last = _G.ui_tracker.last_shown
            assert.is_not_nil(last)
            assert.are.equal("InputContainer", last.type)
        end)

        it("should handle welcome actions appropriately", function()
            plugin:handleWelcomeAction("phone_pc")
            local last = _G.ui_tracker.last_shown
            assert.is_not_nil(last)

            plugin:handleWelcomeAction("ereader")
            local last_ereader = _G.ui_tracker.last_shown
            assert.is_not_nil(last_ereader)
            assert.are.equal("ButtonDialog", last_ereader.type)

            -- Test clicking a provider from the picker
            local gemini_btn = last_ereader.args.buttons[1][1]
            assert.is_not_nil(gemini_btn)
            gemini_btn.callback()
            local input_dlg = _G.ui_tracker.last_shown
            assert.is_not_nil(input_dlg)
            assert.are.equal("InputDialog", input_dlg.type)
        end)
    end)

    describe("Clear API Keys Menu", function()
        it("should validate all menu items in getAPIKeysMenu have valid non-nil text and working callbacks", function()
            local items = plugin:getAPIKeysMenu()
            assert.is_not_nil(items)
            
            for idx, item in ipairs(items) do
                assert.is_not_nil(item.text, "Item " .. idx .. " is missing a required text string")
                assert.are.equal("string", type(item.text), "Item " .. idx .. " text is not a string")
                assert.is_true(#item.text > 0, "Item " .. idx .. " has an empty text string")
                if item.text_func then
                    assert.are.equal("function", type(item.text_func))
                    local dynamic_text = item.text_func()
                    assert.is_not_nil(dynamic_text)
                    assert.are.equal("string", type(dynamic_text))
                    assert.is_true(#dynamic_text > 0)
                end
            end

            local clear_item = nil
            for _, item in ipairs(items) do
                if item.text:find("menu_clear_all_keys") or item.text:find("Clear All API Keys") then
                    clear_item = item
                    break
                end
            end
            assert.is_not_nil(clear_item)
            
            -- Trigger callback and check ButtonDialog is shown
            clear_item.callback()
            local last = _G.ui_tracker.last_shown
            assert.is_not_nil(last)
            assert.are.equal("ButtonDialog", last.type)
            local buttons = last.args.buttons[1]
            assert.is_not_nil(buttons)
            local clear_btn = buttons[2]
            assert.is_not_nil(clear_btn)
            assert.are.equal("function", type(clear_btn.callback))

            -- Execute clear button callback to ensure no crashes during clearing
            local ok, err = pcall(clear_btn.callback)
            assert.is_true(ok, "clear_all_keys callback failed: " .. tostring(err))
        end)

        it("should validate all menu items in getProviderKeySubMenu have valid non-nil text and working clear callback", function()
            local items = plugin:getProviderKeySubMenu("gemini", "Google Gemini")
            assert.is_not_nil(items)

            for idx, item in ipairs(items) do
                assert.is_not_nil(item.text, "Provider sub-item " .. idx .. " is missing a required text string")
                assert.are.equal("string", type(item.text), "Provider sub-item " .. idx .. " text is not a string")
                assert.is_true(#item.text > 0, "Provider sub-item " .. idx .. " has an empty text string")
                if item.text_func then
                    assert.are.equal("function", type(item.text_func))
                    local dynamic_text = item.text_func()
                    assert.is_not_nil(dynamic_text)
                    assert.are.equal("string", type(dynamic_text))
                    assert.is_true(#dynamic_text > 0)
                end
            end

            local clear_item = nil
            for _, item in ipairs(items) do
                if item.text:find("Clear") or item.text:find("menu_clear_single_key") then
                    clear_item = item
                    break
                end
            end
            assert.is_not_nil(clear_item)

            -- Trigger callback and check ButtonDialog is shown
            clear_item.callback()
            local last = _G.ui_tracker.last_shown
            assert.is_not_nil(last)
            assert.are.equal("ButtonDialog", last.type)
            local buttons = last.args.buttons[1]
            assert.is_not_nil(buttons)
            local clear_btn = buttons[2]
            assert.is_not_nil(clear_btn)
            assert.are.equal("function", type(clear_btn.callback))

            -- Execute clear button callback to ensure no crashes during clearing
            local ok, err = pcall(clear_btn.callback)
            assert.is_true(ok, "clear_single_key callback failed: " .. tostring(err))
        end)
    end)

    describe("showImageActions", function()
        it("should render image actions dialog without crashing and without unnecessary page resolution or cache saving", function()
            local img = {
                id = "map_01",
                title = "Roshar Map",
                page = 12,
                is_favorite = false,
                is_hidden = false,
            }
            local resolve_called = false
            local save_called = false
            plugin.image_manager = {
                resolveImagePage = function() resolve_called = true; return 12 end,
            }
            plugin.cache_manager = {
                asyncSaveCache = function() save_called = true end,
            }
            local ok, err = pcall(function()
                plugin:showImageActions(img)
            end)
            assert.is_true(ok, "showImageActions failed: " .. tostring(err))
            assert.is_false(resolve_called, "resolveImagePage should not be called when page is valid")
            assert.is_false(save_called, "asyncSaveCache should not be called on read-only menu open")
            local last = _G.ui_tracker.last_shown
            assert.is_not_nil(last)
            assert.are.equal("InputContainer", last.type)
        end)
    end)

    describe("showImages resume flow", function()
        it("should seamlessly resume minimized image when showImages is called without force_gallery", function()
            local resumed_entry = nil
            plugin.last_minimized_state = {
                image_entry = { id = "map_01", title = "Roshar Map", rotation = 90, zoom_level = 1.5, pan_x = 10, pan_y = 20 },
                file_path = "/tmp/map.png",
                rotation_angle = 90,
                zoom_level = 1.5,
                pan_x = 10,
                pan_y = 20,
            }
            plugin._launchImageViewer = function(self, entry, custom_state)
                resumed_entry = entry
            end

            plugin:showImages()
            assert.is_not_nil(resumed_entry)
            assert.are.equal("map_01", resumed_entry.id)
        end)

        it("should open image gallery when force_gallery is true even if minimized state exists", function()
            plugin.last_minimized_state = {
                image_entry = { id = "map_01", title = "Roshar Map" },
                file_path = "/tmp/map.png",
            }
            plugin.images = { { id = "map_01", title = "Roshar Map" } }
            plugin.book_data = { images = plugin.images }
            plugin.image_manager = {
                getFilteredImages = function() return plugin.images end,
                scanDocumentImages = function() return plugin.images end,
                extractImageToFile = function() return "/tmp/map.png" end,
            }

            plugin:showImages{ force_gallery = true }
            local last = _G.ui_tracker.last_shown
            assert.is_not_nil(last)
            assert.are.equal("InputContainer", last.type)
        end)
    end)

    describe("showImageActions", function()
        it("should open actions overlay and handle key events and in-place toggles without crash", function()
            local img_entry = { id = "img_test", title = "Map of Shire", page = 4, is_favorite = false }
            plugin.book_data = { images = { img_entry } }
            plugin.image_manager = {
                toggleFavorite = function(self, bd, id)
                    img_entry.is_favorite = not img_entry.is_favorite
                    return img_entry.is_favorite
                end,
                toggleHideImage = function(self, bd, id)
                    img_entry.is_hidden = not img_entry.is_hidden
                    return img_entry.is_hidden
                end,
            }

            local overlay = plugin:showImageActions(img_entry)
            assert.is_not_nil(overlay)
            assert.is_not_nil(overlay.onKeyPress)

            -- Initial focus is index 1 (Favorite)
            -- Test Return on Favorite action (idx 1)
            local res = overlay:onKeyPress({ key = "Return" })
            assert.is_true(res)
            assert.is_true(img_entry.is_favorite)

            -- Overlay should still be open (in-place update)
            assert.is_not_nil(overlay[1])

            -- Test Down arrow navigation to index 2 (Series)
            res = overlay:onKeyPress({ key = "Down" })
            assert.is_true(res)

            -- Test Up arrow navigation back to index 1 (Favorite)
            res = overlay:onKeyPress({ key = "Up" })
            assert.is_true(res)

            -- Toggle favorite back to false
            res = overlay:onKeyPress({ key = "Return" })
            assert.is_true(res)
            assert.is_false(img_entry.is_favorite)

            -- Test Close key (Escape)
            res = overlay:onKeyPress({ key = "Escape" })
            assert.is_true(res)
        end)

        it("should open rename dialog without crash", function()
            local img_entry = { id = "img_test", title = "Map of Shire", page = 4 }
            local renamed = false
            plugin.image_manager = {
                renameImage = function(self, bd, id, title)
                    img_entry.title = title
                    renamed = true
                end,
            }
            plugin:renameImageDialog(img_entry, function()
                renamed = true
            end)
            local last = _G.ui_tracker.last_shown
            assert.is_not_nil(last)
            assert.are.equal("InputDialog", last.type)
        end)

        it("should jump to image page via GotoPage event", function()
            local navigated_page = nil
            plugin.ui = {
                handleEvent = function(self, ev)
                    if ev and ev.name == "GotoPage" then
                        navigated_page = (type(ev.args) == "table" and ev.args[1]) or ev.args
                    end
                end,
            }
            plugin:jumpToImagePage(42)
            assert.are.equal(42, navigated_page)
        end)

        it("should invalidate gallery cached_pages and rebuild gallery immediately when hiding an image", function()
            local img_entry = { id = "img_hide_test", title = "Map of Mordor", page = 10, is_hidden = false }
            plugin.book_data = { images = { img_entry } }
            plugin.images = { img_entry }
            local gallery_rebuilt = false
            plugin.image_gallery_overlay = {
                cached_pages = { { img_entry } },
                buildUI = function(self)
                    gallery_rebuilt = true
                end,
            }
            plugin.image_manager = {
                toggleHideImage = function(self, bd, id)
                    img_entry.is_hidden = true
                    return true
                end,
            }

            local overlay = plugin:showImageActions(img_entry)
            assert.is_not_nil(overlay)

            -- Navigate down to Hide action (index 5)
            overlay:onKeyPress({ key = "Down" }) -- to index 1
            overlay:onKeyPress({ key = "Down" }) -- to index 2
            overlay:onKeyPress({ key = "Down" }) -- to index 3
            overlay:onKeyPress({ key = "Down" }) -- to index 4
            overlay:onKeyPress({ key = "Down" }) -- to index 5 (Hide)
            overlay:onKeyPress({ key = "Return" })

            assert.is_true(img_entry.is_hidden)
            assert.is_true(plugin.images[1].is_hidden)
            assert.is_nil(plugin.image_gallery_overlay.cached_pages)
            assert.is_true(gallery_rebuilt)
        end)
    end)

    describe("EntityListOverlay D-pad and non-touch navigation", function()
        local EntityListOverlay = require("xray_entity_list")

        it("starts with no initial focus highlight until D-pad is moved", function()
            local overlay = EntityListOverlay:new{
                plugin = plugin,
                mode = "characters",
                raw_items = {
                    { name = "Char 1", description = "Desc 1" },
                    { name = "Char 2", description = "Desc 2" },
                },
                is_touch_device = false,
            }
            -- Starts clean without any focus highlight
            assert.is_nil(overlay.focus_zone)
            assert.is_nil(overlay.focused_index)

            -- First D-pad press activates focus on cards 1
            overlay:onKeyPress("Down")
            assert.are.equal("cards", overlay.focus_zone)
            assert.are.equal(1, overlay.focused_index)
        end)

        it("navigates down and up through list items and zones with D-pad", function()
            local overlay = EntityListOverlay:new{
                plugin = plugin,
                mode = "characters",
                raw_items = {
                    { name = "Char 1", description = "Desc 1" },
                    { name = "Char 2", description = "Desc 2" },
                },
                is_touch_device = false,
            }
            -- First Down activates cards 1
            overlay:onKeyPress("Down")
            assert.are.equal("cards", overlay.focus_zone)
            assert.are.equal(1, overlay.focused_index)

            -- Second Down moves to cards 2
            overlay:onKeyPress("Down")
            assert.are.equal("cards", overlay.focus_zone)
            assert.are.equal(2, overlay.focused_index)

            -- Down from last card goes to footer
            overlay:onKeyPress("Down")
            assert.are.equal("footer", overlay.focus_zone)
            assert.are.equal(2, overlay.footer_focus_idx)

            -- Down from footer goes to header
            overlay:onKeyPress("Down")
            assert.are.equal("header", overlay.focus_zone)
            assert.are.equal(1, overlay.header_focus_idx)

            -- Down from header goes back to cards 1
            overlay:onKeyPress("Down")
            assert.are.equal("cards", overlay.focus_zone)
            assert.are.equal(1, overlay.focused_index)

            -- Up from cards 1 goes to header
            overlay:onKeyPress("Up")
            assert.are.equal("header", overlay.focus_zone)
            assert.are.equal(1, overlay.header_focus_idx)

            -- Up from header goes to footer
            overlay:onKeyPress("Up")
            assert.are.equal("footer", overlay.focus_zone)

            -- Up from footer goes to bottom card
            overlay:onKeyPress("Up")
            assert.are.equal("cards", overlay.focus_zone)
            assert.are.equal(2, overlay.focused_index)
        end)

        it("allows opening selected item with Return / Enter", function()
            local selected_item = nil
            plugin.showCharacterDetails = function(self, char)
                selected_item = char
            end

            local overlay = EntityListOverlay:new{
                plugin = plugin,
                mode = "characters",
                raw_items = {
                    { name = "Char 1", description = "Desc 1" },
                    { name = "Char 2", description = "Desc 2" },
                },
                is_touch_device = false,
            }
            overlay:onKeyPress("Down") -- activates Char 1
            overlay:onKeyPress("Down") -- moves to Char 2
            overlay:onKeyPress("Return")
            assert.is_not_nil(selected_item)
            assert.are.equal("Char 2", selected_item.name)
        end)

        it("supports direct number hotkeys 1-9 to select items", function()
            local selected_item = nil
            plugin.showCharacterDetails = function(self, char)
                selected_item = char
            end

            local overlay = EntityListOverlay:new{
                plugin = plugin,
                mode = "characters",
                raw_items = {
                    { name = "Alpha", description = "First" },
                    { name = "Beta", description = "Second" },
                },
                is_touch_device = false,
            }
            overlay:onKeyPress("2")
            assert.is_not_nil(selected_item)
            assert.are.equal("Beta", selected_item.name)
        end)

        it("navigates header buttons with Left and Right D-pad", function()
            local overlay = EntityListOverlay:new{
                plugin = plugin,
                mode = "characters",
                raw_items = { { name = "Alpha", description = "First" } },
                is_touch_device = false,
            }
            -- First Down activates cards
            overlay:onKeyPress("Down")
            -- Move focus to header
            overlay:onKeyPress("Up")
            assert.are.equal("header", overlay.focus_zone)
            assert.are.equal(1, overlay.header_focus_idx)

            -- Right moves through header buttons
            overlay:onKeyPress("Right")
            assert.are.equal(2, overlay.header_focus_idx)
            overlay:onKeyPress("Right")
            assert.are.equal(3, overlay.header_focus_idx)

            -- Left moves back
            overlay:onKeyPress("Left")
            assert.are.equal(2, overlay.header_focus_idx)
        end)

        it("navigates footer buttons with Left and Right D-pad", function()
            local overlay = EntityListOverlay:new{
                plugin = plugin,
                mode = "characters",
                raw_items = { { name = "Alpha", description = "First" } },
                is_touch_device = false,
            }
            -- First Down activates cards 1
            overlay:onKeyPress("Down")
            -- Second Down moves from last card to footer
            overlay:onKeyPress("Down")
            assert.are.equal("footer", overlay.focus_zone)
            assert.are.equal(2, overlay.footer_focus_idx)

            -- Right moves to next button (idx 3)
            overlay:onKeyPress("Right")
            assert.are.equal(3, overlay.footer_focus_idx)

            -- Left moves to page button (idx 2)
            overlay:onKeyPress("Left")
            assert.are.equal(2, overlay.footer_focus_idx)

            -- Left moves to prev button (idx 1)
            overlay:onKeyPress("Left")
            assert.are.equal(1, overlay.footer_focus_idx)
        end)

        it("triggers shortcuts for search, sort, and merge", function()
            local overlay = EntityListOverlay:new{
                plugin = plugin,
                mode = "characters",
                raw_items = { { name = "Alpha", description = "First" } },
                is_touch_device = false,
            }
            local search_called = false
            overlay.showSearchDialog = function() search_called = true; return true end
            overlay:handleEvent({ type = "Key", key = "f" })
            assert.is_true(search_called)

            local sort_called = false
            overlay.showSortDialog = function() sort_called = true; return true end
            overlay:handleEvent({ type = "Key", key = "s" })
            assert.is_true(sort_called)

            local merge_called = false
            overlay.showMergeDialog = function() merge_called = true; return true end
            overlay:handleEvent({ type = "Key", key = "m" })
            assert.is_true(merge_called)
        end)

        it("renders entity row with 22pt title and 15pt description to match native menus", function()
            local Font = require("ui/font")
            local old_getFace = Font.getFace
            local font_calls = {}
            Font.getFace = function(self, face, size)
                table.insert(font_calls, { face = face, size = size })
                return { face = face, size = size }
            end

            local overlay = EntityListOverlay:new{
                plugin = plugin,
                mode = "characters",
                raw_items = { { name = "Hero", description = "Protagonist" } },
                is_touch_device = false,
            }

            local row = overlay:renderRow({ name = "Hero", description = "Protagonist" }, 600, 64, false, 1)

            Font.getFace = old_getFace

            local has_22 = false
            local has_15 = false
            for _, fc in ipairs(font_calls) do
                if fc.size == 22 then has_22 = true end
                if fc.size == 15 then has_15 = true end
            end
            assert.is_true(has_22, "Expected title font size 22")
            assert.is_true(has_15, "Expected description font size 15")
        end)

        it("creates sort dialog with left-aligned radio buttons", function()
            local shown_dialog
            local UIManager = require("ui/uimanager")
            local old_show = UIManager.show
            UIManager.show = function(self, widget)
                shown_dialog = widget
            end

            local overlay = EntityListOverlay:new{
                plugin = plugin,
                mode = "characters",
                raw_items = { { name = "Hero", description = "Protagonist" } },
                is_touch_device = false,
            }

            overlay:showSortDialog()
            UIManager.show = old_show

            assert.is_not_nil(shown_dialog)
            assert.are.equal("ButtonDialog", shown_dialog.type)
            local btns = shown_dialog.args.buttons
            -- 3 sort choices should have align = "left"
            assert.are.equal("left", btns[1][1].align)
            assert.are.equal("left", btns[2][1].align)
            assert.are.equal("left", btns[3][1].align)
            -- Cancel button has default center alignment (nil)
            assert.is_nil(btns[4][1].align)
        end)
    end)

    describe("EntityListOverlay prior books styling and timeline distinction", function()
        local EntityListOverlay = require("xray_entity_list")

        it("renders prior books as inset cards without negative page numbers in timeline", function()
            local mock_plugin = {
                loc = { t = function(self, k) return nil end },
                book_data = { book_title = "Lethal White" },
            }
            local overlay = EntityListOverlay:new{
                plugin = mock_plugin,
                mode = "timeline",
                raw_items = {
                    { chapter = "[Book 1: The Cuckoo's Calling]", event = "Strike takes a case", page = -999, source = "series_prior", source_book = 1 },
                    { chapter = "[Book 2: The Silkworm]", event = "Quine disappears", page = -998, source = "series_prior", source_book = 2 },
                    { chapter = "Prologue", event = "Opening scene", page = 11 },
                },
                prior_collapsed = false,
                is_touch_device = false,
            }

            -- Check display items structure
            assert.is_true(overlay.current_page_items[1].is_prior_header)
            assert.are.equal(2, overlay.current_page_items[1].count)
            assert.are.equal("series_prior", overlay.current_page_items[2].source)
            assert.are.equal("series_prior", overlay.current_page_items[3].source)
            assert.is_true(overlay.current_page_items[4].is_current_header)
            assert.is_true(overlay.current_page_items[4].title:find("Lethal White") ~= nil)
            assert.are.equal("Prologue", overlay.current_page_items[5].chapter)

            -- Render prior book row and verify no negative page number is included
            local prior_widget = overlay:renderRow(overlay.current_page_items[2], 600, 64, false, 2)
            assert.is_not_nil(prior_widget)
            local function collectTexts(w, out, visited)
                out = out or {}
                visited = visited or {}
                if not w or type(w) ~= "table" or visited[w] then return out end
                visited[w] = true
                if w.text and type(w.text) == "string" then
                    table.insert(out, w.text)
                end
                if w.args and type(w.args) == "table" then
                    if w.args.text and type(w.args.text) == "string" then
                        table.insert(out, w.args.text)
                    end
                    collectTexts(w.args, out, visited)
                end
                for k, v in pairs(w) do
                    if k ~= "overlay" and k ~= "parent" and type(v) == "table" then
                        collectTexts(v, out, visited)
                    end
                end
                return out
            end

            local prior_texts = collectTexts(prior_widget)
            for _, txt in ipairs(prior_texts) do
                assert.is_nil(txt:match("%-999"))
                assert.is_nil(txt:match("%-998"))
            end
            local found_b1 = false
            local found_recap = false
            for _, txt in ipairs(prior_texts) do
                if txt:find("Book 1") then found_b1 = true end
                if txt == "Recap" then found_recap = true end
            end
            assert.is_true(found_b1)
            assert.is_true(found_recap)

            -- Render current book row and verify normal page is present
            local current_widget = overlay:renderRow(overlay.current_page_items[5], 600, 64, false, 5)
            assert.is_not_nil(current_widget)
            local current_texts = collectTexts(current_widget)
            local has_p11 = false
            for _, txt in ipairs(current_texts) do
                if txt:find("%(p%. 11%)") then has_p11 = true end
            end
            assert.is_true(has_p11)
        end)

        it("hides prior book cards and current book header when collapsed", function()
            local mock_plugin = {
                loc = { t = function(self, k) return nil end },
                book_data = { book_title = "Lethal White" },
            }
            local overlay = EntityListOverlay:new{
                plugin = mock_plugin,
                mode = "timeline",
                raw_items = {
                    { chapter = "[Book 1: The Cuckoo's Calling]", event = "Strike takes a case", page = -999, source = "series_prior", source_book = 1 },
                    { chapter = "Prologue", event = "Opening scene", page = 11 },
                },
                prior_collapsed = true,
                is_touch_device = false,
            }

            -- Page items should only have prior header and prologue (no current header, no prior books)
            assert.are.equal(2, #overlay.current_page_items)
            assert.is_true(overlay.current_page_items[1].is_prior_header)
            assert.are.equal("Prologue", overlay.current_page_items[2].chapter)
        end)

        it("renders series pill badge for prior characters in characters mode", function()
            local mock_plugin = {
                loc = { t = function(self, k) return nil end },
            }
            local overlay = EntityListOverlay:new{
                plugin = mock_plugin,
                mode = "characters",
                raw_items = {
                    { name = "Kelsier", description = "Survivor of Hathsin", source = "series_prior" },
                },
                is_touch_device = false,
            }

            local row_widget = overlay:renderRow(overlay.current_page_items[1], 600, 64, false, 1)
            assert.is_not_nil(row_widget)

            local function collectTexts(w, out, visited)
                out = out or {}
                visited = visited or {}
                if not w or type(w) ~= "table" or visited[w] then return out end
                visited[w] = true
                if w.text and type(w.text) == "string" then
                    table.insert(out, w.text)
                end
                if w.args and type(w.args) == "table" then
                    if w.args.text and type(w.args.text) == "string" then
                        table.insert(out, w.args.text)
                    end
                    collectTexts(w.args, out, visited)
                end
                for k, v in pairs(w) do
                    if k ~= "overlay" and k ~= "parent" and type(v) == "table" then
                        collectTexts(v, out, visited)
                    end
                end
                return out
            end

            local texts = collectTexts(row_widget)
            local found_raw_prior_in_title = false
            local found_series_pill = false
            for _, txt in ipairs(texts) do
                if txt == "Kelsier [Prior]" then
                    found_raw_prior_in_title = true
                end
                if txt == "Series" then
                    found_series_pill = true
                end
            end
            assert.is_false(found_raw_prior_in_title)
            assert.is_true(found_series_pill)
        end)
    end)

    describe("XRayBottomPopup rebuild & font fallback resilience", function()
        it("constructs and rebuilds cleanly without recursion or C stack overflow", function()
            plugin.ai_helper = {
                settings = { ui_popup_intext = true }
            }
            local log_count = 0
            plugin.log = function(self, msg)
                log_count = log_count + 1
            end

            local item = {
                name = "Harry Potter",
                description = "The boy who lived.",
                role = "Protagonist",
            }
            local ok, err = pcall(function()
                plugin:showCharacterDetails(item, { source = "in_text" })
            end)
            assert.is_true(ok)
            assert.is_nil(err)
            assert.is_not_nil(plugin.active_details_dialog)
            assert.are.equal(0, log_count)

            -- Test next/prev button navigation rebuilds without error
            local popup = plugin.active_details_dialog
            if popup.onNextButton then
                local next_ok = pcall(function() popup:onNextButton() end)
                assert.is_true(next_ok)
            end
            if popup.onPrevButton then
                local prev_ok = pcall(function() popup:onPrevButton() end)
                assert.is_true(prev_ok)
            end
        end)

        it("gracefully falls back to cfont if font lookup fails during rebuild", function()
            plugin.ai_helper = {
                settings = { ui_popup_intext = true }
            }
            local log_messages = {}
            plugin.log = function(self, msg)
                table.insert(log_messages, msg)
            end

            -- Simulate font failure on first attempt by making Font:getFace throw an error once
            local Font = require("ui/font")
            local old_getFace = Font.getFace
            local fail_first = true
            Font.getFace = function(self, face, size, index)
                if fail_first then
                    fail_first = false
                    error("Mocked font file missing")
                end
                return old_getFace(self, face, size, index)
            end

            local item = {
                name = "Hermione Granger",
                description = "Clever witch",
            }
            local ok, err = pcall(function()
                plugin:showCharacterDetails(item, { source = "in_text" })
            end)

            Font.getFace = old_getFace
            assert.is_true(ok)
            assert.is_nil(err)
            assert.is_not_nil(plugin.active_details_dialog)
            assert.is_true(#log_messages >= 1)
            assert.is_true(log_messages[1]:find("retrying with cfont fallback") ~= nil)
        end)
    end)

    describe("Linked entries modernization & z-order dialog management", function()
        it("should close active_details_dialog when showRelatedEntities is called", function()
            local mock_dlg = { type = "ButtonDialog" }
            plugin.active_details_dialog = mock_dlg
            local related = {
                { item = { name = "Shallan", description = "Lightweaver" }, type = "character" }
            }
            plugin:showRelatedEntities(related)

            assert.is_nil(plugin.active_details_dialog)
            assert.is_not_nil(plugin.active_related_menu)
            assert.are.equal("InputContainer", plugin.active_related_menu.type)
            assert.are.equal("linked_entries", plugin.active_related_menu.mode)
            assert.truthy(plugin.active_related_menu.title:find("linked_entries"))
        end)

        it("should close previous active_related_menu when showRelatedEntities is called again", function()
            local related1 = {
                { item = { name = "Shallan", description = "Lightweaver" }, type = "character" }
            }
            plugin:showRelatedEntities(related1)
            local first_menu = plugin.active_related_menu
            assert.is_not_nil(first_menu)

            local related2 = {
                { item = { name = "Jasnah", description = "Scholar" }, type = "character" }
            }
            plugin:showRelatedEntities(related2)
            assert.are_not.equal(first_menu, plugin.active_related_menu)
            assert.are.equal("linked_entries", plugin.active_related_menu.mode)
        end)

        it("should close active_related_menu when closeAllMenus is called", function()
            local related = {
                { item = { name = "Dalinar", description = "Bondsmith" }, type = "character" }
            }
            plugin:showRelatedEntities(related)
            assert.is_not_nil(plugin.active_related_menu)

            plugin:closeAllMenus()
            assert.is_nil(plugin.active_related_menu)
        end)

        it("should dismiss active_details_dialog when tapping Linked Entries button in character details", function()
            plugin.ai_helper.settings.ui_popup_intext = false
            plugin.ai_helper.settings.ui_popup_menu = false
            plugin.findRelatedEntities = function()
                return { { item = { name = "Adolin", description = "Duelist" }, type = "character" } }
            end
            local char = { name = "Kaladin", description = "Windrunner" }
            plugin:showCharacterDetails(char, { source = "menu" })

            local dlg = plugin.active_details_dialog
            assert.is_not_nil(dlg)

            -- Find the Linked Entries button in dlg.buttons
            local linked_btn = nil
            for _, row in ipairs(dlg.buttons or {}) do
                for _, btn in ipairs(row) do
                    if (btn.text and (btn.text:find("linked_entries") or btn.text == "Linked Entries")) then
                        linked_btn = btn
                        break
                    end
                end
            end
            assert.is_not_nil(linked_btn)
            linked_btn.callback()

            assert.is_nil(plugin.active_details_dialog)
            assert.is_not_nil(plugin.active_related_menu)
            assert.are.equal("linked_entries", plugin.active_related_menu.mode)
            assert.are.equal("Kaladin", plugin.active_related_menu.entity.name)
            assert.truthy(plugin.active_related_menu.title:find("Kaladin"))
        end)

        it("should render EntityListOverlay in linked_entries mode with Storefront card styling and type badges", function()
            local EntityListOverlay = require("xray_entity_list")
            local raw = {
                { item = { name = "Urithiru", description = "Ancient tower city", source = "series_prior" }, type = "location" },
                { item = { name = "Spren", definition = "Spirits of Roshar" }, type = "term" },
                { item = { name = "Gavilar", biography = "Late king" }, type = "historical" },
            }
            local overlay = EntityListOverlay:new{
                plugin = plugin,
                mode = "linked_entries",
                raw_items = raw,
            }
            assert.are.equal(3, #overlay.items)
            assert.are.equal(1, overlay.total_pages)

            -- Check search filtering
            overlay.search_query = "tower"
            overlay:prepareItems()
            assert.are.equal(1, #overlay.items)
            assert.are.equal("Urithiru", overlay.items[1].item.name)

            -- Check search clear
            overlay.search_query = nil
            overlay:prepareItems()
            assert.are.equal(3, #overlay.items)

            -- Check alphabetical sorting
            overlay.sort_mode = "alphabetical"
            overlay:prepareItems()
            assert.are.equal("Gavilar", overlay.items[1].item.name)
            assert.are.equal("Spren", overlay.items[2].item.name)
            assert.are.equal("Urithiru", overlay.items[3].item.name)
        end)

        it("should dispatch onItemSelect to appropriate detail method", function()
            local EntityListOverlay = require("xray_entity_list")
            local shown_type = nil
            local shown_item = nil
            plugin.showCharacterDetails = function(self, it, opts) shown_type = "character"; shown_item = it end
            plugin.showLocationDetails = function(self, it, opts) shown_type = "location"; shown_item = it end
            plugin.showHistoricalFigureDetails = function(self, it, opts) shown_type = "historical"; shown_item = it end
            plugin.showTermDetails = function(self, it, opts) shown_type = "term"; shown_item = it end

            local overlay = EntityListOverlay:new{
                plugin = plugin,
                mode = "linked_entries",
                raw_items = {},
            }

            overlay:onItemSelect({ item = { name = "Sadeas" }, type = "character" })
            assert.are.equal("character", shown_type)
            assert.are.equal("Sadeas", shown_item.name)

            overlay:onItemSelect({ item = { name = "Kholinar" }, type = "location" })
            assert.are.equal("location", shown_type)
            assert.are.equal("Kholinar", shown_item.name)

            overlay:onItemSelect({ item = { name = "Sunmaker" }, type = "historical" })
            assert.are.equal("historical", shown_type)
            assert.are.equal("Sunmaker", shown_item.name)

            overlay:onItemSelect({ item = { name = "Highstorm" }, type = "term" })
            assert.are.equal("term", shown_type)
            assert.are.equal("Highstorm", shown_item.name)
        end)

        it("should revert cleanly between frequency, alphabetical, and appearance sorting", function()
            local EntityListOverlay = require("xray_entity_list")
            local raw_chars = {
                { name = "Vin", sort_order = 1, mentions = { { page = 12 }, { page = 25 } } },
                { name = "Kelsier", sort_order = 2, mentions = { { page = 5 } } },
                { name = "Elend", sort_order = 3, history = { { page = 80 } } },
                { name = "Sazed", sort_order = 4, mentions = { { page = 60 } } },
                { name = "Breeze", sort_order = 5, mentions = { { page = 45 } } },
            }
            local overlay = EntityListOverlay:new{
                plugin = plugin,
                mode = "characters",
                raw_items = raw_chars,
            }

            -- Initial default is frequency: Vin (2 mentions), Kelsier (1), Sazed (1), Breeze (1), Elend (0)
            assert.are.equal("Vin", overlay.items[1].name)
            assert.are.equal("Kelsier", overlay.items[2].name)
            assert.are.equal("Sazed", overlay.items[3].name)
            assert.are.equal("Breeze", overlay.items[4].name)
            assert.are.equal("Elend", overlay.items[5].name)

            -- Switch to Alphabetical
            overlay.sort_mode = "alphabetical"
            overlay:prepareItems()
            assert.are.equal("Breeze", overlay.items[1].name)
            assert.are.equal("Elend", overlay.items[2].name)
            assert.are.equal("Kelsier", overlay.items[3].name)
            assert.are.equal("Sazed", overlay.items[4].name)
            assert.are.equal("Vin", overlay.items[5].name)

            -- Switch back to Frequency: MUST revert cleanly!
            overlay.sort_mode = "frequency"
            overlay:prepareItems()
            assert.are.equal("Vin", overlay.items[1].name)
            assert.are.equal("Kelsier", overlay.items[2].name)
            assert.are.equal("Sazed", overlay.items[3].name)
            assert.are.equal("Breeze", overlay.items[4].name)
            assert.are.equal("Elend", overlay.items[5].name)

            -- Switch to Appearance: Kelsier (pg 5), Vin (pg 12), Breeze (pg 45), Sazed (pg 60), Elend (pg 80)
            overlay.sort_mode = "appearance"
            overlay:prepareItems()
            assert.are.equal("Kelsier", overlay.items[1].name)
            assert.are.equal("Vin", overlay.items[2].name)
            assert.are.equal("Breeze", overlay.items[3].name)
            assert.are.equal("Sazed", overlay.items[4].name)
            assert.are.equal("Elend", overlay.items[5].name)

            -- Switch to Alphabetical again
            overlay.sort_mode = "alphabetical"
            overlay:prepareItems()
            assert.are.equal("Breeze", overlay.items[1].name)

            -- Switch back to Appearance: MUST revert cleanly!
            overlay.sort_mode = "appearance"
            overlay:prepareItems()
            assert.are.equal("Kelsier", overlay.items[1].name)
            assert.are.equal("Vin", overlay.items[2].name)
            assert.are.equal("Breeze", overlay.items[3].name)
            assert.are.equal("Sazed", overlay.items[4].name)
            assert.are.equal("Elend", overlay.items[5].name)
        end)

        it("should revert cleanly for entities without sort_order or mentions (locations, terms)", function()
            local EntityListOverlay = require("xray_entity_list")
            local raw_locs = {
                { name = "Luthadel" },
                { name = "Kredik Shaw" },
                { name = "Urithiru" },
                { name = "Kharbranth" },
            }
            local overlay = EntityListOverlay:new{
                plugin = plugin,
                mode = "locations",
                raw_items = raw_locs,
            }

            -- Initial default frequency preserves natural list order
            assert.are.equal("Luthadel", overlay.items[1].name)
            assert.are.equal("Kredik Shaw", overlay.items[2].name)
            assert.are.equal("Urithiru", overlay.items[3].name)
            assert.are.equal("Kharbranth", overlay.items[4].name)

            -- Switch to Alphabetical
            overlay.sort_mode = "alphabetical"
            overlay:prepareItems()
            assert.are.equal("Kharbranth", overlay.items[1].name)
            assert.are.equal("Kredik Shaw", overlay.items[2].name)
            assert.are.equal("Luthadel", overlay.items[3].name)
            assert.are.equal("Urithiru", overlay.items[4].name)

            -- Switch back to Frequency: MUST revert to natural list order!
            overlay.sort_mode = "frequency"
            overlay:prepareItems()
            assert.are.equal("Luthadel", overlay.items[1].name)
            assert.are.equal("Kredik Shaw", overlay.items[2].name)
            assert.are.equal("Urithiru", overlay.items[3].name)
            assert.are.equal("Kharbranth", overlay.items[4].name)
        end)

        it("should respect sort_order when _sort_score is 0 or equal", function()
            local EntityListOverlay = require("xray_entity_list")
            local zero_scores = {
                { name = "Vin", _sort_score = 0, sort_order = 1 },
                { name = "Kelsier", _sort_score = 0, sort_order = 2 },
                { name = "Elend", _sort_score = 0, sort_order = 3 },
                { name = "Sazed", _sort_score = 0, sort_order = 4 },
                { name = "Breeze", _sort_score = 0, sort_order = 5 },
            }
            local overlay = EntityListOverlay:new{
                plugin = plugin,
                mode = "characters",
                raw_items = zero_scores,
            }

            assert.are.equal("Vin", overlay.items[1].name)
            assert.are.equal("Kelsier", overlay.items[2].name)
            assert.are.equal("Elend", overlay.items[3].name)
            assert.are.equal("Sazed", overlay.items[4].name)
            assert.are.equal("Breeze", overlay.items[5].name)

            overlay.sort_mode = "alphabetical"
            overlay:prepareItems()
            assert.are.equal("Breeze", overlay.items[1].name)

            overlay.sort_mode = "frequency"
            overlay:prepareItems()
            assert.are.equal("Vin", overlay.items[1].name)
            assert.are.equal("Kelsier", overlay.items[2].name)
            assert.are.equal("Elend", overlay.items[3].name)
            assert.are.equal("Sazed", overlay.items[4].name)
            assert.are.equal("Breeze", overlay.items[5].name)
        end)

        it("should persist sort mode on plugin across new overlay creations", function()
            local EntityListOverlay = require("xray_entity_list")
            plugin.entity_sort_mode = {}
            local overlay1 = EntityListOverlay:new{
                plugin = plugin,
                mode = "characters",
                raw_items = { { name = "B" }, { name = "A" } },
            }
            assert.are.equal("frequency", overlay1.sort_mode)

            -- Simulate picking alphabetical in showSortDialog
            overlay1.sort_mode = "alphabetical"
            plugin.entity_sort_mode[overlay1.mode] = overlay1.sort_mode

            -- New overlay instance for characters should inherit saved sort_mode
            local overlay2 = EntityListOverlay:new{
                plugin = plugin,
                mode = "characters",
                raw_items = { { name = "B" }, { name = "A" } },
            }
            assert.are.equal("alphabetical", overlay2.sort_mode)
            assert.are.equal("A", overlay2.items[1].name)
            assert.are.equal("B", overlay2.items[2].name)
        end)

        it("should rank active series characters ahead of minor characters and prior-only characters at bottom", function()
            local EntityListOverlay = require("xray_entity_list")
            local chars = {
                { name = "Sam Barclay", role = "Supporting", sort_order = 3 },
                { name = "Cormoran Strike", role = "Private Investigator", is_series = true, sort_order = 1 },
                { name = "Robin Ellacott", role = "Investigative Partner", is_series = true, sort_order = 2 },
                { name = "Billy", role = "Minor", sort_order = 4 },
                { name = "Owen Quine", role = "Victim", source = "series_prior", source_book = 1, sort_order = 11001 },
            }
            local overlay = EntityListOverlay:new{
                plugin = plugin,
                mode = "characters",
                raw_items = chars,
            }
            overlay.sort_mode = "frequency"
            overlay:prepareItems()

            assert.are.equal("Cormoran Strike", overlay.items[1].name)
            assert.are.equal("Robin Ellacott", overlay.items[2].name)
            assert.are.equal("Sam Barclay", overlay.items[3].name)
            assert.are.equal("Billy", overlay.items[4].name)
            assert.are.equal("Owen Quine", overlay.items[5].name)
        end)
    end)
end)


