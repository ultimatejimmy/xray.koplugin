-- xray_chapteranalyzer_spec.lua
require("spec.spec_helper")
local analyzer = require("xray_chapteranalyzer")

describe("xray_chapteranalyzer", function()
    describe("countMentions", function()
        it("counts exact mentions correctly", function()
            local text = "Alice went to the park. Alice saw a bird."
            assert.are.equal(2, analyzer:countMentions(text, "Alice"))
        end)

        it("counts case-insensitive mentions", function()
            local text = "Alice went to the park. alice saw a bird."
            assert.are.equal(2, analyzer:countMentions(text, "Alice"))
        end)

        it("handles word boundaries for short names", function()
            -- Short names (< 4 chars) should respect word boundaries
            local text = "Jo went to Jordan's house. Jo is happy."
            -- "Jo" appears twice as a word. "Jordan" contains "Jo" but shouldn't count.
            assert.are.equal(2, analyzer:countMentions(text, "Jo"))
        end)
    end)

    describe("findCharactersInText", function()
        local chars = {
            { name = "Alice", id = 1 },
            { name = "Bob", id = 2 },
            { name = "Charlie", id = 3 }
        }

        it("finds present characters and sorts by count", function()
            local text = "Alice saw Bob. Bob waved at Alice. Bob is tall."
            local found = analyzer:findCharactersInText(text, chars)
            
            assert.are.equal(2, #found)
            assert.are.equal("Bob", found[1].character.name)
            assert.are.equal(3, found[1].count)
            assert.are.equal("Alice", found[2].character.name)
            assert.are.equal(2, found[2].count)
        end)

        it("handles first name matching", function()
            local chars_with_full_names = {
                { name = "Alice Liddell", id = 1 }
            }
            local text = "Alice went down the rabbit hole."
            local found = analyzer:findCharactersInText(text, chars_with_full_names)
            
            assert.are.equal(1, #found)
            assert.are.equal("Alice Liddell", found[1].character.name)
        end)
    end)

    describe("getTextForAnalysis", function()
        local mock_ui
        local getPageXPointer_calls
        local getTextFromXPointers_calls

        before_each(function()
            getPageXPointer_calls = {}
            getTextFromXPointers_calls = {}

            mock_ui = {
                rolling = {}, -- reflowable
                document = {
                    getPageCount = function() return 100 end,
                    getXPointer = function() return "mock_current_xp" end,
                    getPageXPointer = function(self, page)
                        table.insert(getPageXPointer_calls, page)
                        return "xp_page_" .. page
                    end,
                    getTextFromXPointers = function(self, start_xp, end_xp)
                        table.insert(getTextFromXPointers_calls, { start_xp = start_xp, end_xp = end_xp })
                        return "some mock text extracted"
                    end,
                    gotoXPointer = function() end,
                    gotoPage = function() end
                },
                getCurrentPage = function() return 80 end
            }
        end)

        it("uses a window of 60 pages when start_page is not provided", function()
            local text = analyzer:getTextForAnalysis(mock_ui, 50000, nil, 80)

            -- Should resolve window_start = math.max(1, 80 - 60) = 20
            -- Should call getPageXPointer(20) and getPageXPointer(80)
            assert.are.equal(2, #getPageXPointer_calls)
            assert.are.equal(80, getPageXPointer_calls[1])
            assert.are.equal(20, getPageXPointer_calls[2])

            -- Should extract text using the resolved XPointers
            assert.are.equal(1, #getTextFromXPointers_calls)
            assert.are.equal("xp_page_20", getTextFromXPointers_calls[1].start_xp)
            assert.are.equal("xp_page_80", getTextFromXPointers_calls[1].end_xp)
            assert.are.equal("some mock text extracted", text)
        end)

        it("respects start_page when provided", function()
            local text = analyzer:getTextForAnalysis(mock_ui, 50000, nil, 80, 10)

            -- Should call getPageXPointer(10) instead of window fallback
            assert.are.equal(2, #getPageXPointer_calls)
            assert.are.equal(80, getPageXPointer_calls[1])
            assert.are.equal(10, getPageXPointer_calls[2])

            -- Should extract text using the resolved XPointers
            assert.are.equal(1, #getTextFromXPointers_calls)
            assert.are.equal("xp_page_10", getTextFromXPointers_calls[1].start_xp)
            assert.are.equal("xp_page_80", getTextFromXPointers_calls[1].end_xp)
            assert.are.equal("some mock text extracted", text)
        end)
    end)

    describe("getDetailedChapterSamples", function()
        local mock_ui
        local getTextFromXPointers_calls
        local getTextFromXPointer_calls

        before_each(function()
            getTextFromXPointers_calls = {}
            getTextFromXPointer_calls = {}

            mock_ui = {
                rolling = {}, -- reflowable
                document = {
                    getPageCount = function() return 100 end,
                    getXPointer = function() return "mock_current_xp" end,
                    getPageXPointer = function(self, page)
                        return "xp_page_" .. page
                    end,
                    getToc = function()
                        return {
                            { title = "Chapter 1", page = 1, xpointer = "xp_ch1" },
                            { title = "Chapter 2", page = 20, xpointer = "xp_ch2" },
                            { title = "Chapter 3", page = 40, xpointer = "xp_ch3" },
                        }
                    end,
                    getTextFromXPointer = function(self, xp)
                        table.insert(getTextFromXPointer_calls, xp)
                        return "mock text for full chapter " .. xp .. " and it is very long and has start, middle and end segments"
                    end,
                    getTextFromXPointers = function(self, start_xp, end_xp)
                        table.insert(getTextFromXPointers_calls, { start_xp = start_xp, end_xp = end_xp })
                        return "mock text from page range: " .. start_xp .. " to " .. end_xp .. " and it is also very long and has start, middle and end segments"
                    end,
                    gotoXPointer = function() end,
                    gotoPage = function() end
                },
                view = {
                    state = { page = 25 } -- User is on page 25 (inside Chapter 2)
                }
            }
        end)

        it("spoiler-free mode only extracts current chapter up to current page", function()
            local samples, titles = analyzer:getDetailedChapterSamples(mock_ui, 100, 60000, false)

            -- Should only process chapters 1 and 2 (Chapter 3 starts at page 40 > 25)
            assert.are.equal(2, #titles)
            assert.are.equal("Chapter 1", titles[1])
            assert.are.equal("Chapter 2", titles[2])

            -- Chapter 1 is fully read, so it should fetch using getTextFromXPointer
            assert.are.equal(1, #getTextFromXPointer_calls)
            assert.are.equal("xp_ch1", getTextFromXPointer_calls[1])

            -- Chapter 2 is the current chapter, so it should fetch using getTextFromXPointers (page 20 to 25)
            assert.are.equal(1, #getTextFromXPointers_calls)
            assert.are.equal("xp_page_20", getTextFromXPointers_calls[1].start_xp)
            assert.are.equal("xp_page_25", getTextFromXPointers_calls[1].end_xp)
        end)

        it("spoiler-free mode limits NO TOC fallback range to current page", function()
            -- Mock no TOC
            mock_ui.document.getToc = function() return nil end
            
            -- We track getPageText calls
            local getPageText_calls = {}
            mock_ui.document.getPageText = function(self, page)
                table.insert(getPageText_calls, page)
                return "mock page text of page " .. page .. " which is long enough to count"
            end

            local samples, titles = analyzer:getDetailedChapterSamples(mock_ui, 100, 60000, false)

            -- With current page = 25, the fallback even-sampling should step up to page 25
            -- Max page checked should be <= 25
            for _, page in ipairs(getPageText_calls) do
                assert.is_true(page <= 25)
            end
        end)
    end)
end)
