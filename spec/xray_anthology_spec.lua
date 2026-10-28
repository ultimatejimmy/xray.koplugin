-- spec/xray_anthology_spec.lua
require("spec.spec_helper")

local utils = require("xray_utils")
local analyzer = require("xray_chapteranalyzer")
local data_mod = require("xray_data")
local LookupManager = require("xray_lookupmanager")
local Main = require("main")

describe("Anthology / Short Story Collection Mode", function()

    describe("TOC Flattening & Depth", function()
        it("preserves depth on flattened TOC nodes", function()
            local hierarchical_toc = {
                {
                    title = "Part I: Early Tales",
                    page = 1,
                    { title = "The Red-Headed League", page = 10 },
                    { title = "A Scandal in Bohemia", page = 35 },
                },
                {
                    title = "Part II: Later Tales",
                    page = 60,
                    {
                        title = "The Final Problem",
                        page = 70,
                        { title = "Section A", page = 75 }
                    }
                }
            }

            local flat = utils:flattenTOC(hierarchical_toc)
            assert.are.equal(6, #flat)
            assert.are.equal(1, flat[1].depth)
            assert.are.equal("Part I: Early Tales", flat[1].title)
            assert.are.equal(2, flat[2].depth)
            assert.are.equal("The Red-Headed League", flat[2].title)
            assert.are.equal(2, flat[3].depth)
            assert.are.equal("A Scandal in Bohemia", flat[3].title)
            assert.are.equal(1, flat[4].depth)
            assert.are.equal("Part II: Later Tales", flat[4].title)
            assert.are.equal(2, flat[5].depth)
            assert.are.equal("The Final Problem", flat[5].title)
            assert.are.equal(3, flat[6].depth)
            assert.are.equal("Section A", flat[6].title)
        end)
    end)

    describe("Story Boundary Mapping & Auto-Detection", function()
        local mock_ui

        before_each(function()
            mock_ui = {
                document = {
                    file = "test_" .. tostring(math.random(1000000)) .. ".epub",
                    getNumberOfPages = function() return 200 end,
                    getToc = function()
                        return {
                            { title = "Introduction", page = 1, depth = 1 },
                            { title = "Story One: The Beginning", page = 15, depth = 1 },
                            { title = "Story Two: The Middle", page = 50, depth = 1 },
                            { title = "Story Three: The End", page = 120, depth = 1 },
                        }
                    end
                }
            }
        end)

        it("auto-detects depth 1 stories and filters non-narrative frontmatter", function()
            local story_map = analyzer:getStoryMap(mock_ui, nil)
            assert.are.equal(3, #story_map.stories)

            assert.are.equal("Story One: The Beginning", story_map.stories[1].story_title)
            assert.are.equal(15, story_map.stories[1].start_page)
            assert.are.equal(49, story_map.stories[1].end_page)
            assert.are.equal(2, story_map.stories[1].start_toc_idx)
            assert.are.equal(2, story_map.stories[1].end_toc_idx)

            assert.are.equal("Story Two: The Middle", story_map.stories[2].story_title)
            assert.are.equal(50, story_map.stories[2].start_page)
            assert.are.equal(119, story_map.stories[2].end_page)

            assert.are.equal("Story Three: The End", story_map.stories[3].story_title)
            assert.are.equal(120, story_map.stories[3].start_page)
            assert.are.equal(200, story_map.stories[3].end_page)
        end)

        it("auto-detects depth 2 when top-level entries are structural parts/volumes", function()
            mock_ui.document.file = "test_parts_" .. tostring(math.random(1000000)) .. ".epub"
            mock_ui.document.getToc = function()
                return {
                    {
                        title = "Volume 1",
                        page = 1,
                        { title = "Story A", page = 10 },
                        { title = "Story B", page = 40 },
                    },
                    {
                        title = "Volume 2",
                        page = 80,
                        { title = "Story C", page = 90 },
                        { title = "Story D", page = 140 },
                    }
                }
            end

            local story_map = analyzer:getStoryMap(mock_ui, nil)
            assert.are.equal(4, #story_map.stories)
            assert.are.equal("Story A", story_map.stories[1].story_title)
            assert.are.equal(10, story_map.stories[1].start_page)
            assert.are.equal(39, story_map.stories[1].end_page)

            assert.are.equal("Story B", story_map.stories[2].story_title)
            assert.are.equal(40, story_map.stories[2].start_page)
            assert.are.equal(89, story_map.stories[2].end_page)

            assert.are.equal("Story C", story_map.stories[3].story_title)
            assert.are.equal("Story D", story_map.stories[4].story_title)
            assert.are.equal(200, story_map.stories[4].end_page)
        end)

        it("respects explicit custom depth setting", function()
            mock_ui.document.file = "test_custom_" .. tostring(math.random(1000000)) .. ".epub"
            mock_ui.document.getToc = function()
                return {
                    {
                        title = "Part 1",
                        page = 1,
                        { title = "Chapter 1", page = 10 }
                    }
                }
            end

            -- Force depth 1 even if child exists
            local map_d1 = analyzer:getStoryMap(mock_ui, 1)
            assert.are.equal(1, #map_d1.stories)
            assert.are.equal("Part 1", map_d1.stories[1].story_title)

            -- Force depth 2
            mock_ui.document.file = "test_custom_2_" .. tostring(math.random(1000000)) .. ".epub"
            local map_d2 = analyzer:getStoryMap(mock_ui, 2)
            assert.are.equal(1, #map_d2.stories)
            assert.are.equal("Chapter 1", map_d2.stories[1].story_title)
        end)

        it("correctly resolves story for toc index and page", function()
            local s_idx = analyzer:getStoryForTocIndex(mock_ui, 3)
            assert.is_not_nil(s_idx)
            assert.are.equal("Story Two: The Middle", s_idx.story_title)

            local s_pg = analyzer:getStoryForPage(mock_ui, 65)
            assert.is_not_nil(s_pg)
            assert.are.equal("Story Two: The Middle", s_pg.story_title)

            local s_pg3 = analyzer:getStoryForPage(mock_ui, 150)
            assert.is_not_nil(s_pg3)
            assert.are.equal("Story Three: The End", s_pg3.story_title)
        end)
    end)

    describe("Anthology Detection & Mode Check", function()
        local plugin

        before_each(function()
            plugin = {
                ui = {
                    document = {
                        getProps = function() return {} end
                    }
                },
                book_data = {},
                detectAnthologyFromMetadata = Main.detectAnthologyFromMetadata,
                isAnthologyMode = Main.isAnthologyMode,
            }
        end)

        it("detects anthology from title keywords", function()
            assert.is_true(plugin:detectAnthologyFromMetadata({}, "The Complete Short Stories of Sherlock Holmes"))
            assert.is_true(plugin:detectAnthologyFromMetadata({}, "Best American Short Stories 2024"))
            assert.is_true(plugin:detectAnthologyFromMetadata({}, "Selected Stories of Philip K. Dick"))
            assert.is_true(plugin:detectAnthologyFromMetadata({}, "A Science Fiction Anthology"))
            assert.is_true(plugin:detectAnthologyFromMetadata({}, "Collected Stories"))
            assert.is_false(plugin:detectAnthologyFromMetadata({}, "Dune"))
            assert.is_false(plugin:detectAnthologyFromMetadata({}, "The Great Gatsby"))
        end)

        it("detects anthology from document metadata keywords/genre", function()
            assert.is_true(plugin:detectAnthologyFromMetadata({ keywords = "short stories, horror, anthology" }, "Haunted"))
            assert.is_true(plugin:detectAnthologyFromMetadata({ genre = "Short Story Collection" }, "Tales"))
            assert.is_false(plugin:detectAnthologyFromMetadata({ keywords = "novel, fiction" }, "A Great Novel"))
        end)

        it("isAnthologyMode returns true when book_type is 'anthology' or metadata matches", function()
            plugin.book_data.book_type = "anthology"
            assert.is_true(plugin:isAnthologyMode())

            plugin.book_data.book_type = "fiction"
            assert.is_false(plugin:isAnthologyMode())

            plugin.book_data.book_type = nil
            plugin.ui.document.getProps = function()
                return { title = "Collected Short Stories" }
            end
            assert.is_true(plugin:isAnthologyMode())
        end)
    end)

    describe("Scoping & Deduplication", function()
        it("deduplicateByName isolates duplicates across different stories in Anthology mode", function()
            local list = {
                { name = "John Smith", story_id = "story_1", mentions = { { page = 10 } } },
                { name = "John Smith", story_id = "story_1", mentions = { { page = 15 } } },
                { name = "John Smith", story_id = "story_2", mentions = { { page = 60 } } },
                { name = "Mary Jane",  story_id = "story_1", mentions = { { page = 20 } } },
            }

            local mock_caller = {
                isAnthologyMode = function() return true end
            }

            local deduplicated = data_mod:deduplicateByName(list, "name", mock_caller)

            -- Should keep 1 John Smith in story_1, 1 John Smith in story_2, and 1 Mary Jane
            assert.are.equal(3, #deduplicated)

            local counts = {}
            for _, item in ipairs(deduplicated) do
                local key = item.story_id .. ":" .. item.name
                counts[key] = (counts[key] or 0) + 1
            end

            assert.are.equal(1, counts["story_1:John Smith"])
            assert.are.equal(1, counts["story_2:John Smith"])
            assert.are.equal(1, counts["story_1:Mary Jane"])

            -- In story_1, the mentions should be combined
            for _, item in ipairs(deduplicated) do
                if item.story_id == "story_1" and item.name == "John Smith" then
                    assert.are.equal(2, #item.mentions)
                end
            end
        end)

        it("mergeEntries only merges items within the specified story_id", function()
            local list = {
                { name = "Arthur", story_id = "story_1", aliases = {"Art"} },
                { name = "Artie",  story_id = "story_1", aliases = {} },
                { name = "Artie",  story_id = "story_2", aliases = {} },
            }

            local ok = data_mod:mergeEntries(list, "Arthur", "Artie", nil, "story_1")
            assert.is_true(ok)

            -- The Artie in story_2 must NOT be deleted
            assert.are.equal(2, #list)
            assert.are.equal("story_1", list[1].story_id)
            assert.are.equal("Arthur", list[1].name)
            assert.are.equal("story_2", list[2].story_id)
            assert.are.equal("Artie", list[2].name)
        end)
    end)

    describe("Sequential Chapter Delta & Manifest Scoping", function()
        local fetch_mod

        before_each(function()
            fetch_mod = require("xray_fetch")
        end)

        it("mergeSequentialChapterDelta tags entities with story_id and scopes to story", function()
            local plugin = {
                isAnthologyMode = function() return true end,
                getCurrentStory = function()
                    return { story_id = "story_1", story_title = "First Adventure", start_page = 1, end_page = 50 }
                end,
                characters = {
                    { name = "Watson", story_id = "story_1", story_title = "First Adventure", mentions = {} },
                    { name = "Watson", story_id = "story_2", story_title = "Second Adventure", mentions = {} },
                },
                locations = {},
                terms = {},
                historical_figures = {},
                timeline = {},
                book_data = {
                    story_fetch_state = {}
                },
                log = function() end,
                saveData = function() end,
            }

            local delta = {
                new_characters = {
                    { name = "Holmes", description = "Great detective." }
                },
                character_state_updates = {
                    { name = "Watson", description = "Faithful friend." }
                }
            }

            fetch_mod.mergeSequentialChapterDelta(plugin, delta, { title = "Chapter 1", page = 20, toc_index = 1 }, 1)

            -- Watson in story_1 should be updated (description set)
            -- Watson in story_2 should be untouched
            -- Holmes should be added with story_1 tags
            assert.are.equal(3, #plugin.characters)

            local s1_watson, s2_watson, s1_holmes
            for _, c in ipairs(plugin.characters) do
                if c.name == "Watson" and c.story_id == "story_1" then s1_watson = c end
                if c.name == "Watson" and c.story_id == "story_2" then s2_watson = c end
                if c.name == "Holmes" and c.story_id == "story_1" then s1_holmes = c end
            end

            assert.is_not_nil(s1_watson)
            assert.are.equal("Faithful friend.", s1_watson.description)
            assert.is_not_nil(s2_watson)
            assert.is_nil(s2_watson.description)
            assert.is_not_nil(s1_holmes)
            assert.are.equal("story_1", s1_holmes.story_id)
            assert.are.equal("First Adventure", s1_holmes.story_title)

            -- Story fetch state should be tracked per story
            assert.is_not_nil(plugin.book_data.story_fetch_state["story_1"])
            assert.are.equal(20, plugin.book_data.story_fetch_state["story_1"].last_fetch_page)
            assert.are.equal(1, plugin.book_data.story_fetch_state["story_1"].last_fetch_chapter)
        end)

        it("buildCompactEntityManifest scopes manifest to the requested story_id", function()
            local plugin = {
                isAnthologyMode = function() return true end,
                characters = {
                    { name = "Alice", story_id = "story_1" },
                    { name = "Bob", story_id = "story_2" },
                },
                locations = {
                    { name = "Wonderland", story_id = "story_1" },
                    { name = "London", story_id = "story_2" },
                },
                terms = {},
                historical_figures = {}
            }

            local manifest_s1 = fetch_mod.buildCompactEntityManifest(plugin, "story_1")
            assert.is_not_nil(manifest_s1:find("Alice", 1, true))
            assert.is_not_nil(manifest_s1:find("Wonderland", 1, true))
            assert.is_nil(manifest_s1:find("Bob", 1, true))
            assert.is_nil(manifest_s1:find("London", 1, true))

            local manifest_s2 = fetch_mod.buildCompactEntityManifest(plugin, "story_2")
            assert.is_not_nil(manifest_s2:find("Bob", 1, true))
            assert.is_not_nil(manifest_s2:find("London", 1, true))
            assert.is_nil(manifest_s2:find("Alice", 1, true))
        end)
    end)

    describe("LookupManager Story Prioritization & Disambiguation", function()
        local plugin
        local lm

        before_each(function()
            plugin = {
                isAnthologyMode = function() return true end,
                getCurrentStory = function()
                    return { story_id = "story_2", story_title = "The Sign of Four" }
                end,
                isEntityInCurrentStory = function(self, item, current_story)
                    current_story = current_story or self:getCurrentStory()
                    return item.story_id == current_story.story_id
                end,
                resolveEntityStory = function(self, item)
                    return item.story_id, item.story_title
                end,
                characters = {
                    { name = "Jonathan Small", story_id = "story_1", story_title = "A Study in Scarlet" },
                    { name = "Jonathan Small", story_id = "story_2", story_title = "The Sign of Four" },
                },
                locations = {},
                terms = {},
                historical_figures = {},
                loc = {
                    t = function(self, k, a1)
                        if k == "multiple_matches" then return "Multiple matches for " .. tostring(a1) end
                        return k
                    end
                }
            }
            lm = LookupManager:new(plugin)
        end)

        it("lookupAll prioritizes current story entity when identical names exist", function()
            local results = lm:lookupAll("Jonathan Small")
            assert.are.equal(2, #results)
            -- Both have score 100, but story_2 (current story) must be ranked first
            assert.are.equal("story_2", results[1].item.story_id)
            assert.are.equal("The Sign of Four", results[1].item.story_title)
            assert.are.equal("story_1", results[2].item.story_id)
        end)

        it("handleLookup disambiguates candidate buttons with story title", function()
            local shown_dialog = nil
            package.loaded["ui/widget/buttondialog"] = {
                new = function(self, opts)
                    shown_dialog = opts
                    return opts
                end
            }

            lm:handleLookup("Jonathan Small")

            assert.is_not_nil(shown_dialog)
            local buttons = shown_dialog.buttons
            -- Button 1: Current story (The Sign of Four)
            assert.are.equal("Jonathan Small (The Sign of Four)", buttons[1][1].text)
            -- Button 2: Other story (A Study in Scarlet)
            assert.are.equal("Jonathan Small (A Study in Scarlet)", buttons[2][1].text)
        end)
    end)

    describe("Mentions Story Scoping", function()
        local mentions_mod

        before_each(function()
            mentions_mod = require("xray_mentions")
        end)

        it("buildMentionsMenuItems filters mentions to within the entity's story page boundaries", function()
            local plugin = {
                isAnthologyMode = function() return true end,
                book_data = { story_toc_depth = 1 },
                chapter_analyzer = {
                    getStoryMap = function()
                        local s1 = { story_id = "story_1", story_title = "Story 1", start_page = 10, end_page = 50 }
                        local s2 = { story_id = "story_2", story_title = "Story 2", start_page = 60, end_page = 100 }
                        return {
                            stories = { s1, s2 },
                            by_id = { story_1 = s1, story_2 = s2 },
                        }
                    end
                },
                resolveEntityStory = function(self, item)
                    return item.story_id, item.story_title
                end,
                getCurrentPage = function() return 200 end,
                loc = { t = function(self, k) return k end }
            }

            local entity_s1 = {
                name = "Inspector Lestrade",
                story_id = "story_1",
                mentions = {
                    { page = 5, snippet = "Mention before story" },
                    { page = 20, snippet = "Inside story 1" },
                    { page = 35, snippet = "Still inside story 1" },
                    { page = 70, snippet = "Mention in story 2 (leak)" },
                }
            }

            local items = mentions_mod.buildMentionsMenuItems(plugin, entity_s1)
            -- Items include: Refresh Mentions, then page 20, page 35
            -- Pages 5 and 70 must be filtered out
            local page_mentions = {}
            for _, it in ipairs(items) do
                local pg = it.text:match("^p%.(%d+)")
                if pg then table.insert(page_mentions, tonumber(pg)) end
            end

            assert.are.equal(2, #page_mentions)
            assert.are.equal(20, page_mentions[1])
            assert.are.equal(35, page_mentions[2])
        end)
    end)

end)
