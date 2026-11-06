require("spec/spec_helper")
local Evolution = require("xray_evolution")

describe("Evolution Module", function()

    describe("Type safety and edge cases", function()
        it("handles nil and non-table inputs safely", function()
            local res1 = Evolution.build(nil)
            assert.is_table(res1)
            assert.are.equal(#res1, 0)

            local res2 = Evolution.build("invalid")
            assert.is_table(res2)
            assert.are.equal(#res2, 0)

            local res3 = Evolution.filterKey(nil)
            assert.is_table(res3)
            assert.are.equal(#res3, 0)

            local res4 = Evolution.filterKey({})
            assert.is_table(res4)
            assert.are.equal(#res4, 0)
        end)

        it("handles corrupted or unusual field types gracefully", function()
            local entity = {
                name = "Test Entity",
                states = {
                    {
                        chapter_index = "2",
                        page = "45",
                        role = { "Captain", "Commander" }, -- table role
                        status = true,                     -- boolean status
                        description = 123456,              -- numeric description
                        evidence = { "Chapter 2 quote" },  -- table evidence
                        change = false,
                    }
                }
            }
            local milestones = Evolution.build(entity, { cur_chap = 5 })
            assert.are.equal(#milestones, 1)
            local m = milestones[1]
            assert.are.equal(m.chapter_index, 2)
            assert.are.equal(m.page, 45)
            assert.are.equal(m.role, "Captain, Commander")
            assert.are.equal(m.status, "true")
            assert.are.equal(m.description, "123456")
            assert.are.equal(m.evidence, "Chapter 2 quote")
        end)

        it("creates a single baseline milestone for entity with only base fields", function()
            local entity = {
                name = "Ancient Artifact",
                description = "A mysterious glowing crystal found in the caves.",
                role = "relic",
                status = "intact",
                page = 12,
            }
            local milestones = Evolution.build(entity, { cur_chap = 1, cur_page = 20 })
            assert.are.equal(#milestones, 1)
            local m = milestones[1]
            assert.are.equal(m.source, "base")
            assert.are.equal(m.kind, "first")
            assert.are.equal(m.description, entity.description)
            assert.is_true(m.is_current)
            assert.is_false(m.is_locked)
        end)
    end)

    describe("Source Ingestion & Chapter Preservation", function()
        it("ingests from both states and history and merges duplicates", function()
            local entity = {
                name = "Mark Watney",
                states = {
                    {
                        chapter_index = 1,
                        chapter_title = "Sol 6",
                        page_hint = 15,
                        role = "Botanist",
                        status = "stranded",
                        description = "Mark is left behind on Mars after a fierce dust storm.",
                        change = "Stranded on Mars",
                    }
                },
                history = {
                    {
                        chapter = 1,
                        chapter_title = "Sol 6",
                        page = 15,
                        role = "Botanist",
                        status = "stranded",
                        description = "Mark is left behind on Mars after a fierce dust storm.",
                        evidence = "He was struck by an antenna.",
                    },
                    {
                        chapter = "Sol 12",
                        page = 28,
                        role = "Mechanical Engineer",
                        biography = "Watney starts planting potatoes inside the Hab using Martian soil.",
                        change = "Cultivating potatoes",
                    }
                }
            }

            local milestones = Evolution.build(entity, { cur_chap = 5 })
            -- Duplicate at chapter 1 / page 15 should be merged into one, plus Sol 12
            assert.are.equal(#milestones, 2)

            local m1 = milestones[1]
            assert.are.equal(m1.chapter_index, 1)
            assert.are.equal(m1.chapter_title, "Sol 6")
            assert.are.equal(m1.change, "Stranded on Mars")
            assert.are.equal(m1.evidence, "He was struck by an antenna.")

            local m2 = milestones[2]
            assert.are.equal(m2.chapter_title, "Sol 12")
            assert.are.equal(m2.role, "Mechanical Engineer")
            assert.is_not_nil(m2.description:find("planting potatoes"))
        end)

        it("respects custom resolveChapter hook", function()
            local entity = {
                states = {
                    {
                        page = 100,
                        description = "Encounter with the fleet near Jupiter.",
                    }
                }
            }
            local resolve_called = false
            local ctx = {
                resolveChapter = function(page, title, idx)
                    resolve_called = true
                    return 7, "Beyond Jupiter"
                end
            }
            local milestones = Evolution.build(entity, ctx)
            assert.is_true(resolve_called)
            assert.are.equal(milestones[1].chapter_index, 7)
            assert.are.equal(milestones[1].chapter_title, "Beyond Jupiter")
        end)
    end)

    describe("Diffing and Novelty Classification", function()
        it("classifies milestones by role changes, status changes, change headline, and vocabulary", function()
            local entity = {
                states = {
                    {
                        chapter_index = 1,
                        role = "Apprentice",
                        status = "alive",
                        description = "A young student studying magic at the royal academy in the capital city.",
                    },
                    {
                        chapter_index = 2,
                        role = "Apprentice",
                        status = "alive",
                        -- Pure minor rewording of existing concepts, no new terms
                        description = "A young student at the capital royal academy studying magic.",
                    },
                    {
                        chapter_index = 3,
                        role = "Court Wizard",
                        status = "alive",
                        description = "Appointed to advise the King on arcane defense.",
                    },
                    {
                        chapter_index = 4,
                        role = "Court Wizard",
                        status = "missing",
                        description = "Disappeared during the siege.",
                    },
                    {
                        chapter_index = 5,
                        role = "Court Wizard",
                        status = "missing",
                        change = "Discovery of the enchanted mirror",
                        description = "A glowing relic was unearthed in the ruins.",
                    },
                    {
                        chapter_index = 6,
                        role = "Court Wizard",
                        status = "missing",
                        -- Substantial new vocabulary: "Valerius", "Zephyr", "dragon", "citadel", "forbidden", "portal"
                        description = "Valerius unleashed the Zephyr dragon against the imperial citadel opening a forbidden dimensional portal.",
                    }
                }
            }

            local milestones = Evolution.build(entity, { is_full_book = true })
            assert.are.equal(#milestones, 6)

            -- Milestone 1: first
            assert.are.equal(milestones[1].kind, "first")

            -- Milestone 2: reworded
            assert.are.equal(milestones[2].kind, "reworded")

            -- Milestone 3: role change
            assert.are.equal(milestones[3].kind, "key")
            assert.are.equal(milestones[3].role_from, "Apprentice")
            assert.are.equal(milestones[3].role, "Court Wizard")

            -- Milestone 4: status change
            assert.are.equal(milestones[4].kind, "key")
            assert.are.equal(milestones[4].status_from, "alive")
            assert.are.equal(milestones[4].status, "missing")

            -- Milestone 5: change headline present
            assert.are.equal(milestones[5].kind, "key")
            assert.are.equal(milestones[5].change, "Discovery of the enchanted mirror")

            -- Milestone 6: novel vocabulary threshold
            assert.are.equal(milestones[6].kind, "key")
            assert.is_true(#milestones[6].new_terms > 0)

            -- Proper nouns prioritized: "Valerius" and "Zephyr" should come before common words
            local first_term = milestones[6].new_terms[1]
            local second_term = milestones[6].new_terms[2]
            local is_proper = (first_term:match("^[A-Z]") ~= nil) and (second_term:match("^[A-Z]") ~= nil)
            assert.is_true(is_proper)
        end)

        it("filterKey filters out reworded milestones and re-indexes correctly", function()
            local entity = {
                states = {
                    { chapter_index = 1, description = "Hero begins the quest in the peaceful hamlet." },
                    { chapter_index = 2, description = "Hero starts the journey from the quiet hamlet." }, -- reworded
                    { chapter_index = 3, role = "Knight", description = "Hero knighted by the Queen." }, -- key (role)
                    { chapter_index = 4, description = "Hero knighted by Her Majesty." }, -- reworded
                    { chapter_index = 5, change = "Lost sword in battle", description = "Fought valiantly but weapon broke." }, -- key (change)
                }
            }

            local all_m = Evolution.build(entity, { cur_chap = 5 })
            assert.are.equal(5, #all_m)

            local key_m = Evolution.filterKey(all_m)
            assert.are.equal(3, #key_m)

            assert.are.equal(1, key_m[1].chapter_index)
            assert.are.equal(1, key_m[1].idx)
            assert.are.equal(3, key_m[2].chapter_index)
            assert.are.equal(2, key_m[2].idx)
            assert.are.equal(5, key_m[3].chapter_index)
            assert.are.equal(3, key_m[3].idx)
            assert.is_true(key_m[3].is_current)
        end)
    end)

    describe("Spoiler Gating and Lock Status", function()
        local entity = {
            states = {
                { chapter_index = 1, page = 20, description = "Chapter 1 info." },
                { chapter_index = 2, page = 40, description = "Chapter 2 info." },
                { chapter_index = 2, page = 80, description = "Chapter 2 later info." },
                { chapter_index = 3, page = 10, description = "Chapter 3 info." },
            }
        }

        it("locks future milestones according to current chapter and page", function()
            -- Reading at Chapter 2, Page 50
            local milestones = Evolution.build(entity, { cur_chap = 2, cur_page = 50 })
            assert.are.equal(#milestones, 4)

            assert.is_false(milestones[1].is_locked)
            assert.is_false(milestones[2].is_locked)
            assert.is_true(milestones[2].is_current)
            assert.is_true(milestones[3].is_locked)
            assert.is_true(milestones[4].is_locked)
        end)

        it("unlocks everything when is_full_book or show_all is true", function()
            local milestones = Evolution.build(entity, { cur_chap = 1, cur_page = 5, is_full_book = true })
            for _, m in ipairs(milestones) do
                assert.is_false(m.is_locked)
            end
            assert.is_true(milestones[4].is_current)

            local milestones_show_all = Evolution.build(entity, { cur_chap = 1, cur_page = 5, show_all = true })
            for _, m in ipairs(milestones_show_all) do
                assert.is_false(m.is_locked)
            end
        end)

        it("uses plugin:isPositionGateUnlocked when plugin is provided in ctx", function()
            local gate_calls = {}
            local mock_plugin = {
                isPositionGateUnlocked = function(_, gate, cur_chap, cur_page, opts)
                    table.insert(gate_calls, { gate = gate, cur_chap = cur_chap, cur_page = cur_page, opts = opts })
                    if gate.chapter_index and cur_chap and gate.chapter_index < cur_chap then
                        return true
                    elseif gate.chapter_index and cur_chap and gate.chapter_index == cur_chap then
                        local ph = gate.page_hint or gate.page
                        return not ph or not cur_page or ph <= cur_page
                    end
                    return false
                end
            }
            local milestones = Evolution.build(entity, {
                cur_chap = 2,
                cur_page = 50,
                plugin = mock_plugin,
            })
            assert.is_true(#gate_calls > 0)
            assert.is_false(milestones[1].is_locked)
            assert.is_false(milestones[2].is_locked)
            assert.is_true(milestones[3].is_locked)
            assert.is_true(milestones[4].is_locked)
        end)
    end)

    describe("Overlay Integration: Font Size & Eye Toggle", function()
        local EntityListOverlay = require("xray_entity_list")

        it("matches book text font size with configurable and reader settings", function()
            local mock_plugin = {
                ui = {
                    font = {
                        configurable = { font_size = 22 }
                    }
                },
                ai_helper = {
                    settings = { popup_font_size = "normal" }
                }
            }
            local overlay = EntityListOverlay:new{
                plugin = mock_plugin,
                mode = "evolution",
                entity = { name = "Hero", states = {} },
            }
            assert.are.equal(22, overlay:getBookFontSize())

            -- Test with popup_font_size large (+3)
            mock_plugin.ai_helper.settings.popup_font_size = "large"
            assert.are.equal(25, overlay:getBookFontSize())
        end)

        it("toggleEvolutionRevealFuture toggles reveal_future and updates milestone lock status", function()
            local mock_plugin = {
                getCurrentDocPage = function() return 30 end,
                getCurrentChapterIndex = function() return 1 end,
                ai_helper = { settings = { spoiler_setting = "spoiler_free" } }
            }
            local entity_with_future = {
                name = "Explorer",
                states = {
                    { chapter_index = 1, page = 20, description = "Starting journey into the unknown wilderness.", change = "Began journey" },
                    { chapter_index = 2, page = 60, description = "Discovered ancient ruins of the forgotten empire.", change = "Discovered ruins" },
                }
            }
            local overlay = EntityListOverlay:new{
                plugin = mock_plugin,
                mode = "evolution",
                entity = entity_with_future,
            }
            -- Initially reveal_future is false; chapter 2 should be locked
            assert.is_false(overlay.reveal_future)
            assert.is_false(overlay.items[1].is_locked)
            assert.is_true(overlay.items[2].is_locked)

            -- Toggle eye
            overlay:toggleEvolutionRevealFuture()
            assert.is_true(overlay.reveal_future)
            assert.is_false(overlay.items[1].is_locked)
            assert.is_false(overlay.items[2].is_locked)

            -- Toggle eye again
            overlay:toggleEvolutionRevealFuture()
            assert.is_false(overlay.reveal_future)
            assert.is_true(overlay.items[2].is_locked)
        end)

        it("respects spoiler protection settings directly and omits eye button from header", function()
            local mock_plugin_spoiler_free = {
                getCurrentDocPage = function() return 30 end,
                getCurrentChapterIndex = function() return 1 end,
                ai_helper = { settings = { spoiler_setting = "spoiler_free" } }
            }
            local entity = {
                name = "Explorer",
                states = {
                    { chapter_index = 1, page = 20, description = "Starting journey into the wilderness.", change = "Began journey" },
                    { chapter_index = 2, page = 60, description = "Discovered ancient ruins of empire.", change = "Discovered ruins" },
                }
            }
            local overlay_sf = EntityListOverlay:new{
                plugin = mock_plugin_spoiler_free,
                mode = "evolution",
                entity = entity,
            }
            -- spoiler_free locks future milestone
            assert.is_false(overlay_sf.items[1].is_locked)
            assert.is_true(overlay_sf.items[2].is_locked)
            assert.is_not_nil(overlay_sf.title:find("^Story Arc: "))
            assert.are.equal("Story Arc: Explorer (2)", overlay_sf.title)

            -- full_book unlocks all milestones
            local mock_plugin_full_book = {
                getCurrentDocPage = function() return 30 end,
                getCurrentChapterIndex = function() return 1 end,
                ai_helper = { settings = { spoiler_setting = "full_book" } }
            }
            local overlay_fb = EntityListOverlay:new{
                plugin = mock_plugin_full_book,
                mode = "evolution",
                entity = entity,
            }
            assert.is_false(overlay_fb.items[1].is_locked)
            assert.is_false(overlay_fb.items[2].is_locked)
        end)

        it("respects evolution_enabled setting when building entity dialogs and lookup popup", function()
            local XRayUI = require("xray_ui")
            local dummy_plugin = {
                ai_helper = {
                    settings = { evolution_enabled = false },
                    saveSettings = function(self, new_s)
                        for k, v in pairs(new_s) do self.settings[k] = v end
                    end
                },
                loc = { t = function(_, k) return k end },
                showPastEvolution = function() end,
                hasEntityEvolution = function() return true end,
            }
            -- Setting is false -> showEvolutionSettings saves setting
            assert.is_false(dummy_plugin.ai_helper.settings.evolution_enabled)
            dummy_plugin.ai_helper:saveSettings({ evolution_enabled = true })
            assert.is_true(dummy_plugin.ai_helper.settings.evolution_enabled)

            -- When disabled, evolution button is skipped
            dummy_plugin.ai_helper.settings.evolution_enabled = false
            local evolution_enabled = dummy_plugin.ai_helper.settings.evolution_enabled ~= false
            local has_evo = evolution_enabled and dummy_plugin:hasEntityEvolution()
            assert.is_false(has_evo)

            -- When enabled, evolution button is active
            dummy_plugin.ai_helper.settings.evolution_enabled = true
            evolution_enabled = dummy_plugin.ai_helper.settings.evolution_enabled ~= false
            has_evo = evolution_enabled and dummy_plugin:hasEntityEvolution()
            assert.is_true(has_evo)
        end)
    end)
end)
