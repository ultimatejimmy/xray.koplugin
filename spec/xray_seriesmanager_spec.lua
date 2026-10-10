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

        it("saves atomically via temporary file and renames into place", function()
            local test_data = {
                books = {
                    [1] = {
                        title = "Atomic Test",
                        characters = { { name = "Tester" } }
                    }
                }
            }

            local saved = manager:saveSeriesCache(test_slug, test_data)
            assert.is_true(saved)

            -- Confirm target file exists and .tmp file was removed
            local f = io.open(test_cache_path, "r")
            assert.is_not_nil(f)
            if f then f:close() end

            local f_tmp = io.open(test_cache_path .. ".tmp", "r")
            assert.is_nil(f_tmp)
        end)

        it("cleans up temp file and returns false if serialization fails", function()
            local test_data = {
                books = { [1] = { title = "Broken" } }
            }

            -- Mock serializeToFile to throw an error
            local orig_serialize = manager.serializeToFile
            manager.serializeToFile = function() error("Serialization explosion") end

            local saved = manager:saveSeriesCache(test_slug, test_data)
            assert.is_false(saved)

            -- Ensure .tmp was cleaned up
            local f_tmp = io.open(test_cache_path .. ".tmp", "r")
            assert.is_nil(f_tmp)

            manager.serializeToFile = orig_serialize
        end)

        it("does not serialize private underscore fields like _sort_score, _norm_name, and _norm_aliases", function()
            local test_data = {
                books = {
                    [1] = {
                        title = "The Final Empire",
                        characters = {
                            {
                                name = "Kelsier",
                                _sort_score = 1500,
                                _norm_name = "kelsier",
                                aliases = { "Survivor" },
                                _norm_aliases = { "survivor" }
                            }
                        },
                        terms = {
                            {
                                name = "Allomancy",
                                _sort_score = 900
                            }
                        }
                    }
                }
            }

            local saved = manager:saveSeriesCache(test_slug, test_data)
            assert.is_true(saved)

            local f = io.open(test_cache_path, "r")
            assert.is_not_nil(f)
            local content = f:read("*all")
            f:close()

            assert.is_nil(content:find("_sort_score"))
            assert.is_nil(content:find("_norm_name"))
            assert.is_nil(content:find("_norm_aliases"))

            local loaded = manager:loadSeriesCache(test_slug)
            assert.is_not_nil(loaded)
            assert.are.equal("Kelsier", loaded.books[1].characters[1].name)
            assert.is_nil(loaded.books[1].characters[1]._sort_score)
            assert.is_nil(loaded.books[1].characters[1]._norm_name)
            assert.is_nil(loaded.books[1].characters[1]._norm_aliases)
            assert.is_nil(loaded.books[1].terms[1]._sort_score)
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

        it("skips saving to disk when syncing identical book data a second time", function()
            local book_data = {
                title = "The Final Empire",
                author = "Brandon Sanderson",
                characters = {
                    { name = "Kelsier", description = "The Survivor" }
                },
                locations = {
                    { name = "Luthadel", description = "Capital" }
                },
                terms = {},
                timeline = {
                    { chapter = "Chapter 1", event = "Beginning" }
                }
            }

            -- First sync saves to disk
            local ok1 = manager:syncBookToSeriesCache("mistborn", 1, book_data, "/books/mistborn_1.epub")
            assert.is_true(ok1)

            -- Track saveSeriesCache calls
            local save_calls = 0
            local orig_save = manager.saveSeriesCache
            manager.saveSeriesCache = function(self, ...)
                save_calls = save_calls + 1
                return orig_save(self, ...)
            end

            -- Second sync with identical data
            local ok2 = manager:syncBookToSeriesCache("mistborn", 1, book_data, "/books/mistborn_1.epub")
            assert.is_true(ok2)
            assert.are.equal(0, save_calls)

            manager.saveSeriesCache = orig_save
        end)

        it("saves when character description or entity list changes", function()
            local book_data = {
                title = "The Final Empire",
                author = "Brandon Sanderson",
                characters = {
                    { name = "Kelsier", description = "The Survivor" }
                },
                locations = {},
                terms = {},
                timeline = {}
            }

            manager:syncBookToSeriesCache("mistborn", 1, book_data, "/books/mistborn_1.epub")

            local save_calls = 0
            local orig_save = manager.saveSeriesCache
            manager.saveSeriesCache = function(self, ...)
                save_calls = save_calls + 1
                return orig_save(self, ...)
            end

            -- Add a character
            local updated_data = {
                title = "The Final Empire",
                author = "Brandon Sanderson",
                characters = {
                    { name = "Kelsier", description = "The Survivor" },
                    { name = "Vin", description = "Mistborn apprentice" }
                },
                locations = {},
                terms = {},
                timeline = {}
            }

            local ok = manager:syncBookToSeriesCache("mistborn", 1, updated_data, "/books/mistborn_1.epub")
            assert.is_true(ok)
            assert.are.equal(1, save_calls)

            manager.saveSeriesCache = orig_save

            local loaded = manager:loadSeriesCache("mistborn")
            assert.are.equal(2, #loaded.books[1].characters)
        end)

        it("saves when book_path changes", function()
            local book_data = {
                title = "The Final Empire",
                author = "Brandon Sanderson",
                characters = { { name = "Kelsier" } },
                locations = {},
                terms = {},
                timeline = {}
            }

            manager:syncBookToSeriesCache("mistborn", 1, book_data, "/books/mistborn_1.epub")

            local save_calls = 0
            local orig_save = manager.saveSeriesCache
            manager.saveSeriesCache = function(self, ...)
                save_calls = save_calls + 1
                return orig_save(self, ...)
            end

            local ok = manager:syncBookToSeriesCache("mistborn", 1, book_data, "/new/path/mistborn_1.epub")
            assert.is_true(ok)
            assert.are.equal(1, save_calls)

            manager.saveSeriesCache = orig_save

            local loaded = manager:loadSeriesCache("mistborn")
            assert.are.equal("/new/path/mistborn_1.epub", loaded.book_paths[1])
        end)

        it("skips saving when book data contains in-memory _sort_score, _norm_name, or _norm_aliases", function()
            local book_data = {
                title = "The Final Empire",
                author = "Brandon Sanderson",
                characters = {
                    {
                        name = "Kelsier",
                        description = "The Survivor",
                        _sort_score = 5000,
                        _norm_name = "kelsier",
                        aliases = { "Survivor" },
                        _norm_aliases = { "survivor" }
                    }
                },
                locations = {},
                terms = {
                    { name = "Allomancy", description = "Magic system", _sort_score = 3000 }
                },
                timeline = {}
            }

            -- Initial sync saves to disk
            local ok1 = manager:syncBookToSeriesCache("mistborn", 1, book_data, "/books/mistborn_1.epub")
            assert.is_true(ok1)

            local save_calls = 0
            local orig_save = manager.saveSeriesCache
            manager.saveSeriesCache = function(self, ...)
                save_calls = save_calls + 1
                return orig_save(self, ...)
            end

            -- Second sync with the same in-memory data (containing _sort_score)
            local ok2 = manager:syncBookToSeriesCache("mistborn", 1, book_data, "/books/mistborn_1.epub")
            assert.is_true(ok2)
            assert.are.equal(0, save_calls)

            manager.saveSeriesCache = orig_save
        end)

        it("skips saving when syncing clean book cache data against series cache after a merge (Issue #144)", function()
            -- 1. Post-merge book data with _sort_score on characters and terms
            local post_merge_data = {
                title = "Morning Star",
                author = "Pierce Brown",
                characters = {
                    { name = "Darrow", description = "Reaper of Mars", _sort_score = 8000, _norm_name = "darrow" },
                    { name = "Sevro", description = "Howler 1", _sort_score = 6500, _norm_name = "sevro" }
                },
                locations = { { name = "Phobos" } },
                terms = {
                    { name = "SlingBlade", _sort_score = 2000 }
                },
                timeline = {}
            }

            -- Sync post-merge data
            local ok1 = manager:syncBookToSeriesCache("red_rising", 3, post_merge_data, "/books/Morning Star.epub")
            assert.is_true(ok1)

            -- 2. Simulate next book open: loaded from book cache (where CacheManager stripped _sort_score and _norm_*)
            local clean_book_cache_data = {
                title = "Morning Star",
                author = "Pierce Brown",
                characters = {
                    { name = "Darrow", description = "Reaper of Mars" },
                    { name = "Sevro", description = "Howler 1" }
                },
                locations = { { name = "Phobos" } },
                terms = {
                    { name = "SlingBlade" }
                },
                timeline = {}
            }

            local save_calls = 0
            local orig_save = manager.saveSeriesCache
            manager.saveSeriesCache = function(self, ...)
                save_calls = save_calls + 1
                return orig_save(self, ...)
            end

            -- Sync on book open with clean book data
            local ok2 = manager:syncBookToSeriesCache("red_rising", 3, clean_book_cache_data, "/books/Morning Star.epub")
            assert.is_true(ok2)
            assert.are.equal(0, save_calls)

            -- Subsequent open also skips save
            local ok3 = manager:syncBookToSeriesCache("red_rising", 3, clean_book_cache_data, "/books/Morning Star.epub")
            assert.is_true(ok3)
            assert.are.equal(0, save_calls)

            manager.saveSeriesCache = orig_save
        end)

        it("skips saving even if existing series cache file on disk contains _sort_score (backward compatibility)", function()
            -- Simulate legacy series cache file written by 26.9.30.1 that has _sort_score stored on disk
            local legacy_series_path = "/tmp/koreader/settings/xray/series/legacy_series.lua"
            local f = io.open(legacy_series_path, "w")
            assert.is_not_nil(f)
            f:write([[
return {
  cache_version = "6.0",
  series_slug = "legacy_series",
  book_paths = {
    [1] = "/books/legacy_1.epub",
  },
  books = {
    [1] = {
      title = "Legacy Book",
      author = "Legacy Author",
      source = "local_xray",
      characters = {
        {
          name = "Hero",
          description = "Legacy description",
          _sort_score = 4200,
        },
      },
      locations = {},
      terms = {},
      timeline = {},
    },
  },
}
]])
            f:close()

            local save_calls = 0
            local orig_save = manager.saveSeriesCache
            manager.saveSeriesCache = function(self, ...)
                save_calls = save_calls + 1
                return orig_save(self, ...)
            end

            -- Clean book data from book cache
            local book_data = {
                title = "Legacy Book",
                author = "Legacy Author",
                characters = {
                    { name = "Hero", description = "Legacy description" }
                },
                locations = {},
                terms = {},
                timeline = {}
            }

            local ok = manager:syncBookToSeriesCache("legacy_series", 1, book_data, "/books/legacy_1.epub")
            assert.is_true(ok)
            assert.are.equal(0, save_calls)

            manager.saveSeriesCache = orig_save
        end)

        it("filterCurrentOnly strips private underscore fields so new_entry is clean in memory", function()
            local book_data = {
                title = "The Final Empire",
                author = "Brandon Sanderson",
                characters = {
                    {
                        name = "Kelsier",
                        _sort_score = 9999,
                        _norm_name = "kelsier",
                        aliases = { "Survivor" },
                        _norm_aliases = { "survivor" }
                    }
                },
                locations = {},
                terms = {},
                timeline = {}
            }

            local ok = manager:syncBookToSeriesCache("mistborn", 1, book_data, "/books/mistborn_1.epub")
            assert.is_true(ok)

            local loaded = manager:loadSeriesCache("mistborn")
            assert.is_not_nil(loaded)
            assert.is_nil(loaded.books[1].characters[1]._sort_score)
            assert.is_nil(loaded.books[1].characters[1]._norm_name)
            assert.is_nil(loaded.books[1].characters[1]._norm_aliases)
            -- Verify original book_data was not mutated
            assert.are.equal(9999, book_data.characters[1]._sort_score)
            assert.are.equal("kelsier", book_data.characters[1]._norm_name)
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

    describe("Manage Series helpers", function()
        it("writeDocMetadata creates sidecar and saves series info", function()
            local test_epub = "/tmp/koreader/test_book.epub"
            local ok = manager:writeDocMetadata(test_epub, "The Stormlight Archive", 2)
            assert.is_true(ok)

            local meta = manager:readBookMetadata(test_epub)
            assert.is_not_nil(meta)
            assert.are.equal("The Stormlight Archive", meta.series)
            assert.are.equal(2, meta.series_index)
        end)

        it("buildSeriesRoster consolidates cache and current book info", function()
            local slug = "mistborn"
            local cache_data = {
                books = {
                    [1] = { title = "The Final Empire", author = "Brandon Sanderson" },
                },
                book_paths = {
                    [1] = "/tmp/koreader/book1.epub"
                }
            }
            manager:saveSeriesCache(slug, cache_data)

            local book_data = {
                title = "The Well of Ascension",
                author = "Brandon Sanderson",
                series = "Mistborn",
                series_slug = slug,
                series_index = 2
            }
            local props = { series = "Mistborn", series_index = 2 }

            local roster = manager:buildSeriesRoster(book_data, props, "/tmp/koreader/book2.epub")
            assert.is_not_nil(roster)
            assert.are.equal("Mistborn", roster.series_name)
            assert.are.equal(2, #roster.books)
            assert.are.equal(1, roster.books[1].index)
            assert.are.equal("The Final Empire", roster.books[1].title)
            assert.are.equal(2, roster.books[2].index)
            assert.are.equal("The Well of Ascension", roster.books[2].title)
            assert.is_true(roster.books[2].is_current)
        end)
    end)

    describe("getSeriesInfo index fallback and backfill", function()
        it("uses book_data.series_index when present", function()
            local book_data = {
                series_slug = "red_rising",
                series = "Red Rising",
                series_index = 2,
            }
            local props = { series_index = 99 } -- should not override explicit book_data
            local info = manager:getSeriesInfo(book_data, props, "Golden Son", "Pierce Brown")
            assert.is_not_nil(info)
            assert.are.equal("red_rising", info.slug)
            assert.are.equal(2, info.index)
            assert.is_true(info.has_explicit_index)
        end)

        it("falls through to props.series_index and backfills book_data when series_index missing", function()
            local book_data = {
                series_slug = "red_rising",
            }
            local props = { series = "Red Rising", series_index = 2 }
            local info = manager:getSeriesInfo(book_data, props, "Golden Son", "Pierce Brown")
            assert.is_not_nil(info)
            assert.are.equal("red_rising", info.slug)
            assert.are.equal(2, info.index)
            assert.is_true(info.has_explicit_index)
            assert.are.equal("Red Rising", info.name)
            -- Verify in-memory backfill
            assert.are.equal(2, book_data.series_index)
            assert.are.equal("Red Rising", book_data.series)
        end)

        it("falls through to title parsing when series_index missing and props has no index", function()
            local book_data = {
                series_slug = "red_rising",
                series = "Red Rising",
            }
            local props = { series = "Red Rising" }
            local info = manager:getSeriesInfo(book_data, props, "Golden Son (Red Rising #2)", "Pierce Brown")
            assert.is_not_nil(info)
            assert.are.equal(2, info.index)
            assert.is_true(info.has_explicit_index)
            assert.are.equal(2, book_data.series_index)
        end)

        it("defaults to index 1 with has_explicit_index=false when no index is resolvable", function()
            local book_data = {
                series_slug = "red_rising",
            }
            local props = {}
            local info = manager:getSeriesInfo(book_data, props, "Golden Son", "Pierce Brown")
            assert.is_not_nil(info)
            assert.are.equal(1, info.index)
            assert.is_false(info.has_explicit_index)
            -- Does not backfill an unverified default index
            assert.is_nil(book_data.series_index)
        end)
    end)

    describe("syncBookToSeriesCache is_explicit guards", function()
        local slug = "red_rising"

        before_each(function()
            local init_cache = {
                series_slug = slug,
                books = {
                    [1] = { title = "Red Rising", author = "Pierce Brown", source = "local_xray" },
                    [2] = { title = "Golden Son", author = "Pierce Brown", source = "local_xray" },
                },
                book_paths = {
                    [1] = "/books/Red Rising.epub",
                    [2] = "/books/Golden Son.epub",
                }
            }
            manager:saveSeriesCache(slug, init_cache)
        end)

        it("refuses to overwrite a different book when is_explicit is false", function()
            local golden_son_data = {
                title = "Golden Son",
                author = "Pierce Brown",
                characters = {},
            }
            -- Attempting to sync to slot 1 with is_explicit = false must fail because slot 1 is Red Rising
            local ok = manager:syncBookToSeriesCache(slug, 1, golden_son_data, "/books/Golden Son.epub", false)
            assert.is_false(ok)

            -- Cache in slot 1 and slot 2 must be completely preserved
            local c = manager:loadSeriesCache(slug)
            assert.are.equal("Red Rising", c.books[1].title)
            assert.are.equal("/books/Red Rising.epub", c.book_paths[1])
            assert.are.equal("Golden Son", c.books[2].title)
            assert.are.equal("/books/Golden Son.epub", c.book_paths[2])
        end)

        it("refuses to move an existing book to a new slot when is_explicit is false", function()
            local golden_son_data = {
                title = "Golden Son",
                author = "Pierce Brown",
                characters = {},
            }
            -- Attempting to sync Golden Son (which is already in slot 2) to empty slot 3 with is_explicit = false
            local ok = manager:syncBookToSeriesCache(slug, 3, golden_son_data, "/books/Golden Son.epub", false)
            assert.is_false(ok)

            local c = manager:loadSeriesCache(slug)
            assert.is_nil(c.books[3])
            assert.are.equal("Golden Son", c.books[2].title)
        end)

        it("allows syncing to an empty slot when is_explicit is false and book is not elsewhere", function()
            local iron_gold_data = {
                title = "Iron Gold",
                author = "Pierce Brown",
                characters = {},
            }
            local ok = manager:syncBookToSeriesCache(slug, 4, iron_gold_data, "/books/Iron Gold.epub", false)
            assert.is_true(ok)

            local c = manager:loadSeriesCache(slug)
            assert.is_not_nil(c.books[4])
            assert.are.equal("Iron Gold", c.books[4].title)
        end)

        it("allows updating the same book at its existing slot when is_explicit is false", function()
            local updated_gs = {
                title = "Golden Son",
                author = "Pierce Brown",
                characters = { { name = "Darrow" } },
            }
            local ok = manager:syncBookToSeriesCache(slug, 2, updated_gs, "/books/Golden Son.epub", false)
            assert.is_true(ok)

            local c = manager:loadSeriesCache(slug)
            assert.are.equal("Golden Son", c.books[2].title)
            assert.are.equal(1, #c.books[2].characters)
        end)

        it("allows explicit reassignments and pruning when is_explicit is true or nil", function()
            local new_book_1 = {
                title = "Red Rising (Special Edition)",
                author = "Pierce Brown",
                characters = {},
            }
            -- When is_explicit is true, intentional overwrite of slot 1 is allowed
            local ok = manager:syncBookToSeriesCache(slug, 1, new_book_1, "/books/Red Rising Special.epub", true)
            assert.is_true(ok)

            local c = manager:loadSeriesCache(slug)
            assert.are.equal("Red Rising (Special Edition)", c.books[1].title)
        end)
    end)
    describe("fractional series indices", function()
        -- e.g. The Wandering Inn: 1, 1.5, 2, 2.5, 3, ...
        local series_info = { name = "The Wandering Inn", index = 2.5, slug = "the_wandering_inn" }

        after_each(function()
            package.loaded["bookinfomanager"] = nil
        end)

        it("formats whole and fractional indices", function()
            assert.are.equal("3", SeriesManager.formatIndex(3))
            assert.are.equal("2.5", SeriesManager.formatIndex(2.5))
            assert.are.equal("5.33", SeriesManager.formatIndex(5.33))
        end)

        it("lists whole-numbered books before an index", function()
            assert.are.same({ 1, 2, 3 }, SeriesManager.wholeIndicesBefore(4))
            assert.are.same({ 1, 2 }, SeriesManager.wholeIndicesBefore(2.5))
            assert.are.same({}, SeriesManager.wholeIndicesBefore(1))
        end)

        it("lists cached indices before an index in sorted order", function()
            local books = { [2.5] = {}, [1] = {}, [2] = {}, [1.5] = {}, [3] = {} }
            assert.are.same({ 1, 1.5, 2 }, SeriesManager.priorIndicesIn(books, 2.5))
        end)

        it("keeps fractional prior books from the AI and drops the current and later ones", function()
            local mock_ai = {
                createPrompt = function() return {} end,
                executeUnifiedRequest = function()
                    return {
                        prior_books = {
                            { index = 1, title = "The Wandering Inn" },
                            { index = 1.5, title = "No Killing Goblins" },
                            { index = "2", title = "Fae and Fare" },
                            { index = 2.5, title = "Immortal Games" },
                            { index = 3, title = "Flowers of Esthelm" },
                        }
                    }
                end
            }
            local list = manager:getPriorBookList(series_info, "pirateaba", mock_ai)
            assert.are.equal(3, #list)
            assert.are.equal(1, list[1].index)
            assert.are.equal(1.5, list[2].index)
            assert.are.equal("No Killing Goblins", list[2].title)
            assert.are.equal(2, list[3].index)
            assert.are.equal("pirateaba", list[3].author)
        end)

        it("prefers books found on the device over the AI's numbering", function()
            manager.scanFolderForEpubs = function()
                return {
                    { path = "/books/01.epub", title = "The Wandering Inn", series = "The Wandering Inn", series_index = 1 },
                    { path = "/books/1.5.epub", title = "No Killing Goblins", series = "The Wandering Inn", series_index = 1.5 },
                    { path = "/books/2.5.epub", title = "Immortal Games", series = "The Wandering Inn", series_index = 2.5 },
                    { path = "/books/other.epub", title = "Other", series = "Another Series", series_index = 1 },
                }
            end
            local mock_ai = {
                createPrompt = function() return {} end,
                executeUnifiedRequest = function()
                    return {
                        prior_books = {
                            -- AI numbers the novella differently; must not duplicate it
                            { index = 2, title = "No Killing Goblins" },
                            { index = 1, title = "Volume 1" },
                        }
                    }
                end
            }
            local list = manager:getPriorBookList(series_info, "pirateaba", mock_ai, "/books/2.5.epub")
            assert.are.equal(2, #list)
            assert.are.equal("The Wandering Inn", list[1].title)
            assert.are.equal("/books/01.epub", list[1].path)
            assert.are.equal(1.5, list[2].index)
            assert.are.equal("No Killing Goblins", list[2].title)
        end)

        it("generates whole-numbered placeholders below a fractional index", function()
            local list = manager:getPriorBookList(series_info, "pirateaba", nil)
            assert.are.equal(2, #list)
            assert.are.equal(1, list[1].index)
            assert.are.equal(2, list[2].index)
        end)

        it("expects whole-numbered, cached, and on-device prior indices", function()
            manager.scanFolderForEpubs = function()
                return {
                    { path = "/books/1.5.epub", title = "No Killing Goblins", series = "The Wandering Inn", series_index = 1.5 },
                }
            end
            local books = { [1] = {}, [0.5] = {} }
            assert.are.same({ 0.5, 1, 1.5, 2 }, manager:getExpectedPriorIndices(series_info, books, "/books/2.5.epub"))
        end)

        it("reads series metadata from BookInfoManager for books without a sidecar", function()
            package.loaded["bookinfomanager"] = {
                getBookInfo = function(_, path)
                    if path == "/books/1.5.epub" then
                        return { title = "No Killing Goblins", authors = "pirateaba", series = "The Wandering Inn", series_index = 1.5 }
                    end
                end
            }
            local meta = manager:readBookMetadata("/books/1.5.epub")
            assert.are.equal("No Killing Goblins", meta.title)
            assert.are.equal("The Wandering Inn", meta.series)
            assert.are.equal(1.5, meta.series_index)
        end)

        it("keeps fractional indices in series prompts", function()
            local ai_helper = require("xray_aihelper")
            ai_helper.prompts = require("prompts/en")

            local list_prompt = ai_helper:createPrompt(nil, "pirateaba", { series_name = "The Wandering Inn", index = 2.5 }, "prior_book_list")
            assert.is_not_nil(list_prompt:find("Current Book Index: 2.5", 1, true))
            assert.is_not_nil(list_prompt:find("books 1 through 2", 1, true))
            assert.is_not_nil(list_prompt:find("lower than 2.5", 1, true))

            local summary_prompt = ai_helper:createPrompt("No Killing Goblins", "pirateaba", { series_name = "The Wandering Inn", index = 1.5 }, "series_book_summary")
            assert.is_not_nil(summary_prompt:find("TARGET BOOK INDEX: 1.5", 1, true))
            assert.is_not_nil(summary_prompt:find("(Book Index 1.5)", 1, true))

            local whole_prompt = ai_helper:createPrompt(nil, "Brandon Sanderson", { series_name = "Mistborn", index = 3 }, "prior_book_list")
            assert.is_not_nil(whole_prompt:find("Current Book Index: 3", 1, true))
            assert.is_not_nil(whole_prompt:find("books 1 through 2", 1, true))
            assert.is_nil(whole_prompt:find("lower than", 1, true))
        end)

        it("merges every cached prior book below a fractional index", function()
            local plugin = createMockPlugin()
            for k, v in pairs(xray_fetch) do
                plugin[k] = v
            end
            plugin.cache_manager = {
                saveCache = function() return true end,
                asyncSaveCache = function() return true end,
                loadCache = function() return {} end
            }
            plugin.characters, plugin.locations, plugin.terms, plugin.timeline = {}, {}, {}, {}

            local cache_data = {
                books = {
                    [1] = { title = "The Wandering Inn", characters = { { name = "Erin" } }, timeline = { { event = "Erin arrives" } } },
                    [1.5] = { title = "No Killing Goblins", characters = { { name = "Rags" } }, timeline = { { event = "Goblins attack" } } },
                    [2] = { title = "Fae and Fare", characters = { { name = "Ryoka" } } },
                    [3] = { title = "Flowers of Esthelm", characters = { { name = "Spoiler" } } },
                }
            }
            plugin:mergeSeriesContext(cache_data, series_info)

            local names = {}
            for _, c in ipairs(plugin.characters) do names[c.name] = c.source_book end
            assert.are.equal(1, names["Erin"])
            assert.are.equal(1.5, names["Rags"])
            assert.are.equal(2, names["Ryoka"])
            assert.is_nil(names["Spoiler"])

            local labels = {}
            for _, ev in ipairs(plugin.timeline) do labels[ev.chapter] = true end
            assert.is_true(labels["[Book 1.5: No Killing Goblins]"])
        end)
    end)
    describe("fetchSeriesContext", function()
        local original_network

        before_each(function()
            original_network = package.loaded["ui/network/manager"]
            package.loaded["ui/network/manager"] = {
                isOnline = function() return true end,
                runWhenOnline = function(_, fn) fn() end,
            }
        end)

        after_each(function()
            package.loaded["ui/network/manager"] = original_network
        end)

        it("keeps books already fetched when a later book fails", function()
            local plugin = createMockPlugin()
            for k, v in pairs(xray_fetch) do
                plugin[k] = v
            end
            plugin.series_manager = manager
            plugin.cache_manager = {
                saveCache = function() return true end,
                asyncSaveCache = function() return true end,
                loadCache = function() return {} end
            }
            plugin.ui.document.getProps = function()
                return { title = "Proven Guilty", authors = "Jim Butcher", series = "The Dresden Files", series_index = 4 }
            end
            local merged = false
            plugin.mergeSeriesContext = function() merged = true end
            plugin.ai_helper = {
                settings = { series_context_enabled = true },
                setTrapWidget = function() end,
                resetTrapWidget = function() end,
                createPrompt = function(_, title, _, context, section)
                    return { section = section, title = title }
                end,
                executeUnifiedRequest = function(_, prompt)
                    if prompt.section == "prior_book_list" then
                        return { prior_books = {
                            { index = 1, title = "Storm Front" },
                            { index = 2, title = "Fool Moon" },
                            { index = 3, title = "Grave Peril" },
                        } }
                    end
                    if prompt.title == "Grave Peril" then
                        return nil, "error_api", "Parse failed: Failed to parse JSON"
                    end
                    return { characters = { { name = "Harry Dresden" } }, timeline = {} }
                end
            }

            plugin:fetchSeriesContext(true)

            local cache = manager:loadSeriesCache("the_dresden_files")
            assert.is_not_nil(cache)
            assert.are.equal("Storm Front", cache.books[1].title)
            assert.are.equal("Fool Moon", cache.books[2].title)
            assert.is_nil(cache.books[3])
            assert.is_false(merged)
        end)
    end)
end)
