-- spec/xray_horizon_spec.lua
-- Unit tests for Issue #131 (Full Pre-generation & Source-Positioned Entity History),
-- Issue #133 (Offline Prefetch Horizon), and Issue #150 (Spoiler-Free Boundaries).

require("spec/spec_helper")
local xray_ui = require("xray_ui")
local xray_fetch = require("xray_fetch")
local xray_mentions = require("xray_mentions")
local EntityListOverlay = require("xray_entity_list")

describe("xray_horizon_spec", function()
    local plugin

    before_each(function()
        plugin = createMockPlugin()
        for k, v in pairs(xray_ui) do plugin[k] = v end
        for k, v in pairs(xray_fetch) do plugin[k] = v end
        for k, v in pairs(xray_mentions) do plugin[k] = v end
    end)

    describe("isEntityVisibleAtCurrentPosition", function()
        it("should treat legacy entities without visible_from as visible everywhere", function()
            local legacy_char = { name = "Bob", role = "Builder" }
            assert.is_true(plugin:isEntityVisibleAtCurrentPosition(legacy_char, 1, 10))
            assert.is_true(plugin:isEntityVisibleAtCurrentPosition(legacy_char, 5, 200))
        end)

        it("should gate entities strictly by chapter index", function()
            local future_char = {
                name = "Alice",
                visible_from = { chapter_index = 4, chapter_title = "Chapter 4", page_hint = 80 }
            }
            -- Before chapter 4: hidden
            assert.is_false(plugin:isEntityVisibleAtCurrentPosition(future_char, 1, 10))
            assert.is_false(plugin:isEntityVisibleAtCurrentPosition(future_char, 3, 79))
            -- After chapter 4: visible
            assert.is_true(plugin:isEntityVisibleAtCurrentPosition(future_char, 5, 120))
        end)

        it("should support hybrid gating with page_hint in the introductory chapter", function()
            local intro_char = {
                name = "Agent Vance",
                visible_from = { chapter_index = 3, chapter_title = "Chapter 3", page_hint = 65 }
            }
            -- Same chapter, before page 65: hidden
            assert.is_false(plugin:isEntityVisibleAtCurrentPosition(intro_char, 3, 60))
            assert.is_false(plugin:isEntityVisibleAtCurrentPosition(intro_char, 3, 64))
            -- Same chapter, on or after page 65: visible
            assert.is_true(plugin:isEntityVisibleAtCurrentPosition(intro_char, 3, 65))
            assert.is_true(plugin:isEntityVisibleAtCurrentPosition(intro_char, 3, 70))
        end)

        it("should provide full parity across Locations and Terms", function()
            local loc = {
                name = "Hidden Base",
                visible_from = { chapter_index = 5, page_hint = 100 }
            }
            local term = {
                name = "Aetherite",
                visible_from = { chapter_index = 2, page_hint = 30 }
            }
            assert.is_false(plugin:isEntityVisibleAtCurrentPosition(loc, 4, 99))
            assert.is_true(plugin:isEntityVisibleAtCurrentPosition(loc, 5, 101))
            assert.is_false(plugin:isEntityVisibleAtCurrentPosition(term, 2, 25))
            assert.is_true(plugin:isEntityVisibleAtCurrentPosition(term, 2, 35))
        end)

        it("should treat all entities as visible when spoiler_setting is full_book", function()
            local future_char = {
                name = "Alice",
                visible_from = { chapter_index = 10, page_hint = 500 }
            }
            plugin.ai_helper = { settings = { spoiler_setting = "full_book" } }
            assert.is_true(plugin:isEntityVisibleAtCurrentPosition(future_char, 1, 10))
        end)
    end)

    describe("resolveEntityState", function()
        it("should fall back to base fields if entity has no states", function()
            local char = { role = "Doctor", status = "alive", description = "Town physician." }
            local role, status, desc = plugin:resolveEntityState(char, 2, 50)
            assert.are.equal("Doctor", role)
            assert.are.equal("alive", status)
            assert.are.equal("Town physician.", desc)
        end)

        it("should resolve chronological states forward and backward without leaks", function()
            local evolving_char = {
                name = "Sarah",
                role = "Villager",
                status = "alive",
                description = "A quiet farm girl in Oakhaven.",
                states = {
                    {
                        chapter_index = 1,
                        page_hint = 15,
                        role = "Villager",
                        status = "alive",
                        description = "A quiet farm girl in Oakhaven."
                    },
                    {
                        chapter_index = 4,
                        page_hint = 90,
                        role = "Mage Apprentice",
                        status = "alive",
                        description = "A farm girl discovered to possess rare elemental fire magic."
                    },
                    {
                        chapter_index = 8,
                        page_hint = 210,
                        role = "Resistance Leader",
                        status = "alive",
                        description = "Leader of the northern rebellion against the tyrant, formerly a simple farm girl."
                    }
                }
            }

            -- Chapter 2: should see State 1
            local r1, s1, d1 = plugin:resolveEntityState(evolving_char, 2, 30)
            assert.are.equal("Villager", r1)
            assert.are.equal("A quiet farm girl in Oakhaven.", d1)

            -- Chapter 4 before page 90: should still see State 1
            local r2_pre, _, d2_pre = plugin:resolveEntityState(evolving_char, 4, 85)
            assert.are.equal("Villager", r2_pre)
            assert.are.equal("A quiet farm girl in Oakhaven.", d2_pre)

            -- Chapter 4 on page 90: evolves to Mage Apprentice
            local r2, _, d2 = plugin:resolveEntityState(evolving_char, 4, 90)
            assert.are.equal("Mage Apprentice", r2)
            assert.are.equal("A farm girl discovered to possess rare elemental fire magic.", d2)

            -- Backward navigation: reading reverts back to Chapter 2
            local r_back, _, d_back = plugin:resolveEntityState(evolving_char, 2, 35)
            assert.are.equal("Villager", r_back)
            assert.are.equal("A quiet farm girl in Oakhaven.", d_back)

            -- Forward to Chapter 10: reaches Resistance Leader
            local r3, _, d3 = plugin:resolveEntityState(evolving_char, 10, 250)
            assert.are.equal("Resistance Leader", r3)
            assert.are.equal("Leader of the northern rebellion against the tyrant, formerly a simple farm girl.", d3)
        end)

        it("should route resolveDescriptionForPage through resolveEntityState when states exist", function()
            local char_with_states = {
                name = "Lord Kenneth",
                description = "King's advisor.",
                states = {
                    { chapter_index = 1, page_hint = 10, description = "Loyal advisor to the King." },
                    { chapter_index = 5, page_hint = 100, description = "Traitor revealed to be working with rebels." }
                }
            }
            -- Current page 20 (chapter 1)
            plugin.getCurrentChapterIndex = function() return 1 end
            local desc_early = plugin:resolveDescriptionForPage(char_with_states, 20)
            assert.are.equal("Loyal advisor to the King.", desc_early)

            -- Current page 110 (chapter 5)
            plugin.getCurrentChapterIndex = function() return 5 end
            local desc_late = plugin:resolveDescriptionForPage(char_with_states, 110)
            assert.are.equal("Traitor revealed to be working with rebels.", desc_late)
        end)
    end)

    describe("mergeSequentialChapterDelta", function()
        it("should add new entities with visible_from and states", function()
            local delta = {
                new_characters = {
                    {
                        name = "Eldrin",
                        role = "High Elf Ranger",
                        status = "alive",
                        description = "Guards the borders of the Sunwood.",
                        evidence = "Encountered at the forest perimeter."
                    }
                },
                new_locations = {
                    {
                        name = "Sunwood",
                        description = "Ancient forest bathed in perpetual golden twilight."
                    }
                },
                new_terms = {
                    {
                        name = "Sunstone",
                        description = "Luminous crystal that channels solar energy."
                    }
                },
                timeline_event = {
                    chapter = "Chapter 3: The Forest Border",
                    event = "The party reaches the perimeter of the Sunwood and meets Eldrin."
                }
            }

            local chapter_info = {
                title = "Chapter 3: The Forest Border",
                page = 45,
                xpointer = "/6/8!/4/1:0",
                toc_index = 3
            }

            plugin.checkpointHorizonScan = function() end -- mock save
            plugin:mergeSequentialChapterDelta(delta, chapter_info, 3)

            assert.are.equal(1, #plugin.characters)
            local c = plugin.characters[1]
            assert.are.equal("Eldrin", c.name)
            assert.are.equal("High Elf Ranger", c.role)
            assert.is_not_nil(c.visible_from)
            assert.are.equal(3, c.visible_from.chapter_index)
            assert.are.equal(45, c.visible_from.page_hint)
            assert.are.equal(1, #c.states)
            assert.are.equal("High Elf Ranger", c.states[1].role)

            assert.are.equal(1, #plugin.locations)
            local l = plugin.locations[1]
            assert.are.equal("Sunwood", l.name)
            assert.are.equal(3, l.visible_from.chapter_index)

            assert.are.equal(1, #plugin.terms)
            local t = plugin.terms[1]
            assert.are.equal("Sunstone", t.name)
            assert.are.equal(3, t.visible_from.chapter_index)

            assert.are.equal(1, #plugin.timeline)
            assert.are.equal("Chapter 3: The Forest Border", plugin.timeline[1].chapter)
        end)

        it("should append state transitions to existing entities and preserve prior history", function()
            plugin.characters = {
                {
                    name = "Eldrin",
                    role = "High Elf Ranger",
                    status = "alive",
                    description = "Guards the borders of the Sunwood.",
                    visible_from = { chapter_index = 3, page_hint = 45 },
                    states = {
                        { chapter_index = 3, page_hint = 45, role = "High Elf Ranger", description = "Guards the borders." }
                    }
                }
            }

            local delta = {
                character_state_updates = {
                    {
                        name = "Eldrin",
                        role = "Exiled Prince",
                        status = "alive",
                        description = "Revealed as the exiled crown prince of the Sunwood court.",
                        evidence = "Bore the seal of the Sun King."
                    }
                }
            }

            local chapter_info = {
                title = "Chapter 7: Royal Blood",
                page = 130,
                toc_index = 7
            }

            plugin.checkpointHorizonScan = function() end
            plugin:mergeSequentialChapterDelta(delta, chapter_info, 7)

            local c = plugin.characters[1]
            assert.are.equal(2, #c.states)
            assert.are.equal("Exiled Prince", c.role)
            assert.are.equal(7, c.states[2].chapter_index)
            assert.are.equal("Exiled Prince", c.states[2].role)
        end)
    end)

    describe("mention capping (#150 and #133)", function()
        it("should filter out mentions beyond current_page when spoiler_free is enabled", function()
            plugin.ai_helper = { settings = { spoiler_setting = "spoiler_free" } }
            plugin.getCurrentPage = function() return 50 end
            plugin.last_pageno = 50

            local entity = {
                name = "Arthur",
                mentions = {
                    { page = 20, chapter = "Chapter 1", snippet = "Arthur arrived at dawn." },
                    { page = 48, chapter = "Chapter 2", snippet = "Arthur drew his sword." },
                    { page = 85, chapter = "Chapter 4", snippet = "Arthur was struck by an arrow." },
                    { page = 120, chapter = "Chapter 6", snippet = "Arthur was crowned king." },
                }
            }

            local items = plugin:buildMentionsMenuItems(entity)
            -- Should contain Refresh Mentions header + 2 mentions (p. 20, p. 48)
            local mention_count = 0
            for _, it in ipairs(items) do
                if it.text and it.text:find("^p%.%d+") then
                    mention_count = mention_count + 1
                    local pg = tonumber(it.text:match("^p%.(%d+)"))
                    assert.is_true(pg <= 50, "Mention on page " .. tostring(pg) .. " leaked past current_page 50!")
                end
            end
            assert.are.equal(2, mention_count)
        end)
    end)

    describe("EntityListOverlay filtering", function()
        it("should hide future entities and timeline events from prepareItems in spoiler-free mode", function()
            local overlay = EntityListOverlay:new{
                mode = "characters",
                raw_items = {
                    { name = "Known Character", visible_from = { chapter_index = 1, page_hint = 10 } },
                    { name = "Future Character", visible_from = { chapter_index = 5, page_hint = 100 } }
                },
                plugin = plugin
            }

            plugin.getCurrentDocPage = function() return 25 end
            plugin.getCurrentChapterIndex = function() return 2 end
            plugin.ai_helper = { settings = { spoiler_setting = "spoiler_free" } }

            overlay:prepareItems()
            -- Only Known Character should be included
            local visible_items = overlay.items or overlay.display_items or {}
            assert.are.equal(1, #visible_items)
            assert.are.equal("Known Character", visible_items[1].name)
        end)
    end)

    describe("Batch Chapter Delta Prompt & Merging", function()
        it("should build batch prompt with anti-log rules and multi-chapter text blocks", function()
            local ai_helper = require("xray_aihelper")
            local batch = {
                { toc_index = 2, title = "Chapter 2: The Letter", text = "Text of chapter 2" },
                { toc_index = 3, title = "Chapter 3: The Investigation", text = "Text of chapter 3" },
            }
            local manifest = "- Cormoran Strike | Role: Detective | Status: alive"
            local prompt = ai_helper:buildBatchChapterDeltaPrompt("Career of Evil", "Robert Galbraith", batch, manifest)

            assert.is_not_nil(prompt)
            assert.is_true(prompt:find("Book: Career of Evil") ~= nil)
            assert.is_true(prompt:find("Author: Robert Galbraith") ~= nil)
            assert.is_true(prompt:find("%[2%] Chapter 2: The Letter") ~= nil)
            assert.is_true(prompt:find("%[3%] Chapter 3: The Investigation") ~= nil)
            assert.is_true(prompt:find("CHARACTER DESCRIPTION DEPTH & SUBSTANCE") ~= nil)
            assert.is_true(prompt:find("NO Trivial Errand Recaps: Do NOT write chronological logs") ~= nil)
            assert.is_true(prompt:find("=== CHAPTER 2: Chapter 2: The Letter ===") ~= nil)
            assert.is_true(prompt:find("=== CHAPTER 3: Chapter 3: The Investigation ===") ~= nil)
        end)

        it("should merge multi-chapter deltas correctly across chapters", function()
            local batch_response = {
                chapters = {
                    {
                        chapter_index = 2,
                        chapter_title = "Chapter 2",
                        timeline_event = "Event in chapter 2",
                        new_characters = {
                            { name = "Shanker", role = "Informant", status = "alive", description = "Strike's streetwise informant." }
                        }
                    },
                    {
                        chapter_index = 3,
                        chapter_title = "Chapter 3",
                        timeline_event = "Event in chapter 3",
                        character_state_updates = {
                            { name = "Shanker", role = "Crucial Ally", status = "alive", description = "Street informant who helps Strike secure vital leads." }
                        }
                    }
                }
            }

            local ch2 = { toc_index = 2, title = "Chapter 2", page = 40 }
            local ch3 = { toc_index = 3, title = "Chapter 3", page = 70 }

            plugin:mergeSequentialChapterDelta(batch_response.chapters[1], ch2, 2)
            plugin:mergeSequentialChapterDelta(batch_response.chapters[2], ch3, 3)

            local shanker = nil
            for _, c in ipairs(plugin.characters) do
                if c.name == "Shanker" then shanker = c break end
            end
            assert.is_not_nil(shanker)
            assert.are.equal(2, #shanker.states)
            assert.are.equal("Informant", shanker.states[1].role)
            assert.are.equal(2, shanker.states[1].chapter_index)
            assert.are.equal("Crucial Ally", shanker.states[2].role)
            assert.are.equal(3, shanker.states[2].chapter_index)

            -- Batch responses carry timeline_event as a plain string (#157)
            assert.are.equal(2, #plugin.timeline)
            assert.are.equal("Chapter 2", plugin.timeline[1].chapter)
            assert.are.equal("Event in chapter 2", plugin.timeline[1].event)
            assert.are.equal(2, plugin.timeline[1].chapter_index)
            assert.are.equal(40, plugin.timeline[1].page)
            assert.are.equal("Chapter 3", plugin.timeline[2].chapter)
            assert.are.equal("Event in chapter 3", plugin.timeline[2].event)
        end)

        it("should not duplicate a string timeline_event when a chapter is merged twice", function()
            local ch = { toc_index = 4, title = "Chapter 4", page = 90 }
            plugin:mergeSequentialChapterDelta({ timeline_event = "Event in chapter 4" }, ch, 4, true)
            plugin:mergeSequentialChapterDelta({ timeline_event = "Event in chapter 4" }, ch, 4, true)

            assert.are.equal(1, #plugin.timeline)
            assert.are.equal("Event in chapter 4", plugin.timeline[1].event)
        end)

        it("should ignore empty or malformed timeline_event values", function()
            plugin:mergeSequentialChapterDelta({ timeline_event = "" }, { toc_index = 5, title = "Chapter 5", page = 100 }, 5, true)
            plugin:mergeSequentialChapterDelta({ timeline_event = 42 }, { toc_index = 6, title = "Chapter 6", page = 110 }, 6, true)
            plugin:mergeSequentialChapterDelta({ timeline_event = { chapter = "Chapter 7" } }, { toc_index = 7, title = "Chapter 7", page = 120 }, 7, true)
            plugin:mergeSequentialChapterDelta({ timeline_event = { event = "" } }, { toc_index = 8, title = "Chapter 8", page = 130 }, 8, true)
            plugin:mergeSequentialChapterDelta({ timeline_event = { event = 5 } }, { toc_index = 9, title = "Chapter 9", page = 140 }, 9, true)

            assert.are.equal(0, #plugin.timeline)
        end)

        it("should title a string timeline_event with the chapter title and keep an object event's own chapter", function()
            plugin:mergeSequentialChapterDelta({ timeline_event = "String event" }, { toc_index = 10, title = "The Return", page = 150 }, 10, true)
            plugin:mergeSequentialChapterDelta({ timeline_event = { chapter = "Interlude", event = "Object event" } }, { toc_index = 11, title = "Chapter 11", page = 160 }, 11, true)

            assert.are.equal(2, #plugin.timeline)
            assert.are.equal("The Return", plugin.timeline[1].chapter)
            assert.are.equal("String event", plugin.timeline[1].event)
            assert.are.equal("Interlude", plugin.timeline[2].chapter)
            assert.are.equal("Object event", plugin.timeline[2].event)
        end)
    end)

    describe("Unlocked State Counting & Past Evolution Modal", function()
        local evolving_char = {
            name = "Robin Ellacott",
            states = {
                { chapter_index = 1, page_hint = 15, role = "Temp", description = "Temporary secretary." },
                { chapter_index = 4, page_hint = 90, role = "Partner", description = "Full investigative partner." },
                { chapter_index = 8, page_hint = 210, role = "Lead", description = "Leading investigation." }
            }
        }

        it("should accurately count unlocked states based on reader position in spoiler-free mode", function()
            plugin.ai_helper = { settings = { spoiler_setting = "spoiler_free" } }
            plugin.getCurrentChapterIndex = function() return 1 end
            plugin.getCurrentDocPage = function() return 20 end

            local c1 = plugin:getUnlockedStateCount(evolving_char, 1, 20, false)
            assert.are.equal(1, c1)

            -- In chapter 4 before page 90: still 1
            local c2 = plugin:getUnlockedStateCount(evolving_char, 4, 80, false)
            assert.are.equal(1, c2)

            -- In chapter 4 at page 95: 2
            local c3 = plugin:getUnlockedStateCount(evolving_char, 4, 95, false)
            assert.are.equal(2, c3)

            -- In chapter 10: all 3
            local c4 = plugin:getUnlockedStateCount(evolving_char, 10, 300, false)
            assert.are.equal(3, c4)
        end)

        it("should unlock all states in full_book mode", function()
            local c_full = plugin:getUnlockedStateCount(evolving_char, 1, 10, true)
            assert.are.equal(3, c_full)
        end)

        it("should open EntityListOverlay in evolution mode in showPastEvolution", function()
            plugin.getCurrentChapterIndex = function() return 5 end
            plugin.getCurrentDocPage = function() return 100 end
            plugin.ai_helper = { settings = { spoiler_setting = "spoiler_free" } }

            plugin:showPastEvolution(evolving_char)

            assert.is_not_nil(plugin.active_evolution_menu)
            assert.are.equal("evolution", plugin.active_evolution_menu.mode)
            assert.is_not_nil(plugin.active_evolution_menu.items)
            assert.is_true(#plugin.active_evolution_menu.items >= 2)
            assert.are.equal(evolving_char, plugin.active_evolution_menu.entity)
        end)

        it("should accurately report hasEntityEvolution for states and history", function()
            assert.is_true(plugin:hasEntityEvolution(evolving_char))
            assert.is_false(plugin:hasEntityEvolution({ name = "Static", states = { { chapter_index = 1 } } }))
            assert.is_true(plugin:hasEntityEvolution({
                name = "HistChar",
                history = {
                    { page = 10, role = "Crew", description = "Astronaut on Mars." },
                    { page = 50, role = "Survivor", description = "Rescued and safe back on Earth." }
                }
            }))
            assert.is_false(plugin:hasEntityEvolution({
                name = "RewordedOnly",
                history = {
                    { page = 10, description = "Astronaut left behind on Mars." },
                    { page = 50, description = "Astronaut left behind on Mars alone." }
                }
            }))
            assert.is_false(plugin:hasEntityEvolution({ name = "SingleHist", history = { { page = 10 } } }))
            assert.is_false(plugin:hasEntityEvolution({ name = "NoEvo" }))
            assert.is_false(plugin:hasEntityEvolution(nil))
        end)

        it("should reveal all future milestones when show_all is true or full_book in showPastEvolution", function()
            plugin.getCurrentChapterIndex = function() return 2 end
            plugin.getCurrentDocPage = function() return 30 end
            plugin.ai_helper = { settings = { spoiler_setting = "spoiler_free" } }

            plugin:showPastEvolution(evolving_char, { show_all = true })

            assert.is_not_nil(plugin.active_evolution_menu)
            assert.is_true(plugin.active_evolution_menu.reveal_future == true)
            for _, item in ipairs(plugin.active_evolution_menu.items) do
                assert.is_false(item.is_locked == true)
            end
        end)

        it("should handle entities with history and corrupted table fields without crashing", function()
            plugin.getCurrentChapterIndex = function() return 3 end
            plugin.getCurrentDocPage = function() return 50 end
            plugin.ai_helper = { settings = { spoiler_setting = "spoiler_free" } }

            local weird_char = {
                name = "Corrupted State Entity",
                history = {
                    { page = 10, role = { "Array", "Role" }, status = "active", description = "First history" },
                    { page = 60, role = "Advanced", status = { "alive" }, evidence = { "Quote 1", "Quote 2" }, description = "Second history with much more detail about the case" }
                }
            }

            -- Should not crash with table roles/evidence
            local ok, err = pcall(function()
                plugin:showPastEvolution(weird_char)
            end)
            assert.is_true(ok)
            assert.is_not_nil(plugin.active_evolution_menu)
        end)
    end)

    describe("EntityListOverlay count consistency", function()
        it("should display visible count rather than raw items count in header in spoiler-free mode", function()
            plugin.loc = { t = function(self, k) if k == "menu_characters" then return "Characters" end return k end }
            plugin.ai_helper = { settings = { spoiler_setting = "spoiler_free" } }
            plugin.getCurrentDocPage = function() return 15 end
            plugin.getCurrentChapterIndex = function() return 1 end

            local raw_chars = {
                { name = "The Killer", description = "Unknown suspect.", visible_from = { chapter_index = 1, page_hint = 5 } },
                { name = "Sarah Shadlock", description = "Old friend.", visible_from = { chapter_index = 1, page_hint = 10 } },
                { name = "Tom", description = "Strike's nephew.", visible_from = { chapter_index = 1, page_hint = 12 } },
                { name = "Future Suspect", description = "Introduced much later.", visible_from = { chapter_index = 4, page_hint = 80 } },
                { name = "Witness 2", description = "Appears in chapter 5.", visible_from = { chapter_index = 5, page_hint = 110 } },
            }

            local overlay = EntityListOverlay:new{
                plugin = plugin,
                mode = "characters",
                raw_items = raw_chars,
            }

            assert.are.equal(5, #overlay.raw_items)
            assert.are.equal(3, overlay.unfiltered_visible_count)
            assert.are.equal(3, #overlay.items)
            assert.are.equal("Characters (3)", overlay.title)
        end)

        it("should display all items in header in full_book mode", function()
            plugin.loc = { t = function(self, k) if k == "menu_characters" then return "Characters" end return k end }
            plugin.ai_helper = { settings = { spoiler_setting = "full_book" } }
            plugin.getCurrentDocPage = function() return 15 end
            plugin.getCurrentChapterIndex = function() return 1 end

            local raw_chars = {
                { name = "The Killer", description = "Unknown suspect.", visible_from = { chapter_index = 1, page_hint = 5 } },
                { name = "Sarah Shadlock", description = "Old friend.", visible_from = { chapter_index = 1, page_hint = 10 } },
                { name = "Tom", description = "Strike's nephew.", visible_from = { chapter_index = 1, page_hint = 12 } },
                { name = "Future Suspect", description = "Introduced much later.", visible_from = { chapter_index = 4, page_hint = 80 } },
            }

            local overlay = EntityListOverlay:new{
                plugin = plugin,
                mode = "characters",
                raw_items = raw_chars,
            }

            assert.are.equal(4, #overlay.raw_items)
            assert.are.equal(4, overlay.unfiltered_visible_count)
            assert.are.equal(4, #overlay.items)
            assert.are.equal("Characters (4)", overlay.title)
        end)
    end)

    describe("Character Ordering and Series Promotion", function()
        it("should rank protagonists ahead of minor characters in frequency/importance mode before mentions scan", function()
            plugin.ai_helper = { settings = { spoiler_setting = "full_book" } }
            local raw_chars = {
                { name = "Tom", role = "Minor Character", visible_from = { chapter_index = 1, page_hint = 5 } },
                { name = "Sarah Shadlock", role = "Supporting Character", visible_from = { chapter_index = 1, page_hint = 8 } },
                { name = "Cormoran Strike", role = "Protagonist", visible_from = { chapter_index = 1, page_hint = 10 } },
                { name = "Robin Ellacott", role = "Partner", visible_from = { chapter_index = 1, page_hint = 15 } },
            }

            local overlay = EntityListOverlay:new{
                plugin = plugin,
                mode = "characters",
                raw_items = raw_chars,
                sort_mode = "frequency",
            }

            assert.are.equal("Cormoran Strike", overlay.items[1].name)
            assert.are.equal("Robin Ellacott", overlay.items[2].name)
            assert.are.equal("Sarah Shadlock", overlay.items[3].name)
            assert.are.equal("Tom", overlay.items[4].name)
        end)

        it("should order characters chronologically in appearance mode with role tiebreaking", function()
            plugin.ai_helper = { settings = { spoiler_setting = "full_book" } }
            local raw_chars = {
                { name = "Witness B", role = "Minor Character", visible_from = { chapter_index = 2, page_hint = 30 } },
                { name = "Clerk", role = "Minor Character", visible_from = { chapter_index = 1, page_hint = 10 } },
                { name = "Detective Strike", role = "Protagonist", visible_from = { chapter_index = 1, page_hint = 10 } },
                { name = "Future Killer", role = "Antagonist", visible_from = { chapter_index = 3, page_hint = 50 } },
            }

            local overlay = EntityListOverlay:new{
                plugin = plugin,
                mode = "characters",
                raw_items = raw_chars,
                sort_mode = "appearance",
            }

            -- Chapter 1 entities before Chapter 2, Protagonist before Minor within Chapter 1
            assert.are.equal("Detective Strike", overlay.items[1].name)
            assert.are.equal("Clerk", overlay.items[2].name)
            assert.are.equal("Witness B", overlay.items[3].name)
            assert.are.equal("Future Killer", overlay.items[4].name)
        end)

        it("should promote series_prior entities in mergeSequentialChapterDelta and preserve prior descriptions", function()
            plugin.characters = {
                {
                    id = "char_strike",
                    name = "Cormoran Strike",
                    source = "series_prior",
                    is_series = true,
                    from_series = true,
                    source_book = 1,
                    sort_order = 11000,
                    description = "[From Book 1] Afghanistan war veteran and private detective.",
                }
            }

            local delta_data = {
                new_characters = {
                    {
                        name = "Cormoran Strike",
                        role = "Protagonist",
                        description = "Investigating the death of Lula Landry.",
                        evidence = "Hired by John Bristow in Chapter 1.",
                    }
                }
            }

            plugin:mergeSequentialChapterDelta(delta_data, { title = "Chapter 1", page = 10 }, 1)

            local strike = plugin.characters[1]
            assert.is_nil(strike.source) -- Promoted from series_prior to active cast
            assert.is_nil(strike.sort_order) -- Penalty cleared
            assert.is_true(strike.is_series)
            assert.are.equal(1, strike.visible_from.chapter_index)
            assert.are.equal(10, strike.visible_from.page_hint)

            -- Description should have current book first, followed by [From Book 1]
            local expected_desc = "Investigating the death of Lula Landry.\n\n[From Book 1] Afghanistan war veteran and private detective."
            assert.are.equal(expected_desc, strike.description)

            -- resolveEntityState should also format with current book first
            local role, status, desc = plugin:resolveEntityState(strike, 1, 10)
            assert.are.equal("Protagonist", role)
            assert.are.equal(expected_desc, desc)
        end)

        it("should rank co-leads like Robin Ellacott at the top with Cormoran Strike above minor investigators and romantic partners", function()
            plugin.ai_helper = { settings = { spoiler_setting = "full_book" } }
            local raw_chars = {
                {
                    name = "Emma Daniels",
                    role = "Military Investigator",
                    history = {},
                    states = { { chapter_index = 18, page_hint = 137, role = "Military Investigator" } }
                },
                {
                    name = "Elin",
                    role = "Romantic Partner",
                    history = { { chapter = "Ch. 15", page = 158 }, { chapter = "Ch. 19", page = 199 } }
                },
                {
                    name = "Hazel Furley",
                    role = "Donald Laing's Partner",
                    history = { { chapter = "Ch. 39", page = 479 } }
                },
                {
                    name = "Donald Laing",
                    role = "Imprisoned Antagonist",
                    history = { { chapter = "Ch. 7", page = 63 }, { chapter = "Ch. 11", page = 106 } }
                },
                {
                    name = "Robin Ellacott",
                    role = "Former Investigative Assistant",
                    history = { { chapter = "Chapter 3", page = 28 }, { chapter = "Chapter 7", page = 63 }, { chapter = "Chapter 11", page = 106 } },
                    states = { { chapter_index = 22, page_hint = 183, role = "Investigative Assistant" } }
                },
                {
                    name = "Cormoran Strike",
                    role = "Private Investigator",
                    history = { { chapter = "Chapter 3", page = 28 }, { chapter = "Chapter 7", page = 63 }, { chapter = "Chapter 11", page = 106 } }
                },
            }

            local overlay = EntityListOverlay:new{
                plugin = plugin,
                mode = "characters",
                raw_items = raw_chars,
                sort_mode = "frequency",
            }

            -- Cormoran Strike and Robin Ellacott must be the top 2
            assert.are.equal("Cormoran Strike", overlay.items[1].name)
            assert.are.equal("Robin Ellacott", overlay.items[2].name)
            -- Donald Laing (antagonist) should be #3, well ahead of Emma Daniels, Elin, and Hazel Furley
            assert.are.equal("Donald Laing", overlay.items[3].name)
        end)

        it("should correctly identify earliest appearance from history when states begin in later chapters", function()
            plugin.ai_helper = { settings = { spoiler_setting = "full_book" } }
            local raw_chars = {
                {
                    name = "Emma Daniels",
                    role = "Military Investigator",
                    states = { { chapter_index = 18, page_hint = 137 } }
                },
                {
                    name = "Robin Ellacott",
                    role = "Former Investigative Assistant",
                    -- Robin's first state delta occurred in Ch 22, but she was introduced in Ch 3
                    history = { { chapter = "Chapter 3", page = 28 } },
                    states = { { chapter_index = 22, page_hint = 183 } }
                },
                {
                    name = "Cormoran Strike",
                    role = "Private Investigator",
                    history = { { chapter = "Chapter 3", page = 28 } }
                },
            }

            local overlay = EntityListOverlay:new{
                plugin = plugin,
                mode = "characters",
                raw_items = raw_chars,
                sort_mode = "appearance",
            }

            -- Chapter 3 characters (Strike and Robin) must appear before Chapter 18 (Emma Daniels)
            assert.are.equal("Cormoran Strike", overlay.items[1].name)
            assert.are.equal("Robin Ellacott", overlay.items[2].name)
            assert.are.equal("Emma Daniels", overlay.items[3].name)
        end)
    end)
end)
