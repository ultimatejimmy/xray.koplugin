-- spec/xray_story_groups_spec.lua
require("spec.spec_helper")

local analyzer = require("xray_chapteranalyzer")
local Main = require("main")
local EntityListOverlay = require("xray_entity_list")
local XRayData = require("xray_data")

describe("Anthology Story Groups & Recurring Entities", function()
    local function createMockPlugin(ui, book_data)
        local p = {
            ui = ui,
            book_data = book_data or {},
            characters = {},
            locations = {},
            terms = {},
            historical_figures = {},
            timeline = {},
            isAnthologyMode = Main.isAnthologyMode,
            detectAnthologyFromMetadata = Main.detectAnthologyFromMetadata,
            isEntityRecurring = Main.isEntityRecurring,
            getEntityStoryRole = Main.getEntityStoryRole,
            isEntityInCurrentStory = Main.isEntityInCurrentStory,
            getCurrentStory = Main.getCurrentStory,
            resolveEntityStory = Main.resolveEntityStory,
            collectAnthologySignals = Main.collectAnthologySignals,
            ensureAnthologyDecision = Main.ensureAnthologyDecision,
            retagEntitiesByStory = Main.retagEntitiesByStory,
            ensureStoryPresenceScanned = Main.ensureStoryPresenceScanned,
            isStoryAfterCurrent = Main.isStoryAfterCurrent,
            persistBookData = function() end,
            getMenuCounts = Main.getMenuCounts,
            normalizeChapterName = XRayData.normalizeChapterName,
            assignTimelinePages = XRayData.assignTimelinePages,
        }
        return p
    end

    local mock_ui

    before_each(function()
        mock_ui = {
            document = {
                file = "test_sherlock.epub",
                getNumberOfPages = function() return 300 end,
                getProps = function()
                    return {
                        title = "The Adventures of Sherlock Holmes",
                        subject = "Detective and mystery stories, English",
                    }
                end,
                getToc = function()
                    return {
                        { title = "The Adventures of Sherlock Holmes", page = 1 }, -- NCX Title
                        { title = "A Scandal in Bohemia", page = 10 },
                        { title = "The Red-Headed League", page = 40 },
                        { title = "A Case of Identity", page = 70 },
                        { title = "THE FULL PROJECT GUTENBERG LICENSE", page = 295 },
                    }
                end
            }
        }
    end)

    describe("Offline Cache Retagging (retagEntitiesByStory)", function()
        it("retags legacy untagged entities with their correct home story based on chapter or page", function()
            local plugin = createMockPlugin(mock_ui, {
                book_mode_override = "anthology",
            })
            plugin.characters = {
                { name = "Sherlock Holmes", visible_from = { chapter_index = 2 } }, -- Story 1 (A Scandal in Bohemia)
                { name = "Irene Adler", visible_from = { chapter_index = 2 } },      -- Story 1
                { name = "Jabez Wilson", page = 45 },                              -- Story 2 (The Red-Headed League)
                { name = "Mary Sutherland", mentions = { { chapter_index = 4 } } }, -- Story 3 (A Case of Identity)
            }
            plugin.locations = {
                { name = "Briony Lodge", page = 15 },                              -- Story 1
                { name = "Sax-Coburg Square", page = 50 },                         -- Story 2
            }
            plugin.terms = {
                { name = "Sovereign", visible_from = { chapter_index = 2 } },
            }

            plugin:retagEntitiesByStory()

            assert.are.equal("toc_2", plugin.characters[1].story_id)
            assert.are.equal("A Scandal in Bohemia", plugin.characters[1].story_title)

            assert.are.equal("toc_2", plugin.characters[2].story_id)
            assert.are.equal("A Scandal in Bohemia", plugin.characters[2].story_title)

            assert.are.equal("toc_3", plugin.characters[3].story_id)
            assert.are.equal("The Red-Headed League", plugin.characters[3].story_title)

            assert.are.equal("toc_4", plugin.characters[4].story_id)
            assert.are.equal("A Case of Identity", plugin.characters[4].story_title)

            assert.are.equal("toc_2", plugin.locations[1].story_id)
            assert.are.equal("toc_3", plugin.locations[2].story_id)
            assert.are.equal("toc_2", plugin.terms[1].story_id)
        end)
    end)

    describe("Cross-Story Recurring Entity Matching", function()
        it("identifies recurring entities across stories and tracks story_presence", function()
            local plugin = createMockPlugin(mock_ui, {
                book_mode_override = "anthology",
                story_presence = {
                    ["Sherlock Holmes"] = { ["toc_2"] = true, ["toc_3"] = true },
                    ["Dr. John Watson"] = { ["toc_2"] = true, ["toc_3"] = true, ["toc_4"] = true },
                }
            })

            local holmes = { name = "Sherlock Holmes", story_id = "toc_2" }
            local watson = { name = "Dr. John Watson", story_id = "toc_2" }
            local irene = { name = "Irene Adler", story_id = "toc_2" }
            local wilson = { name = "Jabez Wilson", story_id = "toc_3" }

            assert.is_true(plugin:isEntityRecurring(holmes))
            assert.is_true(plugin:isEntityRecurring(watson))
            assert.is_false(plugin:isEntityRecurring(irene))
            assert.is_false(plugin:isEntityRecurring(wilson))

            -- Roles in Story 1 (toc_2)
            assert.are.equal("recurring", plugin:getEntityStoryRole(holmes, "toc_2"))
            assert.are.equal("current", plugin:getEntityStoryRole(irene, "toc_2"))
            assert.are.equal("other", plugin:getEntityStoryRole(wilson, "toc_2"))

            -- Roles in Story 2 (toc_3)
            assert.are.equal("recurring", plugin:getEntityStoryRole(holmes, "toc_3"))
            assert.are.equal("other", plugin:getEntityStoryRole(irene, "toc_3"))
            assert.are.equal("current", plugin:getEntityStoryRole(wilson, "toc_3"))

            -- isEntityInCurrentStory checks
            assert.is_true(plugin:isEntityInCurrentStory(holmes, { story_id = "toc_2" }))
            assert.is_true(plugin:isEntityInCurrentStory(holmes, { story_id = "toc_3" }))
            assert.is_true(plugin:isEntityInCurrentStory(irene, { story_id = "toc_2" }))
            assert.is_false(plugin:isEntityInCurrentStory(irene, { story_id = "toc_3" }))
        end)

        it("includes recurring entities in compact entity manifest for subsequent stories", function()
            local fetch_mod = require("xray_fetch")
            local mock_fetcher = {
                characters = {
                    { name = "Sherlock Holmes", story_id = "toc_2", is_recurring = true, role = "Protagonist", description = "Detective" },
                    { name = "Dr. John Watson", story_id = "toc_2", is_recurring = true, role = "Narrator", description = "Companion" },
                    { name = "Irene Adler", story_id = "toc_2", is_recurring = false, role = "Opera singer", description = "The woman" },
                    { name = "Jabez Wilson", story_id = "toc_3", is_recurring = false, role = "Pawnbroker", description = "Client" },
                },
                locations = {},
                terms = {},
                isEntityRecurring = function(self, e) return e.is_recurring end,
                buildCompactEntityManifest = fetch_mod.buildCompactEntityManifest,
            }

            -- When building manifest for Story 2 (toc_3), recurring characters from Story 1 must be present!
            local manifest = mock_fetcher:buildCompactEntityManifest("toc_3")
            local text = type(manifest) == "table" and table.concat(manifest, "\n") or tostring(manifest)
            assert.is_truthy(text:find("Sherlock Holmes"))
            assert.is_truthy(text:find("Dr. John Watson"))
            assert.is_truthy(text:find("Jabez Wilson"))
            -- Irene Adler is only in Story 1 and not recurring, so she should NOT be in Story 2's manifest
            assert.is_falsy(text:find("Irene Adler"))
        end)
    end)

    describe("UI Story Sections & Folding (EntityListOverlay)", function()
        it("builds current story section with recurring entities, and folded other stories (all stories mode)", function()
            local plugin = createMockPlugin(mock_ui, {
                book_mode_override = "anthology",
                story_presence = {
                    ["Sherlock Holmes"] = { ["toc_2"] = true, ["toc_3"] = true },
                    ["Dr. John Watson"] = { ["toc_2"] = true, ["toc_3"] = true },
                }
            })
            plugin.getCurrentDocPage = function() return 15 end -- Inside Story 1 (A Scandal in Bohemia)
            plugin.anthology_show_all_stories = true

            local items = {
                { name = "Sherlock Holmes", story_id = "toc_2" },
                { name = "Dr. John Watson", story_id = "toc_2" },
                { name = "Irene Adler", story_id = "toc_2" },
                { name = "Godfrey Norton", story_id = "toc_2" },
                { name = "Jabez Wilson", story_id = "toc_3" },
                { name = "Vincent Spaulding", story_id = "toc_3" },
                { name = "Mary Sutherland", story_id = "toc_4" },
            }

            local overlay = {
                plugin = plugin,
                isSectionCollapsed = EntityListOverlay.isSectionCollapsed,
                toggleSection = EntityListOverlay.toggleSection,
                buildStorySections = EntityListOverlay.buildStorySections,
                story_sections_collapsed = {},
            }

            local sections = overlay:buildStorySections(items)

            -- 1. Current story section (expanded by default, contains local + recurring entities)
            assert.is_true(sections[1].is_section_header)
            assert.are.equal("current", sections[1].section_id)
            assert.are.equal(4, sections[1].count) -- Holmes, Watson, Irene Adler, Godfrey Norton
            assert.is_false(sections[1].collapsed)
            assert.are.equal("Sherlock Holmes", sections[2].name)
            assert.are.equal("Dr. John Watson", sections[3].name)
            assert.are.equal("Irene Adler", sections[4].name)
            assert.are.equal("Godfrey Norton", sections[5].name)

            -- 2. Story 2 (collapsed by default, count includes recurring characters present in Story 2)
            assert.is_true(sections[6].is_section_header)
            assert.are.equal("story_toc_3", sections[6].section_id)
            assert.are.equal(4, sections[6].count) -- Jabez Wilson, Vincent Spaulding + Holmes, Watson
            assert.is_true(sections[6].collapsed) -- Collapsed, so items are NOT inserted!

            -- 3. Story 3 (collapsed by default)
            assert.is_true(sections[7].is_section_header)
            assert.are.equal("story_toc_4", sections[7].section_id)
            assert.are.equal(1, sections[7].count)
            assert.is_true(sections[7].collapsed)

            -- Total display items: 1 current header + 4 items + 2 folded headers = 7
            assert.are.equal(7, #sections)
        end)

        it("unfolds story when toggled", function()
            local plugin = createMockPlugin(mock_ui, {
                book_mode_override = "anthology",
            })
            plugin.getCurrentDocPage = function() return 15 end
            plugin.anthology_show_all_stories = true

            local items = {
                { name = "Irene Adler", story_id = "toc_2" },
                { name = "Jabez Wilson", story_id = "toc_3" },
            }

            local overlay = {
                plugin = plugin,
                isSectionCollapsed = EntityListOverlay.isSectionCollapsed,
                toggleSection = EntityListOverlay.toggleSection,
                buildStorySections = EntityListOverlay.buildStorySections,
                story_sections_collapsed = {},
            }

            -- Initially story_toc_3 is collapsed
            assert.is_true(overlay:isSectionCollapsed("story_toc_3"))

            -- User clicks to expand Story 2
            overlay.story_sections_collapsed["story_toc_3"] = false
            assert.is_false(overlay:isSectionCollapsed("story_toc_3"))

            local sections = overlay:buildStorySections(items)
            -- Now Story 2 items should be visible
            local found_wilson = false
            for _, it in ipairs(sections) do
                if it.name == "Jabez Wilson" then found_wilson = true end
            end
            assert.is_true(found_wilson)
        end)

        it("hides future story headers and future characters under spoiler-free mode", function()
            local plugin = createMockPlugin(mock_ui, {
                book_mode_override = "anthology",
                story_presence = {
                    ["Sherlock Holmes"] = { ["toc_2"] = true, ["toc_3"] = true },
                    ["Dr. John Watson"] = { ["toc_2"] = true, ["toc_3"] = true },
                }
            })
            plugin.getCurrentDocPage = function() return 15 end -- Inside Story 1 (A Scandal in Bohemia)
            plugin.ai_helper = { settings = { spoiler_setting = "spoiler_free" } }
            plugin.anthology_show_all_stories = false

            local items = {
                { name = "Sherlock Holmes", story_id = "toc_2" },
                { name = "Dr. John Watson", story_id = "toc_2" },
                { name = "Irene Adler", story_id = "toc_2" },
                { name = "Godfrey Norton", story_id = "toc_2" },
                { name = "Jabez Wilson", story_id = "toc_3" },
                { name = "Vincent Spaulding", story_id = "toc_3" },
                { name = "Mary Sutherland", story_id = "toc_4" },
            }

            local overlay = {
                plugin = plugin,
                isSectionCollapsed = EntityListOverlay.isSectionCollapsed,
                toggleSection = EntityListOverlay.toggleSection,
                buildStorySections = EntityListOverlay.buildStorySections,
                story_sections_collapsed = {},
            }

            local sections = overlay:buildStorySections(items)

            -- Should only have 1 header ("This story: A Scandal in Bohemia") and 4 characters
            assert.are.equal(5, #sections)
            assert.is_true(sections[1].is_section_header)
            assert.are.equal("current", sections[1].section_id)
            assert.are.equal(4, sections[1].count)

            -- No headers for future Story 2 or Story 3!
            for _, s in ipairs(sections) do
                if s.is_section_header then
                    assert.are_not.equal("story_toc_3", s.section_id)
                    assert.are_not.equal("story_toc_4", s.section_id)
                end
            end
        end)

        it("shows past stories folded but hides future stories when at Story 2", function()
            local plugin = createMockPlugin(mock_ui, {
                book_mode_override = "anthology",
                story_presence = {
                    ["Sherlock Holmes"] = { ["toc_2"] = true, ["toc_3"] = true },
                    ["Dr. John Watson"] = { ["toc_2"] = true, ["toc_3"] = true },
                }
            })
            plugin.getCurrentDocPage = function() return 45 end -- Inside Story 2 (The Red-Headed League)
            plugin.ai_helper = { settings = { spoiler_setting = "spoiler_free" } }
            plugin.anthology_show_all_stories = false

            local items = {
                { name = "Sherlock Holmes", story_id = "toc_2" },
                { name = "Dr. John Watson", story_id = "toc_2" },
                { name = "Irene Adler", story_id = "toc_2" },
                { name = "Jabez Wilson", story_id = "toc_3" },
                { name = "Vincent Spaulding", story_id = "toc_3" },
                { name = "Mary Sutherland", story_id = "toc_4" },
            }

            local overlay = {
                plugin = plugin,
                isSectionCollapsed = EntityListOverlay.isSectionCollapsed,
                toggleSection = EntityListOverlay.toggleSection,
                buildStorySections = EntityListOverlay.buildStorySections,
                story_sections_collapsed = {},
            }

            local sections = overlay:buildStorySections(items)

            -- Current section is Story 2 (Jabez Wilson, Vincent Spaulding, Holmes, Watson)
            assert.is_true(sections[1].is_section_header)
            assert.are.equal("current", sections[1].section_id)
            assert.are.equal(4, sections[1].count)

            -- Past story 1 (toc_2) is present and folded!
            local found_past = false
            for _, s in ipairs(sections) do
                if s.is_section_header and s.section_id == "story_toc_2" then
                    found_past = true
                    assert.is_true(s.collapsed)
                end
            end
            assert.is_true(found_past)

            -- Future story 3 (toc_4) MUST NOT be present!
            for _, s in ipairs(sections) do
                if s.is_section_header then
                    assert.are_not.equal("story_toc_4", s.section_id)
                end
            end
        end)

        it("filters out future characters in prepareItems under spoiler-free mode", function()
            local plugin = createMockPlugin(mock_ui, {
                book_mode_override = "anthology",
                story_presence = {
                    ["Sherlock Holmes"] = { ["toc_2"] = true, ["toc_3"] = true },
                }
            })
            plugin.getCurrentDocPage = function() return 1 end -- 1% of book / before first story
            plugin.getCurrentChapterIndex = function() return 1 end
            plugin.ai_helper = { settings = { spoiler_setting = "spoiler_free" } }
            plugin.anthology_show_all_stories = false
            plugin.isEntityVisibleAtCurrentPosition = function(self, entity, chap, pg)
                if entity.visible_from and entity.visible_from.chapter_index and entity.visible_from.chapter_index > chap then
                    return false
                end
                return true
            end

            local raw = {
                { name = "Sherlock Holmes", story_id = "toc_2", visible_from = { chapter_index = 1 } },
                { name = "Irene Adler", story_id = "toc_2", visible_from = { chapter_index = 2 } }, -- Not yet reached!
                { name = "Jabez Wilson", story_id = "toc_3" }, -- Future story!
            }

            local overlay = {
                plugin = plugin,
                mode = "characters",
                raw_items = raw,
                prepareItems = EntityListOverlay.prepareItems,
            }

            overlay:prepareItems()

            -- Only Holmes is visible! Irene Adler hasn't appeared yet in Story 1, and Jabez Wilson is in Story 2!
            assert.are.equal(1, #overlay.items)
            assert.are.equal("Sherlock Holmes", overlay.items[1].name)
        end)

        it("auto-unfolds all matching sections when a search query is active", function()
            local plugin = createMockPlugin(mock_ui, {
                book_mode_override = "anthology",
            })
            plugin.getCurrentDocPage = function() return 15 end

            local items = {
                { name = "Jabez Wilson", story_id = "toc_3" },
            }

            local overlay = {
                plugin = plugin,
                search_query = "wilson",
                isSectionCollapsed = EntityListOverlay.isSectionCollapsed,
                toggleSection = EntityListOverlay.toggleSection,
                buildStorySections = EntityListOverlay.buildStorySections,
                story_sections_collapsed = {},
            }

            -- During search, isSectionCollapsed must return false so search results are open!
            assert.is_false(overlay:isSectionCollapsed("story_toc_3"))

            local sections = overlay:buildStorySections(items)
            assert.is_false(sections[1].collapsed)
            assert.are.equal("Jabez Wilson", sections[2].name)
        end)
    end)

    describe("Menu Counts in Anthology Mode", function()
        it("counts both current story entities and recurring entities for current reading position", function()
            local plugin = createMockPlugin(mock_ui, {
                book_mode_override = "anthology",
                story_presence = {
                    ["Sherlock Holmes"] = { ["toc_2"] = true, ["toc_3"] = true },
                    ["Dr. John Watson"] = { ["toc_2"] = true, ["toc_3"] = true },
                }
            })
            plugin.anthology_show_all_stories = false
            plugin.getCurrentDocPage = function() return 15 end -- Inside Story 1
            plugin.getCurrentStory = function() return { story_id = "toc_2", story_title = "A Scandal in Bohemia" } end

            plugin.characters = {
                { name = "Sherlock Holmes", story_id = "toc_2" }, -- Recurring (counted)
                { name = "Dr. John Watson", story_id = "toc_2" }, -- Recurring (counted)
                { name = "Irene Adler", story_id = "toc_2" },      -- Story 1 (counted)
                { name = "Jabez Wilson", story_id = "toc_3" },     -- Story 2 (not counted in Story 1)
            }
            plugin.locations = {
                { name = "Briony Lodge", story_id = "toc_2" },     -- Story 1 (counted)
                { name = "Sax-Coburg Square", story_id = "toc_3" },-- Story 2 (not counted)
            }

            local counts = plugin:getMenuCounts()
            assert.are.equal(3, counts.characters) -- Holmes, Watson, Irene Adler
            assert.are.equal(1, counts.locations)  -- Briony Lodge
        end)
    end)

    describe("Current Story Visibility under Spoiler-Free", function()
        it("allows all entities of current story through even if their introduction page is further ahead in the story", function()
            local plugin = createMockPlugin(mock_ui, {
                book_mode_override = "anthology",
            })
            plugin.ai_helper = { settings = { spoiler_setting = "spoiler_free" } }
            plugin.getCurrentDocPage = function() return 10 end -- Start of Story 1 (pages 10-39)
            plugin.getCurrentStory = function() return { story_id = "toc_2", story_title = "A Scandal in Bohemia" } end

            local raw_items = {
                { name = "Sherlock Holmes", story_id = "toc_2", page = 35 },
                { name = "Irene Adler", story_id = "toc_2", visible_from = { chapter_index = 2, page_hint = 35 } },
                { name = "Future Entity", story_id = "toc_4", visible_from = { chapter_index = 4, page_hint = 75 } },
            }

            local overlay = {
                plugin = plugin,
                mode = "characters",
                raw_items = raw_items,
                prepareItems = EntityListOverlay.prepareItems,
            }

            overlay:prepareItems()
            -- Story 1 entities (Sherlock Holmes, Irene Adler) must be visible despite being on page 35
            -- Future Entity (Story 3, toc_4) should be hidden because spoiler-free is active
            local visible_names = {}
            for _, entry in ipairs(overlay.items or {}) do
                table.insert(visible_names, entry.name)
            end

            assert.are.equal(2, #visible_names)
            local has_holmes = false
            local has_irene = false
            for _, n in ipairs(visible_names) do
                if n == "Sherlock Holmes" then has_holmes = true end
                if n == "Irene Adler" then has_irene = true end
            end
            assert.is_true(has_holmes)
            assert.is_true(has_irene)
        end)
    end)

    describe("Height-Budgeted Pagination", function()
        it("packs variable height headers and cards without voids and avoids orphan headers", function()
            local row_h = 64
            local divider_h = 1
            local avail_content_h = 640
            local section_header_h = 38 + 1
            local card_h = row_h + divider_h

            local display_items = {
                { is_section_header = true, title = "Current" },
                { name = "Char 1" },
                { name = "Char 2" },
                { is_section_header = true, title = "Story 1" },
                { is_section_header = true, title = "Story 2" },
                { is_section_header = true, title = "Story 3" },
                { is_section_header = true, title = "Story 4" },
                { name = "Story 4 Char 1" },
                { name = "Story 4 Char 2" },
                { name = "Story 4 Char 3" },
                { name = "Story 4 Char 4" },
                { name = "Story 4 Char 5" },
                { is_section_header = true, title = "Story 5" },
                { name = "Story 5 Char 1" },
            }

            local pages = {}
            local cur_page_items = {}
            local cur_page_h = 0

            for idx, it in ipairs(display_items) do
                local is_sec = it.is_section_header or it.is_prior_header or it.is_current_header
                local it_h = is_sec and section_header_h or card_h
                local is_orphan = is_sec and (#cur_page_items > 0) and (cur_page_h + it_h + card_h > avail_content_h)

                if #cur_page_items > 0 and (is_orphan or (cur_page_h + it_h > avail_content_h)) then
                    table.insert(pages, cur_page_items)
                    cur_page_items = {}
                    cur_page_h = 0
                end

                table.insert(cur_page_items, it)
                cur_page_h = cur_page_h + it_h
            end

            if #cur_page_items > 0 then
                table.insert(pages, cur_page_items)
            end

            assert.are.equal(2, #pages)
            -- Page 1 packs 11 items and avoids leaving an orphan header
            assert.are.equal(11, #pages[1])
            -- Story 5 header starts cleanly on Page 2 with its child card
            assert.are.equal(3, #pages[2])
            assert.are.equal("Story 5", pages[2][2].title)
        end)
    end)

    describe("Nested TOC and Misaligned Timeline/Entity Healing", function()
        local nested_ui, plugin

        before_each(function()
            nested_ui = {
                getCurrentPage = function() return 309 end,
                document = {
                    file = "nested_sherlock.epub",
                    getNumberOfPages = function() return 600 end,
                    getPageCount = function() return 600 end,
                    getProps = function()
                        return {
                            title = "The Adventures of Sherlock Holmes",
                            subject = "Short stories",
                        }
                    end,
                    getToc = function()
                        return {
                            { title = "The Adventures of Sherlock Holmes", page = 1 }, -- 1
                            { title = "Contents", page = 3 }, -- 2
                            { title = "I. A SCANDAL IN BOHEMIA", page = 5 }, -- 3 (Story 1)
                            { title = "I.", page = 5 }, -- 4
                            { title = "II.", page = 27 }, -- 5
                            { title = "III.", page = 50 }, -- 6
                            { title = "II. THE RED-HEADED LEAGUE", page = 58 }, -- 7 (Story 2)
                            { title = "III. A CASE OF IDENTITY", page = 113 }, -- 8 (Story 3)
                            { title = "IV. THE BOSCOMBE VALLEY MYSTERY", page = 154 }, -- 9 (Story 4)
                            { title = "V. THE FIVE ORANGE PIPS", page = 210 }, -- 10 (Story 5)
                            { title = "VI. THE MAN WITH THE TWISTED LIP", page = 254 }, -- 11 (Story 6)
                            { title = "VII. THE ADVENTURE OF THE BLUE CARBUNCLE", page = 309 }, -- 12 (Story 7)
                            { title = "VIII. THE ADVENTURE OF THE SPECKLED BAND", page = 356 }, -- 13 (Story 8)
                        }
                    end
                }
            }
            plugin = createMockPlugin(nested_ui, { is_anthology = true })
        end)

        it("heals misaligned timeline events and character story_id using retagEntitiesByStory", function()
            -- Story VII event was previously mis-saved with chapter_index = 11, story_id = "toc_11"
            local blue_carbuncle_ev = {
                chapter = "VII. THE ADVENTURE OF THE BLUE CARBUNCLE",
                event = "Sherlock Holmes deduces the owner of the hat and goose with the blue carbuncle.",
                chapter_index = 11,
                page = 309,
                story_id = "toc_11",
                story_title = "VI. THE MAN WITH THE TWISTED LIP",
            }
            -- Story VIII event was previously mis-saved with chapter_index = 12, story_id = "toc_12"
            local speckled_band_ev = {
                chapter = "VIII. THE ADVENTURE OF THE SPECKLED BAND",
                event = "Helen Stoner visits Holmes regarding Julia's death and the swamp adder.",
                chapter_index = 12,
                page = 356,
                story_id = "toc_12",
                story_title = "VII. THE ADVENTURE OF THE BLUE CARBUNCLE",
            }
            plugin.timeline = { blue_carbuncle_ev, speckled_band_ev }

            -- Jabez Wilson was mis-saved with chapter_index = 6 and story_id = "toc_3"
            local jabez = {
                name = "Jabez Wilson",
                visible_from = {
                    chapter_index = 6,
                    chapter_title = "II. THE RED-HEADED LEAGUE",
                    page_hint = 58,
                },
                story_id = "toc_3",
                story_title = "I. A SCANDAL IN BOHEMIA",
            }
            plugin.characters = { jabez }

            plugin:retagEntitiesByStory()

            -- Blue Carbuncle healed to Story VII (toc_12)
            assert.are.equal("toc_12", blue_carbuncle_ev.story_id)
            assert.are.equal("VII. THE ADVENTURE OF THE BLUE CARBUNCLE", blue_carbuncle_ev.story_title)
            assert.are.equal(12, blue_carbuncle_ev.chapter_index)

            -- Speckled Band healed to Story VIII (toc_13)
            assert.are.equal("toc_13", speckled_band_ev.story_id)
            assert.are.equal("VIII. THE ADVENTURE OF THE SPECKLED BAND", speckled_band_ev.story_title)
            assert.are.equal(13, speckled_band_ev.chapter_index)

            -- Jabez Wilson healed to Story II (toc_7)
            assert.are.equal("toc_7", jabez.story_id)
            assert.are.equal("II. THE RED-HEADED LEAGUE", jabez.story_title)
        end)

        it("shows current story timeline event and hides future stories under spoiler filtering", function()
            local blue_carbuncle_ev = {
                chapter = "VII. THE ADVENTURE OF THE BLUE CARBUNCLE",
                event = "The Blue Carbuncle is found in the Christmas goose.",
                chapter_index = 11, -- initially misaligned
                page = 309,
                story_id = "toc_11", -- initially misaligned
            }
            local speckled_band_ev = {
                chapter = "VIII. THE ADVENTURE OF THE SPECKLED BAND",
                event = "The Speckled Band snake attack.",
                chapter_index = 12,
                page = 356,
                story_id = "toc_12",
            }
            plugin.timeline = { blue_carbuncle_ev, speckled_band_ev }

            -- Run retag
            plugin:retagEntitiesByStory()

            -- Now render timeline view in EntityListOverlay at current page = 309 (in Story VII)
            nested_ui.getCurrentPage = function() return 309 end
            local overlay = EntityListOverlay:new{
                plugin = plugin,
                mode = "timeline",
                items = plugin.timeline,
                reveal_future = false, -- spoiler-free mode
            }

            local sections = overlay:buildStorySections(plugin.timeline)

            -- Check Section 1: This story: VII. THE ADVENTURE OF THE BLUE CARBUNCLE
            assert.is_true(#sections > 0)
            local current_header = sections[1]
            assert.is_true(current_header.is_section_header)
            assert.are.equal("current", current_header.section_id)
            assert.are.equal(1, current_header.count) -- Count should be 1!

            -- Verify the event inside is Blue Carbuncle
            local current_event = sections[2]
            assert.are.equal("VII. THE ADVENTURE OF THE BLUE CARBUNCLE", current_event.chapter)

            -- Verify Story VIII (Speckled Band, future spoiler) is NOT rendered
            for _, item in ipairs(sections) do
                if item.is_section_header and item.section_id == "toc_13" then
                    error("Future story section toc_13 should not be visible under spoiler-free mode")
                end
                if item.chapter and item.chapter:find("SPECKLED BAND") then
                    error("Future event SPECKLED BAND should not be visible under spoiler-free mode")
                end
            end
        end)

        it("preserves current page and anchors to section when expanding/collapsing a folded story", function()
            local events = {}
            for s = 1, 25 do
                for e = 1, 2 do
                    table.insert(events, {
                        chapter = string.format("Story %d Event %d", s, e),
                        event = string.format("Event details for story %d event %d", s, e),
                        chapter_index = s + 2,
                        page = s * 10 + e,
                        story_id = "toc_" .. tostring(s + 2),
                        story_title = string.format("Story %d", s),
                    })
                end
            end
            table.insert(events, {
                chapter = "Current Story Event",
                event = "Current story event details.",
                chapter_index = 30,
                page = 500,
                story_id = "toc_30",
                story_title = "Current Story",
            })
            plugin.timeline = events

            nested_ui.getCurrentPage = function() return 500 end
            local overlay = EntityListOverlay:new{
                plugin = plugin,
                mode = "timeline",
                raw_items = plugin.timeline,
                reveal_future = false,
            }

            overlay.screen_height = 800
            overlay.screen_width = 600

            overlay:buildUI()
            assert.is_true(overlay.total_pages >= 2)

            -- Navigate to page 2
            overlay.current_page = 2
            overlay:buildUI()
            assert.are.equal(2, overlay.current_page)

            -- Find a folded section header on page 2
            local target_sec_id = nil
            for _, it in ipairs(overlay.current_page_items) do
                if it.is_section_header and it.section_id and it.section_id ~= "current" then
                    target_sec_id = it.section_id
                    break
                end
            end
            assert.is_not_nil(target_sec_id)

            -- Expanding this folded section should stay on the page containing the section, NOT jump to page 1
            overlay:toggleSection(target_sec_id)
            assert.are_not.equal(1, overlay.current_page)
            local found_on_page = false
            for _, it in ipairs(overlay.current_page_items) do
                if it.is_section_header and it.section_id == target_sec_id then
                    found_on_page = true
                    break
                end
            end
            assert.is_true(found_on_page)

            -- Collapsing the section should also remain on the page containing the section, NOT jump to page 1
            overlay:toggleSection(target_sec_id)
            assert.are_not.equal(1, overlay.current_page)
            local found_collapsed_on_page = false
            for _, it in ipairs(overlay.current_page_items) do
                if it.is_section_header and it.section_id == target_sec_id then
                    found_collapsed_on_page = true
                    break
                end
            end
            assert.is_true(found_collapsed_on_page)
        end)
    end)
end)
