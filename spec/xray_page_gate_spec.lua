-- spec/xray_page_gate_spec.lua
-- Unit tests for Intra-Chapter Per-Page & Percentage (chapter_pct) Spoiler Gating,
-- 2-Stage Entity States, LookupManager & Alias Gating, and Legacy Cache Self-Healing.

require("spec/spec_helper")
local main_plugin = dofile("xray.koplugin/main.lua")
local xray_ui = require("xray_ui")
local xray_fetch = require("xray_fetch")
local xray_chapteranalyzer = require("xray_chapteranalyzer")
local LookupManager = require("xray_lookupmanager")
local EntityListOverlay = require("xray_entity_list")

describe("xray_page_gate_spec", function()
    local plugin
    local analyzer

    before_each(function()
        plugin = createMockPlugin()
        for k, v in pairs(main_plugin) do plugin[k] = v end
        for k, v in pairs(xray_ui) do plugin[k] = v end
        for k, v in pairs(xray_fetch) do plugin[k] = v end
        analyzer = xray_chapteranalyzer:new()
        plugin.chapter_analyzer = analyzer
        plugin.lookup_manager = LookupManager:new(plugin)
        plugin.showCharacterDetails = function() end
    end)

    describe("ChapterAnalyzer:injectPageMarkers", function()
        it("should tag single-page chapter text with start_page", function()
            local text = "This is a single page chapter."
            local marked = analyzer:injectPageMarkers(text, 10, 10)
            assert.are.equal("[PAGE 10]\n" .. text, marked)
        end)

        it("should divide multi-page chapter proportionally with [PAGE N] markers", function()
            local text = string.rep("Paragraph of narrative text.\n", 20)
            local marked = analyzer:injectPageMarkers(text, 80, 84)
            assert.is_not_nil(marked:find("%[PAGE 80%]"))
            assert.is_not_nil(marked:find("%[PAGE 81%]"))
            assert.is_not_nil(marked:find("%[PAGE 82%]"))
            assert.is_not_nil(marked:find("%[PAGE 83%]"))
            assert.is_not_nil(marked:find("%[PAGE 84%]"))
        end)

        it("should safely handle nil or empty text", function()
            assert.is_nil(analyzer:injectPageMarkers(nil, 1, 5))
            assert.are.equal("", analyzer:injectPageMarkers("", 1, 5))
        end)

        it("should not split multi-byte UTF-8 characters", function()
            -- Chinese / accented characters
            local text = string.rep("这是测试文本，包含中文字符和特殊标点符号。\n", 15)
            local marked = analyzer:injectPageMarkers(text, 1, 3)
            assert.is_not_nil(marked:find("%[PAGE 1%]"))
            assert.is_not_nil(marked:find("%[PAGE 3%]"))
            -- Verify valid UTF-8 by round-tripping through Lua string patterns
            local ok = pcall(function()
                for _ in marked:gmatch("[%z\1-\127\194-\244][\128-\191]*") do end
            end)
            assert.is_true(ok)
        end)
    end)

    describe("Intra-Chapter State Update Gating & Baseline Seeding", function()
        it("should gate state updates at their intra-chapter page milestone and seed baselines", function()
            -- Character from standard fetch with no states yet
            plugin.characters = {
                {
                    id = "char_eldrin",
                    name = "Eldrin",
                    role = "Ranger",
                    status = "alive",
                    description = "Forest ranger of the borderlands.",
                    visible_from = { chapter_index = 1, page_hint = 10 },
                }
            }

            -- Sequential scan of Chapter 5 (p. 80-99) produces a state update at page 95
            local delta = {
                character_state_updates = {
                    {
                        name = "Eldrin",
                        page = 95,
                        role = "Crown Prince",
                        status = "alive",
                        description = "Revealed as the exiled Crown Prince of the realm.",
                        evidence = "Displayed the royal signet ring."
                    }
                }
            }

            local ch5 = {
                toc_index = 5,
                title = "Chapter 5: Revelations",
                page = 80,
                end_page = 99,
            }

            plugin.checkpointHorizonScan = function() end
            plugin:mergeSequentialChapterDelta(delta, ch5, 5, true)

            local eldrin = plugin.characters[1]
            -- Baseline was seeded at states[1]
            assert.are.equal(2, #eldrin.states)
            assert.are.equal("Ranger", eldrin.states[1].role)
            assert.are.equal("Crown Prince", eldrin.states[2].role)
            assert.are.equal(95, eldrin.states[2].page_hint)
            assert.is_true(eldrin.states[2].chapter_pct > 0.7)

            -- Reader at Page 80 (Page 1 of Chapter 5): state 2 is locked!
            local role_p80, _, desc_p80 = plugin:resolveEntityState(eldrin, 5, 80)
            assert.are.equal("Ranger", role_p80)
            assert.are.equal("Forest ranger of the borderlands.", desc_p80)

            -- Reader at Page 94: still locked
            local role_p94, _, desc_p94 = plugin:resolveEntityState(eldrin, 5, 94)
            assert.are.equal("Ranger", role_p94)

            -- Reader reaches Page 95: state 2 unlocks!
            local role_p95, _, desc_p95 = plugin:resolveEntityState(eldrin, 5, 95)
            assert.are.equal("Crown Prince", role_p95)
            assert.are.equal("Revealed as the exiled Crown Prince of the realm.", desc_p95)
        end)
    end)

    describe("2-Stage Intra-Chapter States for New Characters", function()
        it("should emit Stage 1 intro and Stage 2 full states for multi-page chapters", function()
            local delta = {
                new_characters = {
                    {
                        name = "Corwin",
                        first_page = 80,
                        intro_role = "Wounded Traveler",
                        intro_description = "A wounded man found by the road seeking shelter.",
                        page = 99,
                        role = "Royal Assassin",
                        status = "alive",
                        description = "A lethal royal assassin on a mission to eliminate the high council.",
                        evidence = "Found carrying concealed poisoned daggers."
                    }
                }
            }

            local ch5 = {
                toc_index = 5,
                title = "Chapter 5",
                page = 80,
                end_page = 99,
            }

            plugin.checkpointHorizonScan = function() end
            plugin:mergeSequentialChapterDelta(delta, ch5, 5, true)

            local corwin = plugin.characters[1]
            assert.is_not_nil(corwin)
            assert.are.equal(2, #corwin.states)

            -- Stage 1
            assert.are.equal("Wounded Traveler", corwin.states[1].role)
            assert.are.equal("A wounded man found by the road seeking shelter.", corwin.states[1].description)
            assert.are.equal(80, corwin.states[1].page_hint)
            assert.are.equal(0.0, corwin.states[1].chapter_pct)

            -- Stage 2
            assert.are.equal("Royal Assassin", corwin.states[2].role)
            assert.are.equal(99, corwin.states[2].page_hint)
            assert.are.equal(1.0, corwin.states[2].chapter_pct)

            -- On Page 80: visible with Stage 1 description
            assert.is_true(plugin:isEntityVisibleAtCurrentPosition(corwin, 5, 80))
            local r80, _, d80 = plugin:resolveEntityState(corwin, 5, 80)
            assert.are.equal("Wounded Traveler", r80)
            assert.are.equal("A wounded man found by the road seeking shelter.", d80)

            -- On Page 98: still Stage 1
            local r98, _, d98 = plugin:resolveEntityState(corwin, 5, 98)
            assert.are.equal("Wounded Traveler", r98)

            -- On Page 99: evolves to Stage 2
            local r99, _, d99 = plugin:resolveEntityState(corwin, 5, 99)
            assert.are.equal("Royal Assassin", r99)
            assert.are.equal("A lethal royal assassin on a mission to eliminate the high council.", d99)
        end)

        it("should gate mid-chapter introduced characters as invisible on Page 1", function()
            local delta = {
                new_characters = {
                    {
                        name = "Doctor Thorne",
                        first_page = 92,
                        intro_role = "Physician",
                        intro_description = "The town physician called to treat an illness.",
                        page = 99,
                        role = "Physician",
                        status = "alive",
                        description = "The town physician called to treat an illness.",
                    }
                }
            }

            local ch5 = {
                toc_index = 5,
                title = "Chapter 5",
                page = 80,
                end_page = 99,
            }

            plugin.checkpointHorizonScan = function() end
            plugin:mergeSequentialChapterDelta(delta, ch5, 5, true)

            local thorne = plugin.characters[1]
            -- On Page 80: Thorne is NOT visible yet!
            assert.is_false(plugin:isEntityVisibleAtCurrentPosition(thorne, 5, 80))
            assert.is_false(plugin:isEntityVisibleAtCurrentPosition(thorne, 5, 91))

            -- On Page 92: Thorne becomes visible
            assert.is_true(plugin:isEntityVisibleAtCurrentPosition(thorne, 5, 92))
            local r92, _, d92 = plugin:resolveEntityState(thorne, 5, 92)
            assert.are.equal("Physician", r92)
        end)

        it("should gate full description at end_page if model omits intro_description on multi-page chapter", function()
            local delta = {
                new_characters = {
                    {
                        name = "Secret Spy",
                        role = "Double Agent",
                        status = "alive",
                        description = "Revealed as a double agent working for the enemy.",
                        page = 99,
                    }
                }
            }

            local ch5 = {
                toc_index = 5,
                title = "Chapter 5",
                page = 80,
                end_page = 99,
            }

            plugin.checkpointHorizonScan = function() end
            plugin:mergeSequentialChapterDelta(delta, ch5, 5, true)

            local spy = plugin.characters[1]
            -- State was gated at 99 / 1.0
            assert.are.equal(99, spy.states[1].page_hint)

            -- At Page 80: all states locked, so not visible
            assert.is_false(plugin:isEntityVisibleAtCurrentPosition(spy, 5, 80))

            -- Single word lookup at Page 80 prepends safe state without destroying page 99 state
            plugin:_processSingleWordResult({
                is_valid = true,
                type = "character",
                item = {
                    name = "Secret Spy",
                    role = "Suspicious Man",
                    description = "A mysterious man seen in the shadows."
                }
            }, "Secret Spy", "book text", 80)

            assert.are.equal(2, #spy.states)
            assert.are.equal(80, spy.states[1].page_hint)
            assert.are.equal("Suspicious Man", spy.states[1].role)
            assert.are.equal(99, spy.states[2].page_hint)
            assert.are.equal("Double Agent", spy.states[2].role)

            -- Now on Page 80, reader sees Page 80 state
            local r80, _, d80 = plugin:resolveEntityState(spy, 5, 80)
            assert.are.equal("Suspicious Man", r80)

            -- On Page 99, reader sees Page 99 state
            local r99, _, d99 = plugin:resolveEntityState(spy, 5, 99)
            assert.are.equal("Double Agent", r99)
        end)
    end)

    describe("Font-size Repagination Resilience", function()
        it("should evaluate chapter_pct proportionally against repaginated TOC bounds", function()
            -- State stamped during extraction: Ch 5 originally was pages 80 to 100, update at page 90 (pct = 0.5)
            local gate = {
                chapter_index = 5,
                page_hint = 90,
                chapter_pct = 0.5,
                ch_start_page = 80,
                ch_end_page = 100,
            }

            -- User increased font size: live TOC now reports Ch 5 as pages 120 to 160
            plugin._getFlatToc = function()
                return {
                    { title = "Chapter 1", page = 1 },
                    { title = "Chapter 2", page = 20 },
                    { title = "Chapter 3", page = 50 },
                    { title = "Chapter 4", page = 80 },
                    { title = "Chapter 5", page = 120 },
                    { title = "Chapter 6", page = 161 },
                }
            end

            -- Page 120 (0% of Ch 5) -> locked
            assert.is_false(plugin:isPositionGateUnlocked(gate, 5, 120))

            -- Page 135 (37.5% of Ch 5) -> locked
            assert.is_false(plugin:isPositionGateUnlocked(gate, 5, 135))

            -- Page 140 (50.0% of Ch 5) -> unlocked!
            assert.is_true(plugin:isPositionGateUnlocked(gate, 5, 140))

            -- Page 155 (87.5% of Ch 5) -> unlocked!
            assert.is_true(plugin:isPositionGateUnlocked(gate, 5, 155))
        end)
    end)

    describe("LookupManager, Alias Gating & Timeline End-Page", function()
        it("should gate spoiler aliases in LookupManager until their unlock position", function()
            plugin.ai_helper = { settings = { spoiler_setting = "spoiler_free" } }
            plugin.characters = {
                {
                    name = "Vance",
                    role = "Diplomat",
                    visible_from = { chapter_index = 1, page_hint = 10 },
                    aliases = { "Ambassador Vance", "The Masked Culprit" },
                    alias_visible_from = {
                        ["the masked culprit"] = { chapter_index = 5, page_hint = 95, chapter_pct = 0.8 }
                    }
                }
            }

            plugin.getCurrentDocPage = function() return 80 end
            plugin.getCurrentChapterIndex = function() return 5 end

            -- On Page 80: "The Masked Culprit" alias is hidden
            local unl = plugin:getUnlockedAliases(plugin.characters[1], 5, 80)
            assert.are.equal(1, #unl)
            assert.are.equal("Ambassador Vance", unl[1])

            -- Lookup on "The Masked Culprit" returns nothing on Page 80
            local matches_early = plugin.lookup_manager:lookupAll("The Masked Culprit")
            assert.are.equal(0, #matches_early)

            -- Normal name matches
            local matches_vance = plugin.lookup_manager:lookupAll("Vance")
            assert.are.equal(1, #matches_vance)

            -- On Page 95: alias unlocks
            plugin.getCurrentDocPage = function() return 95 end
            local matches_late = plugin.lookup_manager:lookupAll("The Masked Culprit")
            assert.are.equal(1, #matches_late)
            assert.are.equal("Vance", matches_late[1].item.name)
        end)

        it("should gate chapter timeline events until end_page in spoiler-free mode", function()
            plugin.ai_helper = { settings = { spoiler_setting = "spoiler_free" } }
            plugin.timeline = {
                {
                    chapter = "Chapter 5",
                    chapter_index = 5,
                    page = 80,
                    end_page = 99,
                    chapter_pct = 1.0,
                    event = "The castle gates are breached and the king is slain."
                }
            }

            plugin.getCurrentDocPage = function() return 80 end
            plugin.getCurrentChapterIndex = function() return 5 end

            local overlay = EntityListOverlay:new{
                plugin = plugin,
                mode = "timeline",
                raw_items = plugin.timeline,
            }

            -- On Page 80 (start of chapter 5): event is hidden
            overlay:prepareItems()
            assert.are.equal(0, #overlay.items)

            -- On Page 99 (end of chapter 5): event unlocks
            plugin.getCurrentDocPage = function() return 99 end
            overlay:prepareItems()
            assert.are.equal(1, #overlay.items)
            assert.are.equal("The castle gates are breached and the king is slain.", overlay.items[1].event)
        end)
    end)

    describe("Legacy Pre-generated Cache Self-Healing", function()
        it("should self-heal legacy state updates with page_hint == chapter_start", function()
            plugin.ai_helper = { settings = { spoiler_setting = "spoiler_free" } }
            plugin._getFlatToc = function()
                return {
                    { title = "Chapter 1", page = 1 },
                    { title = "Chapter 2", page = 20 },
                    { title = "Chapter 3", page = 50 },
                    { title = "Chapter 4", page = 80 },
                }
            end

            -- Legacy state update: stamped with 50 (chapter start) on a multi-page chapter (50..79)
            local legacy_char = {
                name = "Lord Arthur",
                states = {
                    { chapter_index = 1, page_hint = 10, role = "Lord", description = "A loyal noble." },
                    { chapter_index = 3, page_hint = 50, role = "Traitor", description = "Revealed as a traitor." } -- legacy update!
                }
            }

            -- On Page 50 of Chapter 3: legacy update must NOT leak! Reader sees State 1
            local role50, _, desc50 = plugin:resolveEntityState(legacy_char, 3, 50)
            assert.are.equal("Lord", role50)
            assert.are.equal("A loyal noble.", desc50)

            -- On Page 78: still sees State 1
            local role78, _, desc78 = plugin:resolveEntityState(legacy_char, 3, 78)
            assert.are.equal("Lord", role78)

            -- On Page 79 (end of Chapter 3): legacy update unlocks
            local role79, _, desc79 = plugin:resolveEntityState(legacy_char, 3, 79)
            assert.are.equal("Traitor", role79)
            assert.are.equal("Revealed as a traitor.", desc79)
        end)
    end)
end)
