-- spec/xray_seriesmanager_spec.lua
require("spec.spec_helper")
local SeriesManager = require("xray_seriesmanager")
local xray_fetch = require("xray_fetch")

describe("xray_seriesmanager", function()
    local manager
    local test_slug = "the_wheel_of_time"
    local test_cache_path = "/tmp/koreader/settings/xray/series/" .. test_slug .. ".lua"

    before_each(function()
        manager = SeriesManager:new()
        -- Ensure clean caching directory
        os.execute("rm -rf /tmp/koreader")
        os.execute("mkdir -p /tmp/koreader/settings/xray/series")
    end)

    after_each(function()
        os.execute("rm -rf /tmp/koreader")
    end)

    describe("makeSlug", function()
        it("creates correct slug from series name", function()
            local props = { series = "The Wheel of Time", seriesindex = 3 }
            local info = manager:detectSeries(props)
            assert.is_not_nil(info)
            assert.are.equal("the_wheel_of_time", info.slug)

            local props_punc = { series = "A Game... of Thrones!!", seriesindex = 1 }
            local info_punc = manager:detectSeries(props_punc)
            assert.are.equal("a_game_of_thrones", info_punc.slug)
        end)
    end)

    describe("extractIndexFromTitle", function()
        it("extracts index from standard numeric patterns", function()
            assert.are.equal(2, manager:extractIndexFromTitle("Book 02 - Dark Tide I - Onslaught"))
            assert.are.equal(1, manager:extractIndexFromTitle("The Way of Kings (The Stormlight Archive, #1)"))
            assert.are.equal(2, manager:extractIndexFromTitle("Dune Messiah (Chronicles of Dune Vol. 2)"))
            assert.are.equal(3, manager:extractIndexFromTitle("The Hero of Ages (Volume 3)"))
            assert.are.equal(4, manager:extractIndexFromTitle("Bk. 4 - Wizard and Glass"))
            assert.are.equal(5, manager:extractIndexFromTitle("Nemesis Games (The Expanse Part 5)"))
            assert.are.equal(6, manager:extractIndexFromTitle("No. 06 - Babylon's Ashes"))
        end)

        it("extracts index from series name prefix in title", function()
            assert.are.equal(3, manager:extractIndexFromTitle("The New Jedi Order 03 - Ruin", "The New Jedi Order"))
            assert.are.equal(2, manager:extractIndexFromTitle("The New Jedi Order: 2 - Dark Tide", "The New Jedi Order"))
        end)

        it("extracts index from word numbers", function()
            assert.are.equal(2, manager:extractIndexFromTitle("Words of Radiance: Book Two of the Stormlight Archive"))
            assert.are.equal(1, manager:extractIndexFromTitle("The Final Empire - Book One"))
            assert.are.equal(3, manager:extractIndexFromTitle("Volume Three: The Return of the King"))
        end)

        it("extracts index from Roman numerals", function()
            assert.are.equal(4, manager:extractIndexFromTitle("Book IV - The Shadow Rising"))
            assert.are.equal(5, manager:extractIndexFromTitle("The Fires of Heaven - Volume V"))
        end)

        it("returns nil when title contains no series index pattern", function()
            assert.is_nil(manager:extractIndexFromTitle("1984"))
            assert.is_nil(manager:extractIndexFromTitle("Catch-22"))
            assert.is_nil(manager:extractIndexFromTitle("A Game of Thrones"))
        end)
    end)

    describe("detectSeries", function()
        it("detects series from EPUB props.series and props.seriesindex", function()
            local props = { series = "Mistborn", seriesindex = 2 }
            local info = manager:detectSeries(props)
            assert.is_not_nil(info)
            assert.are.equal("Mistborn", info.name)
            assert.are.equal(2, info.index)
            assert.are.equal("mistborn", info.slug)
        end)

        it("detects series from EPUB props.Series and props.series_index", function()
            local props = { Series = "Stormlight Archive", series_index = 4 }
            local info = manager:detectSeries(props)
            assert.is_not_nil(info)
            assert.are.equal("Stormlight Archive", info.name)
            assert.are.equal(4, info.index)
            assert.are.equal("stormlight_archive", info.slug)
        end)

        it("extracts index from title when props.series is present but series_index is missing", function()
            local props = { series = "The New Jedi Order" }
            local title = "Book 02 - Dark Tide I - Onslaught"
            local info = manager:detectSeries(props, title, "Michael A. Stackpole", nil)
            assert.is_not_nil(info)
            assert.are.equal("The New Jedi Order", info.name)
            assert.are.equal(2, info.index)
            assert.are.equal("the_new_jedi_order", info.slug)
        end)

        it("falls back to AI for index when props.series is present, series_index is missing, and title has no index", function()
            local props = { series = "The New Jedi Order" }
            local title = "Dark Tide I - Onslaught"
            local mock_ai = {
                createPrompt = function(self, t, author, context, prompt_type)
                    assert.are.equal("Dark Tide I - Onslaught", t)
                    assert.are.equal("series_detect", prompt_type)
                    return { type = "detect" }
                end,
                executeUnifiedRequest = function(self, prompt)
                    return {
                        is_series = true,
                        series_name = "The New Jedi Order",
                        book_index = 2
                    }
                end
            }

            local info = manager:detectSeries(props, title, "Michael A. Stackpole", mock_ai)
            assert.is_not_nil(info)
            assert.are.equal("The New Jedi Order", info.name)
            assert.are.equal(2, info.index)
            assert.are.equal("the_new_jedi_order", info.slug)
        end)

        it("falls back to AI detection when metadata is missing", function()
            local mock_ai = {
                createPrompt = function(self, title, author, context, prompt_type)
                    assert.are.equal("The Way of Kings", title)
                    assert.are.equal("Brandon Sanderson", author)
                    assert.are.equal("series_detect", prompt_type)
                    return { type = "detect" }
                end,
                executeUnifiedRequest = function(self, prompt)
                    return {
                        is_series = true,
                        series_name = "The Stormlight Archive",
                        book_index = 1
                    }
                end
            }

            local info = manager:detectSeries({}, "The Way of Kings", "Brandon Sanderson", mock_ai)
            assert.is_not_nil(info)
            assert.are.equal("The Stormlight Archive", info.name)
            assert.are.equal(1, info.index)
            assert.are.equal("the_stormlight_archive", info.slug)
        end)

        it("returns nil if AI reports book is not part of a series", function()
            local mock_ai = {
                createPrompt = function() return {} end,
                executeUnifiedRequest = function()
                    return { is_series = false }
                end
            }
            local info = manager:detectSeries({}, "Standalone Book", "Author", mock_ai)
            assert.is_nil(info)
        end)
    end)

    describe("getPriorBookList", function()
        it("returns prior book list from AI", function()
            local series_info = { name = "Mistborn", index = 3, slug = "mistborn" }
            local mock_ai = {
                createPrompt = function(self, title, author, context, prompt_type)
                    assert.is_nil(title)
                    assert.are.equal("Brandon Sanderson", author)
                    assert.are.equal("Mistborn", context.series_name)
                    assert.are.equal(3, context.index)
                    assert.are.equal("prior_book_list", prompt_type)
                    return { type = "list" }
                end,
                executeUnifiedRequest = function(self, prompt)
                    return {
                        prior_books = {
                            { index = 1, title = "The Final Empire", author = "Brandon Sanderson" },
                            { index = 2, title = "The Well of Ascension", author = "Brandon Sanderson" }
                        }
                    }
                end
            }

            local list = manager:getPriorBookList(series_info, "Brandon Sanderson", mock_ai)
            assert.are.equal(2, #list)
            assert.are.equal("The Final Empire", list[1].title)
            assert.are.equal(1, list[1].index)
            assert.are.equal("The Well of Ascension", list[2].title)
            assert.are.equal(2, list[2].index)
        end)

        it("generates fallback placeholders if AI helper is missing or returns nil", function()
            local series_info = { name = "Mistborn", index = 3, slug = "mistborn" }
            local list = manager:getPriorBookList(series_info, "Brandon Sanderson", nil)
            assert.are.equal(2, #list)
            assert.are.equal("Mistborn (Book 1)", list[1].title)
            assert.are.equal("Brandon Sanderson", list[1].author)
            assert.are.equal("Mistborn (Book 2)", list[2].title)
        end)

        it("returns empty list if book index is 1", function()
            local series_info = { name = "Mistborn", index = 1, slug = "mistborn" }
            local list = manager:getPriorBookList(series_info, "Brandon Sanderson", nil)
            assert.are.equal(0, #list)
        end)
    end)

    describe("caching", function()
        it("saves and loads series cache correctly", function()
            local test_data = {
                books = {
                    [1] = {
                        characters = {
                            { name = "Kelsier", description = "Survivor of Hathsin" }
                        },
                        locations = {
                            { name = "Luthadel", description = "Capital city" }
                        }
                    }
                }
            }

            local saved = manager:saveSeriesCache(test_slug, test_data)
            assert.is_true(saved)

            local loaded = manager:loadSeriesCache(test_slug)
            assert.is_not_nil(loaded)
            assert.are.equal("6.0", loaded.cache_version)
            assert.is_not_nil(loaded.books[1])
            assert.are.equal("Kelsier", loaded.books[1].characters[1].name)
            assert.are.equal("Survivor of Hathsin", loaded.books[1].characters[1].description)
            assert.are.equal("Luthadel", loaded.books[1].locations[1].name)
        end)

        it("returns nil if loading non-existent slug", function()
            local loaded = manager:loadSeriesCache("nonexistent_slug")
            assert.is_nil(loaded)
        end)
    end)

    describe("mergeSeriesContext", function()
        local plugin

        before_each(function()
            plugin = createMockPlugin()
            for k, v in pairs(xray_fetch) do
                plugin[k] = v
            end
            plugin.cache_manager = {
                saveCache = function() return true end,
                asyncSaveCache = function() return true end,
                loadCache = function() return {} end
            }
        end)

        it("merges characters, locations, terms, and timeline events additively", function()
            plugin.characters = {
                { name = "Vin", description = "Street urchin" }
            }
            plugin.locations = {
                { name = "Luthadel", description = "Current city details" }
            }
            plugin.terms = {
                { name = "Allomancy", definition = "Current definition" }
            }
            plugin.timeline = {
                { chapter = "Chapter 1", event = "Current book event", page = 5 }
            }

            local cache_data = {
                books = {
                    [1] = {
                        characters = {
                            { name = "Vin", description = "Survivor's apprentice" },
                            { name = "Kelsier", description = "The Survivor" }
                        },
                        locations = {
                            { name = "Luthadel", description = "Capital of Final Empire" },
                            { name = "Hathsin", description = "Pits of Hathsin" }
                        },
                        terms = {
                            { name = "Allomancy", definition = "Metal burning art" },
                            { name = "Feruchemy", definition = "Metal storing art" }
                        },
                        timeline = {
                            { chapter = "Prologue", event = "Kelsier destroys pits" }
                        }
                    }
                }
            }

            local series_info = { name = "Mistborn", index = 2, slug = "mistborn" }
            plugin:mergeSeriesContext(cache_data, series_info)

            -- Verify existing character is prepended with [From Book N]
            assert.are.equal(2, #plugin.characters)
            local vin = plugin.characters[1]
            assert.are.equal("Vin", vin.name)
            assert.truthy(vin.description:find("^%[From Book 1%] Survivor's apprentice"))
            assert.truthy(vin.description:find("Street urchin$"))

            -- Verify new character is inserted with source = series_prior
            local kelsier = plugin.characters[2]
            assert.are.equal("Kelsier", kelsier.name)
            assert.are.equal("series_prior", kelsier.source)
            assert.are.equal(1, kelsier.source_book)

            -- Verify locations merging
            assert.are.equal(2, #plugin.locations)
            local luthadel = plugin.locations[1]
            assert.truthy(luthadel.description:find("^%[From Book 1%] Capital of Final Empire"))
            local hathsin = plugin.locations[2]
            assert.are.equal("Hathsin", hathsin.name)
            assert.are.equal("series_prior", hathsin.source)

            -- Verify terms merging
            assert.are.equal(2, #plugin.terms)
            local allomancy = plugin.terms[1]
            assert.truthy(allomancy.definition:find("^%[From Book 1%] Metal burning art"))
            local feruchemy = plugin.terms[2]
            assert.are.equal("Feruchemy", feruchemy.name)
            assert.are.equal("series_prior", feruchemy.source)

            -- Verify timeline events: prior events should have source = series_prior, negative page
            -- (sortTimelineByTOC is a no-op in tests; search by source rather than assuming position)
            assert.are.equal(2, #plugin.timeline)
            local prior_ev = nil
            for _, ev in ipairs(plugin.timeline) do
                if ev.source == "series_prior" then prior_ev = ev; break end
            end
            assert.is_not_nil(prior_ev)
            assert.are.equal("[Book 1]", prior_ev.chapter)
            assert.are.equal("Kelsier destroys pits", prior_ev.event)
            assert.are.equal("series_prior", prior_ev.source)
            assert.are.equal(-999, prior_ev.page) -- -1000 + 1
        end)

        it("ensures re-runnability is clean and doesn't duplicate prefixes or list items", function()
            plugin.characters = {
                { name = "Vin", description = "Street urchin" }
            }
            local cache_data = {
                books = {
                    [1] = {
                        characters = {
                            { name = "Vin", description = "Survivor's apprentice" },
                            { name = "Kelsier", description = "The Survivor" }
                        }
                    }
                }
            }
            local series_info = { name = "Mistborn", index = 2, slug = "mistborn" }

            -- Run merge once
            plugin:mergeSeriesContext(cache_data, series_info)
            assert.are.equal(2, #plugin.characters)

            -- Run merge a second time
            plugin:mergeSeriesContext(cache_data, series_info)

            -- Count of characters should remain 2 (prior Kelsier removed and re-added, not duplicated)
            assert.are.equal(2, #plugin.characters)
            local vin = plugin.characters[1]
            -- Description should contain prefix only once
            local count = 0
            for _ in vin.description:gmatch("%[From Book 1%]") do
                count = count + 1
            end
            assert.are.equal(1, count)
        end)

        it("assigns sort_order >= 10000 to prior characters so they sort after current characters", function()
            plugin.characters = {
                { name = "Vin", sort_order = 1 },
                { name = "Elend", sort_order = 2 }
            }
            local cache_data = {
                books = {
                    [1] = {
                        characters = {
                            { name = "Kelsier", sort_order = 1 }
                        }
                    }
                }
            }
            local series_info = { name = "Mistborn", index = 2, slug = "mistborn" }
            plugin:mergeSeriesContext(cache_data, series_info)

            assert.are.equal(3, #plugin.characters)
            local kelsier = plugin.characters[3]
            assert.are.equal("Kelsier", kelsier.name)
            assert.are.equal("series_prior", kelsier.source)
            assert.is_true(kelsier.sort_order >= 10000)
        end)
    end)

    describe("syncBookToSeriesCache", function()
        it("saves clean book data with source=local_xray and tracks book_path", function()
            local book_data = {
                title = "The Final Empire",
                author = "Brandon Sanderson",
                characters = {
                    { name = "Kelsier", description = "The Survivor" },
                    { name = "Old Char", source = "series_prior" } -- should be filtered out
                },
                locations = {
                    { name = "Luthadel", description = "Capital" }
                },
                terms = {},
                timeline = {
                    { chapter = "Chapter 1", event = "Beginning" }
                }
            }

            local ok = manager:syncBookToSeriesCache("mistborn", 1, book_data, "/books/mistborn_1.epub")
            assert.is_true(ok)

            local loaded = manager:loadSeriesCache("mistborn")
            assert.is_not_nil(loaded)
            assert.is_not_nil(loaded.books[1])
            assert.are.equal("local_xray", loaded.books[1].source)
            assert.are.equal("The Final Empire", loaded.books[1].title)
            assert.are.equal(1, #loaded.books[1].characters)
            assert.are.equal("Kelsier", loaded.books[1].characters[1].name)
            assert.are.equal("/books/mistborn_1.epub", loaded.book_paths[1])
        end)
    end)

    describe("findLocalBookXRay", function()
        local series_info = { name = "Mistborn", slug = "mistborn", index = 2 }

        it("returns existing local_xray entry from SeriesCache directly", function()
            local cache_data = {
                books = {
                    [1] = {
                        title = "The Final Empire",
                        source = "local_xray",
                        characters = { { name = "Kelsier" } }
                    }
                }
            }
            manager:saveSeriesCache("mistborn", cache_data)

            local found = manager:findLocalBookXRay(series_info, 1, "/books/book2.epub", "The Final Empire", nil)
            assert.is_not_nil(found)
            assert.are.equal("The Final Empire", found.title)
            assert.are.equal("local_xray", found.source)
        end)

        it("discovers local book from tracked book_paths", function()
            local mock_cache_mgr = {
                loadCache = function(self, path)
                    if path == "/books/tracked_book1.epub" then
                        return {
                            title = "The Final Empire",
                            series_slug = "mistborn",
                            series_index = 1,
                            characters = { { name = "Kelsier" } },
                            locations = {},
                            terms = {},
                            timeline = {}
                        }
                    end
                    return nil
                end
            }

            local initial_cache = {
                book_paths = {
                    [1] = "/books/tracked_book1.epub"
                },
                books = {}
            }
            manager:saveSeriesCache("mistborn", initial_cache)

            local found = manager:findLocalBookXRay(series_info, 1, "/books/book2.epub", "The Final Empire", mock_cache_mgr)
            assert.is_not_nil(found)
            assert.are.equal("The Final Empire", found.title)
            assert.are.equal("local_xray", found.source)
        end)

        it("discovers local book via directory scanning of sibling SDRs", function()
            local lfs = require("lfs")
            local orig_dir = lfs.dir
            lfs.dir = function(path)
                local entries = { "01 - The Final Empire.sdr", "02 - The Well of Ascension.epub" }
                local idx = 0
                return function()
                    idx = idx + 1
                    return entries[idx]
                end
            end

            -- Write a mock xray_cache.lua file in tmp
            local mock_sdr_dir = "/tmp/koreader/01 - The Final Empire.sdr"
            os.execute("mkdir -p '" .. mock_sdr_dir .. "'")
            local f = io.open(mock_sdr_dir .. "/xray_cache.lua", "w")
            f:write("return { title = 'The Final Empire', series_slug = 'mistborn', series_index = 1, characters = {{ name = 'Kelsier' }} }")
            f:close()

            local found = manager:findLocalBookXRay(series_info, 1, "/tmp/koreader/02 - The Well of Ascension.epub", "The Final Empire", nil)
            lfs.dir = orig_dir

            assert.is_not_nil(found)
            assert.are.equal("The Final Empire", found.title)
            assert.are.equal("local_xray", found.source)
        end)

        it("returns nil when no matching local book is found", function()
            local found = manager:findLocalBookXRay(series_info, 1, "/nonexistent/book2.epub", "Unknown Title", nil)
            assert.is_nil(found)
        end)
    end)

    describe("Prompt safeguards and timeline synthesis", function()
        local ai_helper

        before_each(function()
            ai_helper = require("xray_aihelper")
            local en_prompts = require("prompts/en")
            ai_helper.prompts = en_prompts
        end)

        it("injects strict anti-spoiler safeguards into series_book_summary", function()
            local context = {
                series_name = "Mistborn",
                index = 1
            }
            local prompt = ai_helper:createPrompt("The Final Empire", "Brandon Sanderson", context, "series_book_summary")

            assert.is_not_nil(prompt:find("ABSOLUTE SPOILER BOUNDARY"))
            assert.is_not_nil(prompt:find("FORBIDDEN LATER%-BOOK INFORMATION"))
            assert.is_not_nil(prompt:find("CRITICAL ANTI%-SPOILER SAFEGUARD"))
            assert.is_not_nil(prompt:find("reborn"))
        end)

        it("formats local_timeline_summary with grounding constraint and chapter events", function()
            local context = {
                series_name = "Mistborn",
                index = 1,
                events_text = "[Chapter 1] Kelsier visits the plantation.\n\n[Chapter 2] Vin hides in Luthadel."
            }
            local prompt = ai_helper:createPrompt("The Final Empire", "Brandon Sanderson", context, "local_timeline_summary")

            assert.is_not_nil(prompt:find("STRICT GROUNDING CONSTRAINT"))
            assert.is_not_nil(prompt:find("Kelsier visits the plantation"))
            assert.is_not_nil(prompt:find("Vin hides in Luthadel"))
            assert.is_not_nil(prompt:find("TARGET BOOK INDEX: 1"))
        end)
    end)

    describe("Duplicate index pruning and self-import guards", function()
        it("prunes old index entry when a book is re-indexed to a new position", function()
            local slug = "test_series"
            local book_path = "/path/to/book.epub"
            local bdata1 = { title = "Lethal White", characters = { { name = "Strike" } } }
            manager:syncBookToSeriesCache(slug, 1, bdata1, book_path)

            local c1 = manager:loadSeriesCache(slug)
            assert.is_not_nil(c1.books[1])
            assert.are.equal(book_path, c1.book_paths[1])

            -- Re-index to book 4
            local bdata4 = { title = "Lethal White", characters = { { name = "Strike" }, { name = "Robin" } } }
            manager:syncBookToSeriesCache(slug, 4, bdata4, book_path)

            local c4 = manager:loadSeriesCache(slug)
            assert.is_nil(c4.books[1], "Old index 1 should be pruned")
            assert.is_nil(c4.book_paths[1], "Old book_paths 1 should be pruned")
            assert.is_not_nil(c4.books[4], "New index 4 should exist")
            assert.are.equal(book_path, c4.book_paths[4])
        end)

        it("avoids self-importing when mergeSeriesContext encounters same book path or title", function()
            local fake_plugin = {
                ui = { document = { file = "/books/book4.epub", getProps = function() return { title = "Lethal White" } end } },
                characters = {},
                locations = {},
                terms = {},
                timeline = {},
                sortDataByFrequency = function(self, list, text, key) return list end,
                assignTimelinePages = function() end,
                sortTimelineByTOC = function() end,
            }
            setmetatable(fake_plugin, { __index = xray_fetch })

            local cache_data = {
                book_paths = {
                    [1] = "/books/book4.epub", -- same path as current book
                    [2] = "/books/book2.epub",
                },
                books = {
                    [1] = { title = "Lethal White", characters = { { name = "Duplicate Strike" } } },
                    [2] = { title = "The Silkworm", characters = { { name = "Silkworm Character" } } },
                }
            }
            local series_info = { index = 4, slug = "cormoran_strike" }
            fake_plugin:mergeSeriesContext(cache_data, series_info)

            -- Should NOT import from book 1 because it's the current book
            local imported_names = {}
            for _, c in ipairs(fake_plugin.characters) do imported_names[c.name] = true end
            assert.is_nil(imported_names["Duplicate Strike"])
            assert.is_true(imported_names["Silkworm Character"])
        end)
    end)
end)

