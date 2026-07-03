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
        it("should show a Menu even if no characters, containing Fetch More", function()
            plugin.characters = {}
            plugin:showCharacters()
            local last = _G.ui_tracker.last_shown
            assert.are.equal("Menu", last.type)
            assert.truthy(last.args.title:find("menu_characters"))
            assert.are.equal(1, #last.args.item_table)
            assert.truthy(last.args.item_table[1].text:find("menu_fetch_more_chars"))
        end)

        it("should show a Menu if characters exist", function()
            plugin.characters = { { name = "Alice", description = "Test" } }
            plugin:showCharacters()
            local last = _G.ui_tracker.last_shown
            assert.are.equal("Menu", last.type)
            assert.truthy(last.args.title:find("menu_characters"))
            -- Verify Alice is in the menu
            local found = false
            for _, item in ipairs(last.args.item_table) do
                if item.text:find("Alice") then found = true; break end
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
        it("should show primary picker dialog", function()
            plugin.characters = { { name = "A" }, { name = "B" } }
            plugin:showMergeFlow(plugin.characters, "characters")
            local last = _G.ui_tracker.last_shown
            assert.are.equal("ButtonDialog", last.type)
            assert.are.equal("merge_pick_primary", last.args.title)
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
        it("should show a Menu even if no terms, containing Fetch More", function()
            plugin.terms = {}
            plugin:showTerms()
            local last = _G.ui_tracker.last_shown
            assert.are.equal("Menu", last.type)
            assert.truthy(last.args.title:find("menu_terms"))
            assert.are.equal(1, #last.args.item_table)
            assert.truthy(last.args.item_table[1].text:find("menu_fetch_more_terms"))
        end)

        it("should show a Menu if terms exist", function()
            plugin.terms = { { name = "Muggle", definition = "Non-magical person" } }
            plugin:showTerms()
            local last = _G.ui_tracker.last_shown
            assert.are.equal("Menu", last.type)
            assert.truthy(last.args.title:find("menu_terms"))
            -- Verify Muggle is in the menu
            local found = false
            for _, item in ipairs(last.args.item_table) do
                if item.text:find("Muggle") then found = true; break end
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
    end)

    describe("scanBookForUnits", function()
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
                    unit_conversion_direction = "auto",
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
                return mock_hits
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
    end)
end)
