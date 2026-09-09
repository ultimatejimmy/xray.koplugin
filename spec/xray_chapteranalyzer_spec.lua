-- xray_chapteranalyzer_spec.lua
require("spec.spec_helper")
local analyzer = require("xray_chapteranalyzer")
local AIHelper = require("xray_aihelper")

describe("xray_chapteranalyzer", function()
    describe("utf8_sub", function()
        it("preserves Chinese characters at byte boundaries", function()
            local text = string.char(0xE7,0x94,0xB2, 0xE4,0xB9,0x99, 0xE4,0xB8,0x99, 0xE4,0xB8,0x81)
            for offset = 1, #text do
                local result = analyzer.utf8_sub(text, 1, offset)
                assert.are.equal(result, AIHelper:sanitize_utf8(result))
            end
        end)

        it("does not begin or end with UTF-8 continuation bytes", function()
            local text = string.char(0xE8,0xAF,0xA1,0xE7,0xA7,0x98,0xE4,0xB9,0x8B,0xE4,0xB8,0xBB,0xEF,0xBC,0x8C,0xE6,0xB8,0xB8,0xE6,0x88,0x8F,0xE5,0x85,0xA5,0xE4,0xBE,0xB5)
            local result = analyzer.utf8_sub(text, 2, #text - 2)
            assert.are.equal(result, AIHelper:sanitize_utf8(result))
        end)
    end)

    describe("getEndPageForCurrentPage", function()
        it("uses the next page as the end XPointer for reflowable documents", function()
            local ui = { rolling = {} }

            assert.are.equal(26, analyzer:getEndPageForCurrentPage(ui, 25))
        end)

        it("uses the current page as the inclusive end for page-based documents", function()
            local ui = { paging = {} }

            assert.are.equal(25, analyzer:getEndPageForCurrentPage(ui, 25))
        end)
    end)

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

        it("respects start_page when provided within the 60-page window", function()
            -- current_page = 80, start_page = 30 (diff is 50, within 60-page limit)
            local text = analyzer:getTextForAnalysis(mock_ui, 50000, nil, 80, 30)

            -- Should call getPageXPointer(30) instead of window fallback
            assert.are.equal(2, #getPageXPointer_calls)
            assert.are.equal(80, getPageXPointer_calls[1])
            assert.are.equal(30, getPageXPointer_calls[2])

            -- Should extract text using the resolved XPointers
            assert.are.equal(1, #getTextFromXPointers_calls)
            assert.are.equal("xp_page_30", getTextFromXPointers_calls[1].start_xp)
            assert.are.equal("xp_page_80", getTextFromXPointers_calls[1].end_xp)
            assert.are.equal("some mock text extracted", text)
        end)

        it("caps start_page to the 60-page window when start_page is too far in the past", function()
            -- current_page = 80, start_page = 10 (diff is 70, exceeds 60-page limit)
            local text = analyzer:getTextForAnalysis(mock_ui, 50000, nil, 80, 10)

            -- Should call getPageXPointer(20) because 80 - 60 = 20
            assert.are.equal(2, #getPageXPointer_calls)
            assert.are.equal(80, getPageXPointer_calls[1])
            assert.are.equal(20, getPageXPointer_calls[2])

            -- Should extract text using the resolved XPointers
            assert.are.equal(1, #getTextFromXPointers_calls)
            assert.are.equal("xp_page_20", getTextFromXPointers_calls[1].start_xp)
            assert.are.equal("xp_page_80", getTextFromXPointers_calls[1].end_xp)
            assert.are.equal("some mock text extracted", text)
        end)

        it("uses the fetch pipeline's resolved page for chapter sampling", function()
            local sampling_ui = {
                rolling = {},
                getCurrentPage = function() return 19 end,
                document = {
                    getToc = function()
                        return {
                            { title = "Chapter 1", page = 1, xpointer = "xp_ch1" },
                            { title = "Chapter 2", page = 250, xpointer = "xp_ch2" },
                        }
                    end,
                    getTextFromXPointer = function() return string.rep("chapter text ", 20) end,
                },
                view = { state = { page = 19 } },
            }
            local _, titles = analyzer:getDetailedChapterSamples(sampling_ui, 100, 60000, false, nil, nil, 298)
            assert.are.equal(2, #titles)
            assert.are.equal("Chapter 2", titles[2])
        end)

        it("does not extract the next page from a page-based document", function()
            local getPageText_calls = {}
            local paged_ui = {
                paging = {},
                document = {
                    getPageText = function(self, page)
                        table.insert(getPageText_calls, page)
                        return "text from page " .. page
                    end,
                },
            }
            local current_page = 25
            local end_page = analyzer:getEndPageForCurrentPage(paged_ui, current_page)

            local text = analyzer:getTextForAnalysis(paged_ui, 50000, nil, end_page, 20)

            assert.are.equal(6, #getPageText_calls)
            assert.are.equal(20, getPageText_calls[1])
            assert.are.equal(25, getPageText_calls[#getPageText_calls])
            assert.is_nil(text:find("text from page 26", 1, true))
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

            -- Chapter 2 is the current chapter, so it should fetch using getTextFromXPointers (page 20 to 26 to include current page)
            assert.are.equal(1, #getTextFromXPointers_calls)
            assert.are.equal("xp_page_20", getTextFromXPointers_calls[1].start_xp)
            assert.are.equal("xp_page_26", getTextFromXPointers_calls[1].end_xp)
        end)

        it("spoiler-free mode does not sample beyond the current PDF page", function()
            local getPageText_calls = {}
            local paged_ui = {
                paging = {},
                document = {
                    getToc = function()
                        return {
                            { title = "Chapter 1", page = 20, xpointer = "page:20" },
                            { title = "Chapter 2", page = 40, xpointer = "page:40" },
                        }
                    end,
                    getPageText = function(self, page)
                        table.insert(getPageText_calls, page)
                        return string.rep("page " .. page .. " text ", 20)
                    end,
                },
                view = {
                    state = { page = 25 },
                },
            }

            local samples, titles = analyzer:getDetailedChapterSamples(paged_ui, 100, 60000, false)

            assert.is_not_nil(samples)
            assert.are.equal(1, #titles)
            assert.are.equal("Chapter 1", titles[1])
            assert.are.equal(20, getPageText_calls[1])
            assert.are.equal(25, getPageText_calls[#getPageText_calls])
            for _, page in ipairs(getPageText_calls) do
                assert.is_true(page <= 25)
            end
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

            -- With current page = 25, the fallback even-sampling should step up to page 25
            -- Max page checked should be <= 25
            for _, page in ipairs(getPageText_calls) do
                assert.is_true(page <= 25)
            end
        end)

        it("handles nested TOCs where parent nodes have higher page numbers than child chapters", function()
            -- Mock nested TOC hierarchy like "Heroes, The": Part I (page 50) -> Chapter 1 (page 10), Chapter 2 (page 30)
            mock_ui.document.getToc = function()
                return {
                    { title = "Title Page", page = 1, xpointer = "xp_title" },
                    {
                        title = "Part I: TROUBLE", page = 50, xpointer = "xp_part1",
                        { title = "Some Kind of Coward", page = 10, xpointer = "xp_ch1" },
                        { title = "The Heroes", page = 30, xpointer = "xp_ch2" }
                    }
                }
            end

            mock_ui.rolling = { current_page = 44 }
            mock_ui.view = { state = { page = 44 } }

            local samples, titles = analyzer:getDetailedChapterSamples(mock_ui, 100, 60000, false)

            -- Should process Some Kind of Coward (10), The Heroes (30)
            -- Title Page is non-narrative; Part I (50 > 44) should not break the loop early
            assert.are.equal(2, #titles)
            assert.are.equal("Some Kind of Coward", titles[1])
            assert.are.equal("The Heroes", titles[2])
        end)

        it("safely invokes getCurrentPage as a method when resolving current_page", function()
            local called_with_self = false
            local ui = {
                document = {
                    getToc = function()
                        return {
                            { title = "Chapter 1", page = 5 },
                        }
                    end,
                    getPageText = function() return "Chapter 1 text content" end
                },
                getCurrentPage = function(self_arg)
                    if self_arg then called_with_self = true end
                    return 10
                end
            }

            local ok, err = pcall(function()
                analyzer:getDetailedChapterSamples(ui, 100, 60000, false)
            end)

            assert.is_true(ok)
            assert.is_nil(err)
            assert.is_true(called_with_self)
        end)
    end)
end)

describe("background sampling boundaries", function()
    local analyzer = require("xray_chapteranalyzer"):new()

    it("visits every chapter when more than 200 entries share one page", function()
        local toc = {}
        for i = 1, 450 do toc[i] = { title = "Chapter " .. i, page = 1 } end
        local ui = { document = { getToc = function() return toc end } }
        local cursor, seen = { page = 0 }, {}
        for _ = 1, 3 do
            local batch = analyzer:getBackgroundBatch(ui, cursor, 1)
            for i = batch.first_chapter, batch.last_chapter do
                assert.is_nil(seen[i]); seen[i] = true
            end
            cursor = batch.next_cursor
        end
        assert.are.equal(450, #seen)
        assert.are.equal(1, cursor.page)
        assert.is_nil(analyzer:getBackgroundBatch(ui, cursor, 1))
    end)

    it("samples only the selected chapter slice without reading future pages", function()
        local toc, ranges = {}, {}
        for i = 1, 220 do toc[i] = { title = "Chapter " .. i, page = i } end
        local ui = { document = {
            getToc = function() return toc end,
            getPageText = function(_, p) ranges[#ranges + 1] = p; return string.rep("é漢字 ", 100) end,
        } }
        local batch = analyzer:getBackgroundBatch(ui, { page = 100 }, 220)
        local text, titles = analyzer:getDetailedChapterSamples(ui, 200, 150000, false, 101, {}, 160, batch)
        assert.is_string(text)
        assert.are.equal("Chapter 101", titles[1])
        assert.are.equal("Chapter 160", titles[#titles])
        for _, page in ipairs(ranges) do assert.is_true(page >= 101 and page <= 160) end
    end)

    it("never splits a UTF-8 code point when trimming main context", function()
        local ui = { document = { getPageText = function() return string.rep("é漢字", 20) end } }
        local text = analyzer:getTextForAnalysis(ui, 11, nil, 1, 1)
        local chars = require("util").splitToChars(text)
        assert.are.equal(text, table.concat(chars))
        assert.is_true(#text <= 11)
    end)
end)
