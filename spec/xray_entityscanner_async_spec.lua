-- spec/xray_entityscanner_async_spec.lua
require("spec/spec_helper")

describe("xray_entityscanner async background scanning & overlay", function()
    local orig_ffiutil
    local fake_ffiutil
    local written_chunks
    local pipe_written
    local fail_fork
    local is_done_flag
    local child_ran
    local terminated_pid
    local read_calls
    local plugin
    local original_scheduleIn
    local scheduled_tasks
    local mock_time

    local function advance_time(seconds)
        local end_time = mock_time + seconds
        while true do
            local next_idx = nil
            local next_target = nil
            for i, task in ipairs(scheduled_tasks) do
                if task.target <= end_time and (not next_target or task.target < next_target) then
                    next_idx = i
                    next_target = task.target
                end
            end
            if not next_idx then break end
            local task = table.remove(scheduled_tasks, next_idx)
            mock_time = task.target
            task.fn()
        end
        mock_time = end_time
    end

    before_each(function()
        orig_ffiutil = package.loaded["ffi/util"]
        _G.XRAY_DISABLE_ENTITY_SUBPROCESS = false
        written_chunks = {}
        pipe_written = ""
        fail_fork = false
        is_done_flag = true
        child_ran = false
        terminated_pid = nil
        read_calls = 0
        scheduled_tasks = {}
        mock_time = 1000

        local UIManager = require("ui/uimanager")
        original_scheduleIn = UIManager.scheduleIn
        UIManager.scheduleIn = function(_, delay, callback)
            local fn = type(delay) == "function" and delay or callback
            local wait = type(delay) == "number" and delay or 0
            table.insert(scheduled_tasks, { target = mock_time + wait, fn = fn })
        end

        fake_ffiutil = {
            runInSubProcess = function(child_fn, with_pipe)
                if fail_fork then
                    return false, "fork failed: out of memory"
                end
                child_ran = true
                child_fn(8888, "fake_write_fd")
                return 8888, "fake_read_fd"
            end,
            writeToFD = function(fd, data, close_after)
                table.insert(written_chunks, data)
                pipe_written = pipe_written .. data
            end,
            isSubProcessDone = function(pid)
                return is_done_flag
            end,
            terminateSubProcess = function(pid)
                terminated_pid = pid
            end,
            readFromFD = function(fd, size)
                return ""
            end,
            readAllFromFD = function(fd)
                read_calls = read_calls + 1
                return pipe_written
            end,
            getNonBlockingReadSize = function(fd)
                return #pipe_written
            end,
        }
        package.loaded["ffi/util"] = fake_ffiutil

        pcall(os.execute, "mkdir -p /tmp/test_entity_book.epub.sdr")
        pcall(os.remove, "/tmp/test_entity_book.epub.sdr/xray_entity_cache.cache")

        plugin = createMockPlugin()
        local xray_entityscanner = require("xray_entityscanner")
        for k, v in pairs(xray_entityscanner) do
            plugin[k] = v
        end
        plugin.path = "xray.koplugin"
        plugin.ui.document.file = "/tmp/test_entity_book.epub"

        plugin.ai_helper = {
            settings = {
                entity_footnotes_enabled = true,
                entity_cat_characters = true,
                entity_cat_historical_figures = true,
                entity_cat_locations = true,
                entity_cat_terms = true,
                entity_mention_mode = "all",
                entity_popup_style = "footnote",
            },
            saveSettings = function(self_ah, new_st)
                for k, v in pairs(new_st) do
                    self_ah.settings[k] = v
                end
            end
        }

        plugin.characters = {
            { name = "Sherlock Holmes", aliases = { "Holmes", "Consulting Detective" }, description = "A brilliant detective." }
        }
        plugin.locations = {
            { name = "221B Baker Street", description = "The famous London residence." }
        }
        plugin.terms = {
            { name = "Scotland Yard", definition = "The headquarters of London police." }
        }
        plugin.historical_figures = {}

        plugin.ui.document.findAllText = function(self_doc, pat, regex, contextWords, maxResults, returnXPointers, flag)
            if pat:find("Holmes") or pat:find("Sherlock") then
                return {
                    { matched_text = "Sherlock Holmes", text = "Sherlock Holmes", start = "xp_start_1", start0 = "xp_start_1", ["end"] = "xp_end_1" },
                    { matched_text = "Holmes", text = "Holmes", start = "xp_start_2", start0 = "xp_start_2", ["end"] = "xp_end_2" },
                }
            end
            return {}
        end

        plugin.ui.document.getPageFromXPointer = function(self_doc, xp)
            if xp == "xp_start_1" or xp == "xp_end_1" then return 1 end
            if xp == "xp_start_2" or xp == "xp_end_2" then return 2 end
            return 1
        end

        plugin.ui.document.getScreenBoxesFromPositions = function(self_doc, start_xp, end_xp, flag)
            if start_xp == "xp_start_1" then
                return { { x = 100, y = 200, w = 120, h = 20 } }
            elseif start_xp == "xp_start_2" then
                return { { x = 100, y = 250, w = 60, h = 20 } }
            end
            return {}
        end
    end)

    after_each(function()
        _G.XRAY_DISABLE_ENTITY_SUBPROCESS = true
        package.loaded["ffi/util"] = orig_ffiutil
        local UIManager = require("ui/uimanager")
        UIManager.scheduleIn = original_scheduleIn
        pcall(os.remove, "/tmp/test_entity_book.epub.sdr/xray_entity_cache.cache")
    end)

    it("verifies SRELL regex character escaping does not escape '-' or '%'", function()
        -- Directly test regex escaping behavior
        local raw_term = "Twenty-One% Special (Class-A)"
        local esc = raw_term:gsub("([%^%$%.%*%+%?%(%)%[%]%{%}|\\])", "\\%1"):gsub("%s+", "\\s+")
        -- '-' and '%' must remain unescaped so SRELL doesn't throw error_escape (102)
        assert.is_nil(esc:find([[\-]], 1, true))
        assert.is_nil(esc:find([[\%]], 1, true))
        assert.is_not_nil(esc:find([[\(]], 1, true))
        assert.is_not_nil(esc:find([[\)]], 1, true))
    end)

    it("runs background entity scan via subprocess and writes atomic v3 cache", function()
        plugin:scanBookForEntities(true)
        assert.is_true(child_ran)

        -- Advance scheduled poll to process completion
        advance_time(1)

        assert.is_not_nil(plugin.entity_xp_matches)
        assert.are.equal(2, #plugin.entity_xp_matches)

        -- Verify page buckets populated directly from background scan
        assert.is_not_nil(plugin.entity_matches_by_page[1])
        assert.are.equal(1, #plugin.entity_matches_by_page[1])
        assert.are.equal("Sherlock Holmes", plugin.entity_matches_by_page[1][1].entity_name)

        assert.is_not_nil(plugin.entity_matches_by_page[2])
        assert.are.equal(1, #plugin.entity_matches_by_page[2])
        assert.are.equal("Holmes", plugin.entity_matches_by_page[2][1].matched_text)

        -- Verify cache was saved to disk
        local f = io.open("/tmp/test_entity_book.epub.sdr/xray_entity_cache.cache", "r")
        assert.is_not_nil(f)
        local sig = f:read("*l")
        assert.is_true(sig:find("^v[34567]|") ~= nil)
        f:close()
    end)

    it("invalidates cache when entity list or categories change", function()
        -- First run and save
        plugin:scanBookForEntities(true)
        advance_time(1)
        assert.are.equal(2, #plugin.entity_xp_matches)

        -- Add new character to trigger signature change
        table.insert(plugin.characters, { name = "John Watson", description = "The loyal doctor." })

        local loaded = plugin:loadEntityCache("/tmp/test_entity_book.epub.sdr")
        -- Should return false because signature changed
        assert.is_false(loaded)
    end)

    it("handles watchdog timeout by cancelling subprocess", function()
        is_done_flag = false -- simulate hung child
        plugin:scanBookForEntities(true)
        assert.are.equal(8888, plugin._entity_scan_pid)

        -- Advance time past timeout
        plugin._entity_scan_started_at = os.time() - 400
        -- Manually invoke the poll callback
        plugin._entity_scan_poll_fn()

        assert.are.equal(8888, terminated_pid)
        assert.is_nil(plugin._entity_scan_pid)
    end)

    it("cancels running scan when document is closed", function()
        is_done_flag = false
        plugin:scanBookForEntities(true)
        assert.are.equal(8888, plugin._entity_scan_pid)

        plugin:_cancelEntityScanChild("document closing")
        assert.are.equal(8888, terminated_pid)
        assert.is_nil(plugin._entity_scan_pid)
    end)

    it("executes in-process fallback when FFI subprocess is disabled", function()
        _G.XRAY_DISABLE_ENTITY_SUBPROCESS = true
        plugin:scanBookForEntities(true)

        -- Advance event loop coroutine steps
        advance_time(0.1)
        advance_time(0.1)

        assert.is_not_nil(plugin.entity_xp_matches)
        assert.are.equal(2, #plugin.entity_xp_matches)
    end)

    it("deduplicates mentions per page when entity_mention_mode is 'first'", function()
        -- Setup 2 mentions of the same character on page 1
        plugin.entity_xp_matches = {
            { start_xp = "xp_start_1", end_xp = "xp_end_1", matched_text = "Sherlock Holmes", entity_name = "Sherlock Holmes", category = "character", page = 1 },
            { start_xp = "xp_start_1", end_xp = "xp_end_1", matched_text = "Holmes", entity_name = "Sherlock Holmes", category = "character", page = 1 },
        }
        plugin.entity_matches_by_page = {
            [1] = plugin.entity_xp_matches
        }
        plugin.last_pageno = 1

        plugin.ai_helper.settings.entity_mention_mode = "first"
        plugin:_resolveEntityHighlightBoxes()

        -- Only 1 box should be kept for Sherlock Holmes on page 1
        assert.are.equal(1, #plugin.entity_boxes)

        -- In "all" mode, both mentions are retained
        plugin.ai_helper.settings.entity_mention_mode = "all"
        plugin._entity_box_cache_sig = nil
        plugin:_resolveEntityHighlightBoxes()
        assert.are.equal(2, #plugin.entity_boxes)
    end)

    it("filters out entities that are not visible at current position (spoiler shield)", function()
        plugin.entity_xp_matches = {
            { start_xp = "xp_start_1", end_xp = "xp_end_1", matched_text = "Sherlock Holmes", entity_name = "Sherlock Holmes", category = "character", page = 1 },
        }
        plugin.entity_matches_by_page = { [1] = plugin.entity_xp_matches }
        plugin.last_pageno = 1

        plugin.isEntityVisibleAtCurrentPosition = function(self_pl, ent)
            return false -- hidden behind spoiler gate
        end

        plugin:_resolveEntityHighlightBoxes()
        assert.are.equal(0, #plugin.entity_boxes)

        plugin.isEntityVisibleAtCurrentPosition = function(self_pl, ent)
            return true -- unlocked
        end
        plugin._entity_box_cache_sig = nil
        plugin:_resolveEntityHighlightBoxes()
        assert.are.equal(1, #plugin.entity_boxes)
    end)

    it("routes tap to handleLookup in footnote mode and EntityTooltip in tooltip mode", function()
        plugin.entity_boxes = {
            { x = 100, y = 200, w = 120, h = 20, entity_name = "Sherlock Holmes", category = "character", matched_text = "Sherlock Holmes" }
        }

        local lookup_called = false
        plugin.lookup_manager = {
            handleLookup = function(self_lm, name)
                lookup_called = (name == "Sherlock Holmes")
            end
        }

        -- Tap inside box (105, 205)
        local handled = plugin:_handleEntityTap({ pos = { x = 105, y = 205 } })
        assert.is_true(handled)
        assert.is_true(lookup_called)

        -- Tap outside box (50, 50)
        local missed = plugin:_handleEntityTap({ pos = { x = 50, y = 50 } })
        assert.is_false(missed)
    end)

    it("generates uppercase and titlecase search variants for entity matching (e.g. HOUSTON)", function()
        plugin.locations = {
            { name = "Houston", description = "Mission Control" }
        }
        plugin.terms = {
            { name = "Atmospheric Regulator", aliases = { "regulator" }, definition = "Life support system" }
        }

        local terms, lookup = plugin._collectEntityTerms(plugin, {
            entity_cat_characters = true,
            entity_cat_historical_figures = true,
            entity_cat_locations = true,
            entity_cat_terms = true,
        })

        local terms_set = {}
        for _, t in ipairs(terms) do terms_set[t] = true end

        -- Capitalized location generates both Title Case and ALL-CAPS
        assert.is_true(terms_set["Houston"])
        assert.is_true(terms_set["HOUSTON"])

        -- Lowercase alias generates lowercase, Title Case, and ALL-CAPS
        assert.is_true(terms_set["regulator"])
        assert.is_true(terms_set["Regulator"])
        assert.is_true(terms_set["REGULATOR"])

        -- Lookup correctly maps lowercase keys to canonical entities
        assert.is_not_nil(lookup["houston"])
        assert.are.equal("Houston", lookup["houston"].canonical)
        assert.are.equal("location", lookup["houston"].category)

        assert.is_not_nil(lookup["regulator"])
        assert.are.equal("Atmospheric Regulator", lookup["regulator"].canonical)
    end)

    it("addEntityToUnderlines incrementally updates matches and underlines when enabled", function()
        plugin.ai_helper = {
            settings = {
                entity_footnotes_enabled = true,
                entity_cat_characters = true,
                entity_cat_locations = true,
            }
        }
        plugin.entity_xp_matches = {
            { start_xp = "/1/1", end_xp = "/1/2", matched_text = "Sherlock Holmes", entity_name = "Sherlock Holmes", category = "character", page = 1 }
        }
        plugin.entity_matches_by_page = {
            [1] = { plugin.entity_xp_matches[1] }
        }

        local new_loc = { name = "Houston", description = "NASA Mission Control" }
        table.insert(plugin.locations, new_loc)

        -- Mock doc:findAllText to return a hit for Houston
        local orig_findAllText = plugin.ui.document.findAllText
        plugin.ui.document.findAllText = function(self_doc, pattern, case_ins, nb_ctx, max_h, is_regex)
            if pattern:find("Houston") or pattern:find("HOUSTON") then
                return {
                    { start = "/2/1", ["end"] = "/2/2", matched_text = "HOUSTON" }
                }
            end
            return {}
        end

        local saved_cache = false
        plugin.saveEntityCache = function()
            saved_cache = true
            return true
        end

        plugin:addEntityToUnderlines(new_loc, "location")

        -- Check that HOUSTON was added to entity_xp_matches
        assert.are.equal(2, #plugin.entity_xp_matches)
        assert.are.equal("HOUSTON", plugin.entity_xp_matches[2].matched_text)
        assert.are.equal("Houston", plugin.entity_xp_matches[2].entity_name)
        assert.are.equal("location", plugin.entity_xp_matches[2].category)

        -- Check that page buckets were updated
        assert.is_not_nil(plugin.entity_matches_by_page[1])
        assert.are.equal(2, #plugin.entity_matches_by_page[1])

        -- Check that cache was saved
        assert.is_true(saved_cache)

        -- Restore
        plugin.ui.document.findAllText = orig_findAllText
    end)

    it("addEntityToUnderlines does nothing when entity_footnotes_enabled is false", function()
        plugin.ai_helper = {
            settings = {
                entity_footnotes_enabled = false,
            }
        }
        plugin.entity_xp_matches = {
            { start_xp = "/1/1", end_xp = "/1/2", matched_text = "Sherlock Holmes", entity_name = "Sherlock Holmes", category = "character", page = 1 }
        }
        local new_loc = { name = "Houston", description = "NASA Mission Control" }
        plugin:addEntityToUnderlines(new_loc, "location")
        assert.are.equal(1, #plugin.entity_xp_matches)
    end)

    describe("Sub-name derivation & deduplication", function()
        it("derives unambiguous person sub-names and rejects ambiguous shared surnames", function()
            plugin.characters = {
                { name = "Martha Cratchit" },
                { name = "Bob Cratchit" },
                { name = "Master Peter Cratchit" },
            }
            plugin.historical_figures = {}
            plugin.locations = {}
            plugin.terms = {}
            local settings = { entity_cat_characters = true }

            local terms, lookup = plugin._collectEntityTerms(plugin, settings)

            -- Martha and Peter should be derived because only one entity claims each
            assert.is_not_nil(lookup["martha"])
            assert.are.equal("Martha Cratchit", lookup["martha"].canonical)
            assert.is_not_nil(lookup["peter"])
            assert.are.equal("Master Peter Cratchit", lookup["peter"].canonical)
            assert.is_not_nil(lookup["master peter"])
            assert.are.equal("Master Peter Cratchit", lookup["master peter"].canonical)

            -- Cratchit is claimed by 3 entities, so it MUST NOT be registered as a derived term!
            assert.is_nil(lookup["cratchit"])
        end)

        it("deduplicates overlapping character intervals on the same text node keeping longest match", function()
            local hits = {
                {
                    start_xp = "/body/div/p[1]/text().0",
                    end_xp = "/body/div/p[1]/text().12",
                    matched_text = "Bob Cratchit",
                    entity_name = "Bob Cratchit",
                },
                {
                    start_xp = "/body/div/p[1]/text().0",
                    end_xp = "/body/div/p[1]/text().3",
                    matched_text = "Bob",
                    entity_name = "Bob Cratchit",
                },
                {
                    start_xp = "/body/div/p[1]/text().20",
                    end_xp = "/body/div/p[1]/text().26",
                    matched_text = "Martha",
                    entity_name = "Martha Cratchit",
                },
            }

            local deduped = plugin._deduplicateEntityHits(hits)
            assert.are.equal(2, #deduped)
            local texts = {}
            for _, h in ipairs(deduped) do
                table.insert(texts, h.matched_text)
            end
            table.sort(texts)
            assert.are.same({ "Bob Cratchit", "Martha" }, texts)
        end)

        it("_rebuildEntityPageBuckets updates page buckets when pagination changes", function()
            plugin.entity_xp_matches = {
                { start_xp = "/body/div/p[1]/text().0", end_xp = "/body/div/p[1]/text().10", matched_text = "Scrooge", page = 1 },
                { start_xp = "/body/div/p[2]/text().0", end_xp = "/body/div/p[2]/text().10", matched_text = "Martha", page = 1 },
            }
            plugin.ui = {
                document = {
                    file = "/test.epub",
                    getPageFromXPointer = function(doc, xp)
                        if xp:find("p%[2%]") then return 2 end
                        return 1
                    end,
                    getPageCount = function() return 2 end,
                    getDocumentRenderingHash = function() return "hash_new" end,
                }
            }

            plugin:_rebuildEntityPageBuckets()

            assert.is_not_nil(plugin.entity_matches_by_page[1])
            assert.are.equal(1, #plugin.entity_matches_by_page[1])
            assert.are.equal("Scrooge", plugin.entity_matches_by_page[1][1].matched_text)

            assert.is_not_nil(plugin.entity_matches_by_page[2])
            assert.are.equal(1, #plugin.entity_matches_by_page[2])
            assert.are.equal("Martha", plugin.entity_matches_by_page[2][1].matched_text)
        end)

        it("skips generic single-word stopword/honorific person aliases like 'Spirit' and keeps 'Scrooge'", function()
            plugin.characters = {
                { name = "Ebenezer Scrooge", aliases = { "Scrooge" }, description = "Miser" },
                { name = "Ghost of Christmas Present", aliases = { "The Ghost of Christmas Present", "Spirit" }, description = "Spirit of Christmas" },
            }
            plugin.locations = {}
            plugin.terms = {}
            plugin.historical_figures = {}

            local _, lookup = plugin._collectEntityTerms(plugin, {
                entity_cat_characters = true,
                entity_cat_historical_figures = true,
                entity_cat_locations = true,
                entity_cat_terms = true,
            })

            assert.is_not_nil(lookup["scrooge"])
            assert.are.equal("Ebenezer Scrooge", lookup["scrooge"].canonical)
            assert.is_nil(lookup["spirit"])
        end)

        it("prefers history[1] before entity.description in showEntityFootnote when resolveDescriptionForPage returns '---'", function()
            local UIManager = require("ui/uimanager")
            local shown_widget = nil
            local orig_show = UIManager.show
            UIManager.show = function(_, w) shown_widget = w end

            plugin.ai_helper.settings.entity_popup_style = "tooltip"
            plugin.characters = {
                {
                    name = "Ebenezer Scrooge",
                    description = "Stave 3 late spoiler description",
                    history = {
                        { page = 7, description = "Stave 1 early description" },
                        { page = 106, description = "Stave 3 late spoiler description" },
                    },
                }
            }
            plugin.resolveDescriptionForPage = function() return "---" end
            plugin:showEntityFootnote({ entity_name = "Ebenezer Scrooge", category = "character", x = 10, y = 10, w = 50, h = 20 })

            UIManager.show = orig_show
            assert.is_not_nil(shown_widget)
            assert.are.equal("Stave 1 early description", shown_widget.description_text)
        end)
    end)

    describe("Entity scan lifecycle & opt-in defaults", function()
        it("does not permanently block lazy scan when characters are initially empty", function()
            plugin.ai_helper = {
                settings = {
                    entity_footnotes_enabled = true,
                }
            }
            plugin.characters = {}
            plugin.historical_figures = {}
            plugin.locations = {}
            plugin.terms = {}
            plugin._entity_scan_attempted = nil

            plugin:scanBookForEntities()
            assert.is_nil(plugin._entity_scan_attempted)

            -- Now populate characters and verify scanBookForEntities marks attempted and proceeds
            plugin.characters = { { name = "Nick Carraway" } }
            plugin.loadEntityCache = function() return true end
            plugin:scanBookForEntities()
            assert.is_true(plugin._entity_scan_attempted)
        end)

        it("skips scanning and clears underlines when entity_footnotes_enabled is nil (off by default)", function()
            plugin.ai_helper = { settings = {} }
            plugin.characters = { { name = "Nick Carraway" } }
            plugin.entity_xp_matches = { { start_xp = "/1/1", end_xp = "/1/2", matched_text = "Nick", entity_name = "Nick Carraway", category = "character", page = 1 } }
            plugin._entity_scan_attempted = nil

            plugin:scanBookForEntities()
            assert.is_nil(plugin._entity_scan_attempted)
            assert.is_nil(plugin.entity_xp_matches)
        end)

        it("triggers scanBookForEntities after sequential chapter scan completes with batches", function()
            local UIManager = require("ui/uimanager")
            local fetch_mod = require("xray_fetch")
            local ChapterAnalyzer = require("xray_chapteranalyzer")
            local scheduled = {}
            local orig_schedule = UIManager.scheduleIn
            local orig_get_text = ChapterAnalyzer.getSingleChapterText
            UIManager.scheduleIn = function(_, delay, fn)
                table.insert(scheduled, { delay = delay, fn = fn })
                return fn
            end
            ChapterAnalyzer.getSingleChapterText = function()
                return string.rep("Nick went home and talked with his friends. ", 5)
            end

            local scan_called = false
            local mock_plugin = {
                destroyed = false,
                ui = {
                    document = { getPageCount = function() return 10 end },
                    getCurrentPage = function() return 1 end,
                },
                ai_helper = {
                    settings = { entity_footnotes_enabled = true },
                    buildChapterDeltaPrompt = function() return "prompt" end,
                    buildBatchChapterDeltaPrompt = function() return "prompt" end,
                    buildComprehensiveRequest = function() return { url = "x" } end,
                    makeRequestAsync = function() return 123 end,
                    checkAsyncResult = function()
                        return {
                            new_characters = { { name = "Nick", description = "Main character" } },
                            timeline_event = { chapter = "Ch 1", event = "Intro" }
                        }
                    end,
                },
                mergeSequentialChapterDelta = fetch_mod.mergeSequentialChapterDelta,
                checkpointHorizonScan = function() end,
                runPostFetchDuplicateCheck = function() end,
                buildCompactEntityManifest = function() return "" end,
                scanBookForEntities = function() scan_called = true end,
                log = function() end,
                chapters_fetched = {},
            }

            fetch_mod.queueSequentialChapterScan(mock_plugin, {
                { toc_index = 1, title = "Ch 1", page = 1, end_page = 5, unique_id = "ch1" }
            }, true)

            -- Drive the scheduled callbacks (pollResult -> 3s cooldown -> processNext -> finishScan -> 0.5s scanBookForEntities)
            local safety = 0
            while #scheduled > 0 and safety < 20 do
                safety = safety + 1
                local item = table.remove(scheduled, 1)
                item.fn()
            end

            UIManager.scheduleIn = orig_schedule
            ChapterAnalyzer.getSingleChapterText = orig_get_text
            assert.is_true(scan_called)
        end)
    end)

    describe("Bionic Reading, Guided Dots, and Kobo guards", function()
        local Device = require("device")
        local orig_is_kobo

        before_each(function()
            orig_is_kobo = Device.isKobo
        end)

        after_each(function()
            Device.isKobo = orig_is_kobo
        end)

        it("uses plain 5-arg findAllText (no search_flags=1) and normalizes Guided Dots in _computeEntityMatches", function()
            plugin.characters = {
                { name = "Bob Cratchit", aliases = {}, description = "Clerk." }
            }
            plugin.locations = {}
            plugin.terms = {}
            plugin.historical_figures = {}

            local seen_flags = {}
            local find_calls = 0
            plugin.ui.document.findAllText = function(self_doc, pat, case_ins, ctx, max_hits, is_regex, search_flags)
                find_calls = find_calls + 1
                seen_flags[find_calls] = search_flags
                return {
                    {
                        matched_text = "Bob\194\183Cratchit",
                        text = "Bob\194\183Cratchit",
                        start = "xp_b1",
                        start0 = "xp_b1",
                        ["end"] = "xp_b2",
                    }
                }
            end

            local matches = plugin:_computeEntityMatches(plugin.ai_helper.settings)
            assert.is_true(find_calls >= 1)
            assert.is_nil(seen_flags[1])
            assert.are.equal(1, #matches)
            assert.are.equal("Bob Cratchit", matches[1].matched_text)
            assert.are.equal("Bob Cratchit", matches[1].entity_name)
        end)

        it("accepts compatible v6 and legacy bionic-suffixed v7 caches without invalidating underlines", function()
            local xray_utils = require("xray_utils")
            local orig_fp = xray_utils.getDocumentDomFingerprint
            xray_utils.getDocumentDomFingerprint = function() return "1234:5678" end

            plugin.characters = { { name = "Sherlock Holmes", description = "Detective." } }
            plugin.historical_figures = {}
            plugin.locations = {}
            plugin.terms = {}

            local cache_dir = "/tmp/test_xray_legacy_cache_" .. tostring(os.time())
            os.execute("mkdir -p " .. cache_dir)
            local legacy_sig = "v6|true|true|true|true|Sherlock Holmes||||1234:5678:b0"
            local ok_save = plugin:saveEntityCache(cache_dir, {
                {
                    start_xp = "xp_s1",
                    end_xp = "xp_e1",
                    matched_text = "Sherlock Holmes",
                    category = "character",
                    entity_name = "Sherlock Holmes",
                    page = 1,
                }
            }, "legacy_test", legacy_sig)
            assert.is_true(ok_save)

            plugin.entity_xp_matches = nil
            local loaded = plugin:loadEntityCache(cache_dir)
            assert.is_true(loaded)
            assert.is_true(plugin._entity_cache_needs_refresh)
            assert.are.equal(1, #plugin.entity_xp_matches)
            assert.are.equal("Sherlock Holmes", plugin.entity_xp_matches[1].entity_name)

            os.execute("rm -rf " .. cache_dir)
            xray_utils.getDocumentDomFingerprint = orig_fp
        end)

        it("does not run in-process fallback when auto-scan subprocess fails", function()
            local inproc_called = false
            local orig_inproc = plugin._runEntityScanInProcess
            plugin._runEntityScanInProcess = function()
                inproc_called = true
            end

            plugin._entity_scan_fallback_used = false
            plugin._entity_auto_retry_used = false
            plugin:_onEntityScanFinished("/tmp/nonexistent_dir", false, false)

            assert.is_false(inproc_called)
            assert.is_true(plugin._entity_auto_retry_used)

            plugin._runEntityScanInProcess = orig_inproc
        end)

        it("reschedules low-memory auto scan up to 3 times and stops", function()
            local xray_utils = require("xray_utils")
            local orig_low_mem = xray_utils.isLowMemory
            xray_utils.isLowMemory = function() return true end

            plugin.characters = { { name = "Sherlock Holmes", description = "Detective." } }
            plugin.ai_helper.settings.entity_footnotes_enabled = true
            plugin._entity_low_mem_retries = 0

            plugin:scanBookForEntities(false)
            assert.are.equal(1, plugin._entity_low_mem_retries)
            assert.is_false(plugin._entity_scan_attempted)

            plugin:scanBookForEntities(false)
            assert.are.equal(2, plugin._entity_low_mem_retries)

            plugin:scanBookForEntities(false)
            assert.are.equal(3, plugin._entity_low_mem_retries)

            plugin:scanBookForEntities(false)
            assert.are.equal(4, plugin._entity_low_mem_retries)
            assert.is_true(plugin._entity_scan_attempted)

            xray_utils.isLowMemory = orig_low_mem
        end)

        it("schedules sliced page-bucket rebuild instead of blocking _resolveEntityHighlightBoxes", function()
            local sync_rebuild_called = false
            local orig_sync = plugin._rebuildEntityPageBuckets
            plugin._rebuildEntityPageBuckets = function()
                sync_rebuild_called = true
            end

            plugin.entity_xp_matches = {
                { start_xp = "xp_1", end_xp = "xp_2", matched_text = "Sherlock Holmes", entity_name = "Sherlock Holmes", category = "character", page = 1 },
            }
            plugin.entity_matches_by_page = { [1] = plugin.entity_xp_matches }
            plugin._entity_bucket_page_count = 10
            plugin._entity_bucket_render_hash = "old_hash"
            plugin.ui.document.getPageCount = function() return 12 end
            plugin.ui.document.getDocumentRenderingHash = function() return "new_hash" end
            plugin.ui.document.getPageFromXPointer = function() return 2 end
            plugin._entity_box_cache_sig = nil

            plugin:_resolveEntityHighlightBoxes()
            assert.is_false(sync_rebuild_called)
            assert.is_true(plugin._entity_bucket_rebuilding)

            advance_time(0.1)
            assert.is_nil(plugin._entity_bucket_rebuilding)
            assert.are.equal(12, plugin._entity_bucket_page_count)
            assert.are.equal("new_hash", plugin._entity_bucket_render_hash)
            assert.is_not_nil(plugin.entity_matches_by_page[2])

            plugin._rebuildEntityPageBuckets = orig_sync
        end)

        it("suppresses shorter overlapping cross-node boxes with distinct XPointers while keeping shared-XPointer fixtures", function()
            plugin.characters = {
                { name = "Bob Cratchit", description = "Clerk." },
                { name = "Cratchit", description = "Family." },
                { name = "Sherlock Holmes", aliases = { "Holmes" }, description = "Detective." },
            }
            plugin.entity_xp_matches = {
                { start_xp = "xp_full_s", end_xp = "xp_full_e", matched_text = "Bob Cratchit", entity_name = "Bob Cratchit", category = "character", page = 1 },
                { start_xp = "xp_sub_s", end_xp = "xp_sub_e", matched_text = "Cratchit", entity_name = "Cratchit", category = "character", page = 1 },
            }
            plugin.entity_matches_by_page = { [1] = plugin.entity_xp_matches }
            plugin.last_pageno = 1
            plugin.ai_helper.settings.entity_mention_mode = "all"

            plugin.ui.document.getScreenBoxesFromPositions = function(self_doc, start_xp, end_xp)
                if start_xp == "xp_full_s" then
                    return { { x = 100, y = 200, w = 140, h = 24 } }
                elseif start_xp == "xp_sub_s" then
                    return { { x = 140, y = 200, w = 80, h = 24 } }
                elseif start_xp == "xp_shared_s" then
                    return { { x = 100, y = 300, w = 120, h = 24 } }
                end
                return {}
            end

            plugin._entity_box_cache_sig = nil
            plugin:_resolveEntityHighlightBoxes()
            assert.are.equal(1, #plugin.entity_boxes)
            assert.are.equal("Bob Cratchit", plugin.entity_boxes[1].entity_name)

            -- Shared identical XPointers are kept in "all" mode for compatibility
            plugin.entity_xp_matches = {
                { start_xp = "xp_shared_s", end_xp = "xp_shared_e", matched_text = "Sherlock Holmes", entity_name = "Sherlock Holmes", category = "character", page = 1 },
                { start_xp = "xp_shared_s", end_xp = "xp_shared_e", matched_text = "Holmes", entity_name = "Sherlock Holmes", category = "character", page = 1 },
            }
            plugin.entity_matches_by_page = { [1] = plugin.entity_xp_matches }
            plugin._entity_box_cache_sig = nil
            plugin:_resolveEntityHighlightBoxes()
            assert.are.equal(2, #plugin.entity_boxes)
        end)

        it("retains FFI subprocess support on Kobo in xray_entityscanner._getFFIUtil", function()
            Device.isKobo = function() return true end
            assert.is_not_nil(plugin._getFFIUtil())

            local callback_cleared = false
            plugin.ui.document.setCallback = function(_, fn)
                if fn == nil then callback_cleared = true end
            end

            plugin:scanBookForEntities(false)
            assert.is_true(child_ran)
            assert.is_true(callback_cleared)
        end)

        it("unschedules poll timer, drains pipe, and halts in-process coroutine on _cancelEntityScanChild", function()
            local UIManager = require("ui/uimanager")
            local orig_unschedule = UIManager.unschedule
            local unscheduled = {}
            UIManager.unschedule = function(_, fn)
                if fn then
                    unscheduled[fn] = true
                    for i = #scheduled_tasks, 1, -1 do
                        if scheduled_tasks[i].fn == fn then
                            table.remove(scheduled_tasks, i)
                        end
                    end
                end
            end

            is_done_flag = false
            plugin:scanBookForEntities(true)
            local poll_fn = plugin._entity_scan_poll_fn
            assert.is_not_nil(poll_fn)

            plugin:_cancelEntityScanChild("test cancel")
            assert.is_true(unscheduled[poll_fn] == true)
            assert.is_nil(plugin._entity_scan_poll_fn)
            assert.are.equal(8888, terminated_pid)

            -- Simulate killed child exiting and advance past reap(1s) to verify readAllFromFD drains pipe
            is_done_flag = true
            advance_time(1.5)
            assert.is_true(read_calls >= 1)

            -- Also verify in-process coroutine step is unscheduled and halted on cancel
            _G.XRAY_DISABLE_ENTITY_SUBPROCESS = true
            plugin._entity_scan_in_progress = true
            plugin:_runEntityScanInProcess("/tmp/test_entity_book.epub.sdr", plugin.ai_helper.settings, true)
            local step_fn = plugin._entity_inproc_step_fn
            assert.is_not_nil(step_fn)

            plugin:_cancelEntityScanChild("cancel inproc")
            assert.is_true(unscheduled[step_fn] == true)
            assert.is_nil(plugin._entity_inproc_step_fn)
            assert.is_nil(plugin._entity_scan_in_progress)

            UIManager.unschedule = orig_unschedule
        end)

        it("configures manual ProgressBarDialog with subtitle, progress_max=100, and safe dismiss_callback", function()
            local ProgressBarDialog = require("ui/widget/progressbardialog")
            local orig_new = ProgressBarDialog.new
            local captured_opts = nil
            local close_calls = 0

            ProgressBarDialog.new = function(cls, opts)
                captured_opts = opts
                local inst = orig_new(cls, opts)
                inst.close = function(d)
                    close_calls = close_calls + 1
                    if d.dismiss_callback then
                        d.dismiss_callback()
                        d.dismiss_callback = nil
                    end
                end
                return inst
            end

            plugin:scanBookForEntities(true)
            advance_time(1)

            assert.is_not_nil(captured_opts)
            assert.is_not_nil(captured_opts.subtitle)
            assert.are.equal(100, captured_opts.progress_max)
            assert.are.equal(1, close_calls)
            assert.is_nil(plugin.active_entity_scan_dialog)

            ProgressBarDialog.new = orig_new
        end)

        it("returns {} in _resolveEntityHighlightBoxes when getPageFromXPointer is supported and 3-page window is empty", function()
            plugin.entity_xp_matches = {
                { start_xp = "xp_p1", end_xp = "xp_p1e", matched_text = "Sherlock Holmes", entity_name = "Sherlock Holmes", category = "character", page = 1 },
            }
            plugin.entity_matches_by_page = {}
            plugin.last_pageno = 50
            plugin._entity_box_cache_sig = nil

            local box_calls = 0
            plugin.ui.document.getScreenBoxesFromPositions = function()
                box_calls = box_calls + 1
                return { { x = 1, y = 1, w = 10, h = 10 } }
            end

            plugin:_resolveEntityHighlightBoxes()
            assert.are.equal(0, box_calls)
            assert.are.equal(0, #plugin.entity_boxes)
        end)
    end)
end)
