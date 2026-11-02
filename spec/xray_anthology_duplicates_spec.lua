-- spec/xray_anthology_duplicates_spec.lua
require("spec.spec_helper")

local analyzer = require("xray_chapteranalyzer")
local data_mod = require("xray_data")
local Main = require("main")
local EntityListOverlay = require("xray_entity_list")
local ui_mod = require("xray_ui")

describe("Anthology-Aware Duplicate Detection & Linking", function()
    local function createMockPlugin(ui, book_data)
        local p = {
            ui = ui,
            book_data = book_data or {},
            characters = {},
            locations = {},
            terms = {},
            historical_figures = {},
            timeline = {},
            loc = {
                t = function(self, key, ...)
                    return key
                end
            },
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
            markStoryPresence = Main.markStoryPresence,
            getStoryPresence = Main.getStoryPresence,
            migrateStoryPresence = Main.migrateStoryPresence,
            canonicalNameKey = data_mod.canonicalNameKey,
            namesMatchCanonical = data_mod.namesMatchCanonical,
            isMoreCompleteName = data_mod.isMoreCompleteName,
            promoteName = data_mod.promoteName,
            mergeEntryItems = data_mod.mergeEntryItems,
            mergeEntries = data_mod.mergeEntries,
            linkEntriesAcrossStories = data_mod.linkEntriesAcrossStories,
            buildDuplicateCandidates = ui_mod.buildDuplicateCandidates,
            resolveDuplicatePair = ui_mod.resolveDuplicatePair,
            makeRejectKey = ui_mod.makeRejectKey,
            isPairRejected = ui_mod.isPairRejected,
            filterValidDuplicatePairs = ui_mod.filterValidDuplicatePairs,
            walkDuplicatePairs = ui_mod.walkDuplicatePairs,
            log = function() end,
            persistBookData = function() end,
        }
        return p
    end

    local mock_ui

    before_each(function()
        mock_ui = {
            document = {
                file = "test_sherlock.epub",
                getNumberOfPages = function() return 300 end,
                getPageCount = function() return 300 end,
                getProps = function()
                    return {
                        title = "The Adventures of Sherlock Holmes",
                        subject = "Detective and mystery stories, English",
                    }
                end,
                getToc = function()
                    return {
                        { title = "A Scandal in Bohemia", page = 10 },
                        { title = "The Red-Headed League", page = 40 },
                        { title = "A Case of Identity", page = 70 },
                    }
                end
            },
            getCurrentPage = function() return 45 end, -- in story_2
        }
    end)

    describe("Component A: canonicalNameKey & namesMatchCanonical", function()
        it("normalizes Dr. John Watson, Doctor John Watson, and John Watson to identical core", function()
            local c1, t1 = data_mod:canonicalNameKey("Dr. John Watson")
            local c2, t2 = data_mod:canonicalNameKey("Doctor John Watson")
            local c3, t3 = data_mod:canonicalNameKey("John Watson")

            assert.are.equal("john watson", c1)
            assert.are.equal("john watson", c2)
            assert.are.equal("john watson", c3)

            assert.are.equal("dr", t1)
            assert.are.equal("dr", t2)
            assert.is_nil(t3)

            assert.is_true(data_mod:namesMatchCanonical("Dr. John Watson", "Doctor John Watson"))
            assert.is_true(data_mod:namesMatchCanonical("Dr. John Watson", "John Watson"))
            assert.is_true(data_mod:namesMatchCanonical("Doctor John Watson", "John Watson"))
        end)

        it("handles titles, suffixes, and articles properly", function()
            local c1, t1 = data_mod:canonicalNameKey("The Doctor")
            assert.are.equal("doctor", c1)
            assert.is_nil(t1)

            local c2, t2 = data_mod:canonicalNameKey("Mrs. Hudson")
            assert.are.equal("hudson", c2)
            assert.are.equal("mrs", t2)

            local c3, t3 = data_mod:canonicalNameKey("John Smith Jr.")
            assert.are.equal("john smith", c3)
            assert.is_nil(t3)
        end)

        it("prevents conflicting titles from matching", function()
            assert.is_false(data_mod:namesMatchCanonical("Mr. Hudson", "Mrs. Hudson"))
            assert.is_true(data_mod:namesMatchCanonical("Mr. Hudson", "Hudson"))
        end)

        it("deduplicateByName collapses honorific variants within the same story", function()
            local list = {
                { name = "John Watson", story_id = "story_1", mentions = { { page = 12 } } },
                { name = "Dr. John Watson", story_id = "story_1", mentions = { { page = 15 } } },
                { name = "Doctor John Watson", story_id = "story_1", mentions = { { page = 18 } } },
                { name = "John Watson", story_id = "story_2", mentions = { { page = 45 } } },
                { name = "Mr. Hudson", story_id = "story_1" },
                { name = "Mrs. Hudson", story_id = "story_1" },
            }

            local mock_caller = {
                isAnthologyMode = function() return true end
            }

            local result = data_mod:deduplicateByName(list, "name", mock_caller)
            
            -- Watson in story_1 should collapse to 1 entry; Watson in story_2 stays separate; Mr & Mrs Hudson stay separate
            -- Total entries: 1 (Watson s1) + 1 (Watson s2) + 2 (Hudson) = 4
            assert.are.equal(4, #result)

            local s1_watson = nil
            for _, it in ipairs(result) do
                assert.is_nil(it._dedup_title)
                if it.story_id == "story_1" and (it.name:find("Watson")) then
                    s1_watson = it
                end
            end
            assert.is_not_nil(s1_watson)
            assert.are.equal(3, #s1_watson.mentions)
        end)

        it("mergeEntryItems operates by reference and merges mentions", function()
            local a = { name = "Arthur", story_id = "story_1", aliases = {"Art"}, mentions = {{page=1}} }
            local b = { name = "Artie", story_id = "story_1", mentions = {{page=2}} }
            local list = { a, b }

            local ok, old_name = data_mod:mergeEntryItems(list, a, b)
            assert.is_true(ok)
            assert.are.equal(1, #list)
            assert.are.equal(a, list[1])
            assert.are.equal(2, #a.mentions)
            assert.is_false(data_mod:mergeEntryItems(list, a, a))
        end)

        it("linkEntriesAcrossStories links recurring entities without deleting the other story entry", function()
            local anchor = { name = "Sherlock Holmes", story_id = "story_1", aliases = {"Holmes"} }
            local local_it = { name = "Holmes", story_id = "story_2", aliases = {} }
            local list = { anchor, local_it }

            local survivor = data_mod:linkEntriesAcrossStories(list, anchor, local_it)
            assert.are.equal(local_it, survivor)
            assert.are.equal(2, #list)
            assert.is_true(anchor.is_recurring)
            assert.is_true(local_it.is_recurring)
            assert.are.equal("Sherlock Holmes", local_it.name)
        end)
    end)

    describe("Component B: Presence helpers & Recurring detection", function()
        it("getStoryPresence and markStoryPresence index canonical buckets and migrate correctly", function()
            local p = createMockPlugin(mock_ui, {
                book_type = "anthology",
                story_presence = {
                    ["Dr. John Watson"] = { ["story_1"] = true },
                    ["John Watson"] = { ["story_2"] = true },
                }
            })

            local pres = p:getStoryPresence("Doctor John Watson")
            assert.is_not_nil(pres)
            assert.is_true(pres["story_1"])
            assert.is_true(pres["story_2"])

            p:migrateStoryPresence("John Watson", "Doctor John Watson")
            assert.is_nil(p.book_data.story_presence["John Watson"])
            assert.is_not_nil(p.book_data.story_presence["Doctor John Watson"])

            local ent = { name = "Dr. John Watson" }
            assert.is_true(p:isEntityRecurring(ent))
        end)
    end)

    describe("Component C: buildStorySections canonical de-dupe", function()
        it("shows only one Watson row in current story preferring home copy", function()
            local p = createMockPlugin(mock_ui, {
                book_type = "anthology",
                story_presence = {
                    ["John Watson"] = { ["toc_2"] = true, ["toc_3"] = true },
                }
            })
            p.characters = {
                { name = "Dr. John Watson", story_id = "toc_2", is_recurring = true },
                { name = "John Watson", story_id = "toc_3", is_recurring = true },
            }

            local overlay = EntityListOverlay:new{
                plugin = p,
                mode = "characters",
            }

            local sections = overlay:buildStorySections(p.characters)
            local current_section_items = {}
            local in_curr = false
            for _, item in ipairs(sections) do
                if item.is_section_header and item.section_id == "current" then
                    in_curr = true
                elseif item.is_section_header then
                    in_curr = false
                elseif in_curr then
                    table.insert(current_section_items, item)
                end
            end

            assert.are.equal(1, #current_section_items)
            assert.are.equal("toc_3", current_section_items[1].story_id)
        end)
    end)

    describe("Component D: Duplicate Candidates, Pair Resolution & Walk", function()
        it("buildDuplicateCandidates scopes to current story and present recurring entities", function()
            local p = createMockPlugin(mock_ui, {
                book_type = "anthology",
                story_presence = {
                    ["Sherlock Holmes"] = { ["toc_2"] = true, ["toc_3"] = true },
                    ["Mycroft Holmes"] = { ["toc_2"] = true }, -- not in toc_3
                }
            })
            local cur_story = { story_id = "toc_3", story_title = "The Red-Headed League" }
            local list = {
                { name = "Sherlock Holmes", story_id = "toc_2", is_recurring = true },
                { name = "Sherlock Holmes", story_id = "toc_3", is_recurring = true },
                { name = "Jabez Wilson", story_id = "toc_3" },
                { name = "Mycroft Holmes", story_id = "toc_2", is_recurring = true },
            }

            local candidates = p:buildDuplicateCandidates(list, cur_story)
            assert.are.equal(2, #candidates)
            local names = {}
            for _, it in ipairs(candidates) do table.insert(names, it.name) end
            table.sort(names)
            assert.are.equal("Jabez Wilson", names[1])
            assert.are.equal("Sherlock Holmes", names[2])
        end)

        it("resolveDuplicatePair rejects identical entities and handles cross-story flag", function()
            local p = createMockPlugin(mock_ui, { book_type = "anthology" })
            local cur_story = { story_id = "toc_3" }
            local it_s1 = { name = "Sherlock Holmes", story_id = "toc_2" }
            local it_s2 = { name = "Sherlock", story_id = "toc_3" }
            local candidates = { it_s1, it_s2 }

            local p1, s1 = p:resolveDuplicatePair(candidates, { primary = "Sherlock", secondary = "Sherlock" }, cur_story)
            assert.is_nil(p1)

            local p2, s2, cross = p:resolveDuplicatePair(candidates, { primary = "Sherlock Holmes", secondary = "Sherlock" }, cur_story)
            assert.are.equal(it_s1, p2)
            assert.are.equal(it_s2, s2)
            assert.is_true(cross)
        end)

        it("scoped reject key does not suppress pair in other stories", function()
            local p = createMockPlugin(mock_ui, {
                book_type = "anthology",
                rejected_merge_pairs = {}
            })
            local it_s1_a = { name = "John", story_id = "toc_2" }
            local it_s1_b = { name = "John Doe", story_id = "toc_2" }
            local it_s2_a = { name = "John", story_id = "toc_3" }
            local it_s2_b = { name = "John Doe", story_id = "toc_3" }

            local r_key = p:makeRejectKey(it_s1_a, it_s1_b)
            p.book_data.rejected_merge_pairs[r_key] = true

            assert.is_true(p:isPairRejected(it_s1_a, it_s1_b))
            assert.is_false(p:isPairRejected(it_s2_a, it_s2_b))
        end)
    end)

    describe("Component E: Pending review discard on story change", function()
        it("discards pending review when user has moved to another story", function()
            local p = createMockPlugin(mock_ui, { book_type = "anthology" })
            p.pending_duplicate_review = {
                story_id = "toc_2",
                characters = { { primary = "Holmes", secondary = "Sherlock" } }
            }

            -- mock_ui getCurrentPage is 45, which is toc_3
            assert.are.equal("toc_3", p:getCurrentStory().story_id)

            -- Simulating the check performed on opening the character menu
            if p:isAnthologyMode() and p.pending_duplicate_review and p.pending_duplicate_review.story_id then
                local cs = p.getCurrentStory and p:getCurrentStory()
                if not cs or cs.story_id ~= p.pending_duplicate_review.story_id then
                    p.pending_duplicate_review = nil
                end
            end

            assert.is_nil(p.pending_duplicate_review)
        end)
    end)
end)
