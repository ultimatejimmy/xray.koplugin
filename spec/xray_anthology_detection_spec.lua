-- spec/xray_anthology_detection_spec.lua
require("spec.spec_helper")

local analyzer = require("xray_chapteranalyzer")
local data_mod = require("xray_data")
local Main = require("main")

describe("Anthology Detection & Edge Case Handling", function()
    local function createMockPlugin(ui, book_data)
        return {
            ui = ui,
            book_data = book_data,
            detectAnthologyFromMetadata = Main.detectAnthologyFromMetadata,
            isAnthologyMode = Main.isAnthologyMode,
            isEntityRecurring = Main.isEntityRecurring,
            getEntityStoryRole = Main.getEntityStoryRole,
            collectAnthologySignals = Main.collectAnthologySignals,
            ensureAnthologyDecision = Main.ensureAnthologyDecision,
            detectBookTypeHeuristic = Main.detectBookTypeHeuristic,
            persistBookData = Main.persistBookData or function() end,
            retagEntitiesByStory = Main.retagEntitiesByStory or function() end,
        }
    end

    describe("Gutenberg & Non-Story Entry Filtering", function()
        it("identifies Gutenberg licenses, title page, and front/back matter", function()
            local ca = analyzer:new{}
            local book_title = "The Adventures of Sherlock Holmes"

            -- NCX entry 1 matching book title
            assert.is_true(ca:isNonStoryEntry("The Adventures of Sherlock Holmes", book_title))
            assert.is_true(ca:isNonStoryEntry("THE ADVENTURES OF SHERLOCK HOLMES", book_title))

            -- Gutenberg license
            assert.is_true(ca:isNonStoryEntry("THE FULL PROJECT GUTENBERG™ LICENSE", book_title))
            assert.is_true(ca:isNonStoryEntry("Project Gutenberg License", book_title))

            -- Editor notes and front matter
            assert.is_true(ca:isNonStoryEntry("Editor's Note", book_title))
            assert.is_true(ca:isNonStoryEntry("Note on the Text", book_title))
            assert.is_true(ca:isNonStoryEntry("Table of Contents", book_title))
            assert.is_true(ca:isNonStoryEntry("Introduction", book_title))

            -- Real stories should NOT be filtered
            assert.is_false(ca:isNonStoryEntry("A Scandal in Bohemia", book_title))
            assert.is_false(ca:isNonStoryEntry("The Red-Headed League", book_title))
            assert.is_false(ca:isNonStoryEntry("The Dead", book_title))
        end)

        it("reverts introduction filter from general non-narrative chapters in novels", function()
            -- Introduction should NOT be filtered in novel narrative checks (xray_data)
            assert.is_false(data_mod:isNonNarrativeChapter("Introduction"))
            assert.is_false(data_mod:isNonNarrativeChapter("Introduction: The Journey Begins"))
        end)
    end)

    describe("Metadata Detection with Plural 'stories'", function()
        it("matches plural stories in subject/genre for Sherlock Holmes", function()
            local plugin = createMockPlugin({})
            local props = {
                title = "The Adventures of Sherlock Holmes",
                subject = "Detective and mystery stories, English",
            }
            assert.is_true(plugin:detectAnthologyFromMetadata(props, props.title))
        end)

        it("does not falsely trigger on novel subjects like Fiction or Novel", function()
            local plugin = createMockPlugin({})
            local props = {
                title = "Harry Potter and the Sorcerer's Stone",
                subject = "Wizards -- Fiction; Magic -- Fiction; England -- Juvenile fiction",
            }
            assert.is_false(plugin:detectAnthologyFromMetadata(props, props.title))
        end)
    end)

    describe("Poetry Keyword Bug Regression", function()
        it("does not classify an anthology of short stories as poetry", function()
            local plugin = createMockPlugin({
                document = {
                    file = "short_stories_anthology.epub",
                    getProps = function()
                        return {
                            title = "The Best American Short Stories Anthology",
                            subject = "Short stories, American",
                        }
                    end
                }
            })
            local book_path = "short_stories_anthology.epub"
            local label = plugin:detectBookTypeHeuristic(book_path)
            -- Should be prose_fiction, NOT poetry
            assert.are_not.equal("poetry", label)
            assert.are.equal("prose_fiction", label)
        end)
    end)

    describe("Signals Collection & Named Ratio", function()
        it("computes high named ratio for anthology with titled stories", function()
            local mock_ui = {
                document = {
                    file = "sherlock.epub",
                    getNumberOfPages = function() return 300 end,
                    getProps = function()
                        return {
                            title = "The Adventures of Sherlock Holmes",
                            subject = "Detective and mystery stories, English",
                        }
                    end,
                    getToc = function()
                        return {
                            { title = "The Adventures of Sherlock Holmes", page = 1 }, -- NCX title
                            { title = "A Scandal in Bohemia", page = 10 },
                            { title = "The Red-Headed League", page = 35 },
                            { title = "A Case of Identity", page = 60 },
                            { title = "The Boscombe Valley Mystery", page = 85 },
                            { title = "The Five Orange Pips", page = 110 },
                            { title = "THE FULL PROJECT GUTENBERG LICENSE", page = 290 },
                        }
                    end
                }
            }
            local plugin = createMockPlugin(mock_ui)
            local signals = plugin:collectAnthologySignals()
            assert.is_true(signals.meta_match)
            assert.are.equal(5, signals.story_count) -- NCX title and License filtered out
            assert.are.equal(1.0, signals.named_ratio) -- All 5 stories have distinct non-generic names
        end)

        it("computes low named ratio for a standard chapter-numbered novel", function()
            local mock_ui = {
                document = {
                    file = "novel.epub",
                    getNumberOfPages = function() return 300 end,
                    getProps = function()
                        return {
                            title = "Great Expectations",
                            subject = "Fiction",
                        }
                    end,
                    getToc = function()
                        return {
                            { title = "Chapter 1", page = 5 },
                            { title = "Chapter 2", page = 15 },
                            { title = "Chapter 3", page = 25 },
                            { title = "Chapter 4", page = 35 },
                            { title = "Chapter 5", page = 45 },
                        }
                    end
                }
            }
            local plugin = createMockPlugin(mock_ui)
            local signals = plugin:collectAnthologySignals()
            assert.is_false(signals.meta_match)
            assert.are.equal(5, signals.story_count)
            assert.are.equal(0.0, signals.named_ratio) -- None are distinct story titles
        end)
    end)

    describe("ensureAnthologyDecision", function()
        it("auto-enables anthology mode for high confidence signals without AI call", function()
            local mock_ui = {
                document = {
                    file = "sherlock_test.epub",
                    getNumberOfPages = function() return 300 end,
                    getProps = function()
                        return {
                            title = "The Adventures of Sherlock Holmes",
                            subject = "Detective and mystery stories, English",
                        }
                    end,
                    getToc = function()
                        return {
                            { title = "A Scandal in Bohemia", page = 10 },
                            { title = "The Red-Headed League", page = 35 },
                            { title = "A Case of Identity", page = 60 },
                        }
                    end
                }
            }
            local plugin = createMockPlugin(mock_ui, {})

            local decided = nil
            plugin:ensureAnthologyDecision(function(is_anth)
                decided = is_anth
            end)

            assert.is_true(decided)
            assert.is_true(plugin.book_data.anthology_detected)
            assert.are.equal("anthology", plugin.book_data.book_type)
            assert.are.equal("anthology", plugin.book_type)
            assert.is_true(plugin:isAnthologyMode())
        end)

        it("rejects anthology mode for chapter-based novels without AI call", function()
            local mock_ui = {
                document = {
                    file = "novel_test.epub",
                    getNumberOfPages = function() return 300 end,
                    getProps = function()
                        return {
                            title = "A Normal Novel",
                            subject = "Fiction",
                        }
                    end,
                    getToc = function()
                        return {
                            { title = "Chapter 1", page = 5 },
                            { title = "Chapter 2", page = 15 },
                            { title = "Chapter 3", page = 25 },
                        }
                    end
                }
            }
            local plugin = createMockPlugin(mock_ui, {})

            local decided = nil
            plugin:ensureAnthologyDecision(function(is_anth)
                decided = is_anth
            end)

            assert.is_false(decided)
            assert.is_false(plugin.book_data.anthology_detected)
            assert.is_false(plugin:isAnthologyMode())
        end)

        it("respects explicit user override over any detection", function()
            local plugin = createMockPlugin(nil, {
                book_mode_override = "fiction",
                anthology_detected = true,
            })
            assert.is_false(plugin:isAnthologyMode())

            plugin.book_data.book_mode_override = "anthology"
            assert.is_true(plugin:isAnthologyMode())
        end)
    end)
end)
