-- xray_cachemanager_spec.lua
require("spec.spec_helper")
local cache_manager = require("xray_cachemanager"):new()

describe("xray_cachemanager", function()
    local test_book = "/tmp/test_book.epub"
    local test_cache = test_book .. ".sdr/xray_cache.lua"

    before_each(function()
        -- Ensure clean state
        os.execute("rm -rf /tmp/test_book.epub.sdr")
        os.execute("mkdir -p /tmp/test_book.epub.sdr")
    end)

    describe("getCachePath", function()
        it("returns correct sidecar path", function()
            local path = cache_manager:getCachePath(test_book)
            assert.are.equal(test_cache, path)
        end)
    end)

    describe("Serialization and Saving", function()
        it("saves and loads data correctly", function()
            local data = {
                characters = {
                    { name = "Alice", role = "Protagonist" }
                },
                last_fetch_page = 42
            }

            local success = cache_manager:saveCache(test_book, data)
            assert.is_true(success)

            local loaded = cache_manager:loadCache(test_book)
            assert.is_not_nil(loaded)
            assert.are.equal("Alice", loaded.characters[1].name)
            assert.are.equal(42, loaded.last_fetch_page)
            assert.are.equal("6.1", loaded.cache_version)
        end)

        it("loads legacy 6.0 cache data seamlessly without data loss", function()
            local f = io.open(test_cache, "w")
            f:write("-- X-Ray Cache v6.0\nreturn { cache_version = '6.0', last_fetch_page = 50, characters = { { name = 'Legacy Alice' } } }\n")
            f:close()

            local loaded = cache_manager:loadCache(test_book)
            assert.is_not_nil(loaded)
            assert.are.equal("6.0", loaded.cache_version)
            assert.are.equal("Legacy Alice", loaded.characters[1].name)
            assert.are.equal(50, loaded.last_fetch_page)
        end)

        it("saves and loads data correctly using asyncSaveCache fallback", function()
            local data = {
                characters = {
                    { name = "Bob", role = "Deuteragonist" }
                },
                last_fetch_page = 101
            }

            local done_called = false
            local success = cache_manager:asyncSaveCache(test_book, data, function(res)
                done_called = true
                assert.is_true(res)
            end)
            assert.is_true(success)
            assert.is_true(done_called)

            -- Allow any forked child process time to finish writing before reading
            os.execute("sleep 0.2")

            local loaded = cache_manager:loadCache(test_book)
            assert.is_not_nil(loaded)
            assert.are.equal("Bob", loaded.characters[1].name)
            assert.are.equal(101, loaded.last_fetch_page)
        end)

        it("handles circular references gracefully", function()
            local data = { name = "Alice" }
            data.self = data -- Circular reference

            local success = cache_manager:saveCache(test_book, data)
            assert.is_true(success)

            local loaded = cache_manager:loadCache(test_book)
            -- The circular reference is serialized as an empty table with a comment marker
            assert.is_table(loaded.self)
            assert.are.equal(0, #loaded.self)
        end)

        it("cancels active async saves cleanly", function()
            local cm = require("xray_cachemanager"):new()
            assert.is_table(cm._active_saves)
            cm:cancelAsyncSaves()
            assert.are.equal(0, #cm._active_saves)
        end)

        it("safely handles truncated or corrupted cache files with syntax error", function()
            -- Write a corrupted cache file that only has 'return ' (as from an interrupted save)
            local f = io.open(test_cache, "w")
            f:write("-- X-Ray Cache v6.0\n-- Generated: 2026-09-08 12:00:00\n\nreturn \n")
            f:close()

            local loaded = cache_manager:loadCache(test_book)
            assert.is_nil(loaded)
        end)

        it("performs atomic writes so temp files are cleaned up", function()
            local data = { characters = { { name = "Charlie" } } }
            local success = cache_manager:saveCache(test_book, data)
            assert.is_true(success)

            local tmp_file = test_cache .. ".tmp"
            local f_tmp = io.open(tmp_file, "r")
            assert.is_nil(f_tmp) -- tmp file should not linger after successful save

            local loaded = cache_manager:loadCache(test_book)
            assert.is_not_nil(loaded)
            assert.are.equal("Charlie", loaded.characters[1].name)
        end)

        it("serializes and coalesces overlapping async saves cleanly without data loss", function()
            local UIManager = require("ui/uimanager")
            local orig_scheduleIn = UIManager.scheduleIn
            local queue = {}
            UIManager.scheduleIn = function(self_or_delay, delay_or_fn, maybe_fn)
                local fn = type(maybe_fn) == "function" and maybe_fn or (type(delay_or_fn) == "function" and delay_or_fn or self_or_delay)
                table.insert(queue, fn)
            end

            local data1 = { characters = { { name = "FirstSave" } } }
            local data2 = { characters = { { name = "SecondSave" } } }
            local data3 = { characters = { { name = "ThirdSave" } } }

            local cb1_called, cb2_called, cb3_called = false, false, false

            -- First async save starts
            local s1 = cache_manager:asyncSaveCache(test_book, data1, function(res)
                cb1_called = res
            end)
            assert.is_true(s1)
            -- Coroutine is scheduled in queue, file is open
            assert.are.equal(1, #queue)

            -- Second async save is requested while first is active -> gets queued as pending
            local s2 = cache_manager:asyncSaveCache(test_book, data2, function(res)
                cb2_called = res
            end)
            assert.is_true(s2)

            -- Third async save is requested while first is still active -> coalesces pending with data3
            local s3 = cache_manager:asyncSaveCache(test_book, data3, function(res)
                cb3_called = res
            end)
            assert.is_true(s3)

            -- Drive the scheduled queue to completion
            local iterations = 0
            while #queue > 0 and iterations < 1000 do
                iterations = iterations + 1
                local step = table.remove(queue, 1)
                step()
            end

            UIManager.scheduleIn = orig_scheduleIn

            assert.is_true(cb1_called)
            assert.is_true(cb2_called)
            assert.is_true(cb3_called)

            -- Cache file should exist and have data3 (the latest coalesced data)
            local loaded = cache_manager:loadCache(test_book)
            assert.is_not_nil(loaded)
            assert.are.equal("ThirdSave", loaded.characters[1].name)

            -- Temp file should be cleaned up
            local f_tmp = io.open(test_cache .. ".tmp", "r")
            assert.is_nil(f_tmp)
        end)

        it("handles synchronous saveCache while an async save is active", function()
            local UIManager = require("ui/uimanager")
            local orig_scheduleIn = UIManager.scheduleIn
            local queue = {}
            UIManager.scheduleIn = function(self_or_delay, delay_or_fn, maybe_fn)
                local fn = type(maybe_fn) == "function" and maybe_fn or (type(delay_or_fn) == "function" and delay_or_fn or self_or_delay)
                table.insert(queue, fn)
            end

            local async_data = { characters = { { name = "AsyncInFlight" } } }
            local async_cb_called = nil
            local s1 = cache_manager:asyncSaveCache(test_book, async_data, function(res)
                async_cb_called = res
            end)
            assert.is_true(s1)

            -- Save synchronously while async is in flight
            local sync_data = { characters = { { name = "SyncOverride" } } }
            local s2 = cache_manager:saveCache(test_book, sync_data)
            assert.is_true(s2)

            -- In-flight async callback was notified of cancellation
            assert.is_false(async_cb_called)

            UIManager.scheduleIn = orig_scheduleIn

            -- Cache file has sync data
            local loaded = cache_manager:loadCache(test_book)
            assert.is_not_nil(loaded)
            assert.are.equal("SyncOverride", loaded.characters[1].name)
        end)

        it("flushes in-flight and pending async saves synchronously with flushAsyncSaves", function()
            local UIManager = require("ui/uimanager")
            local orig_scheduleIn = UIManager.scheduleIn
            local queue = {}
            UIManager.scheduleIn = function(self_or_delay, delay_or_fn, maybe_fn)
                local fn = type(maybe_fn) == "function" and maybe_fn or (type(delay_or_fn) == "function" and delay_or_fn or self_or_delay)
                table.insert(queue, fn)
            end

            local data1 = { characters = { { name = "ActiveSave" } } }
            local data2 = { characters = { { name = "PendingSave" } } }
            local cb1_called, cb2_called = nil, nil

            cache_manager:asyncSaveCache(test_book, data1, function(res) cb1_called = res end)
            cache_manager:asyncSaveCache(test_book, data2, function(res) cb2_called = res end)

            -- Flush all saves synchronously
            cache_manager:flushAsyncSaves()

            UIManager.scheduleIn = orig_scheduleIn

            assert.is_true(cb1_called)
            assert.is_true(cb2_called)

            -- The loaded cache must contain data2 (the newest pending data)
            local loaded = cache_manager:loadCache(test_book)
            assert.is_not_nil(loaded)
            assert.are.equal("PendingSave", loaded.characters[1].name)
        end)

        it("does not serialize private underscore fields like _norm_name and _norm_aliases", function()
            local data = {
                characters = {
                    {
                        name = "Sherlock Holmes",
                        _norm_name = "sherlock holmes",
                        aliases = { "Sherlock" },
                        _norm_aliases = { "sherlock" }
                    }
                }
            }
            local success = cache_manager:saveCache(test_book, data)
            assert.is_true(success)

            local f = io.open(test_cache, "r")
            assert.is_not_nil(f)
            local content = f:read("*all")
            f:close()

            assert.is_nil(content:find("_norm_name"))
            assert.is_nil(content:find("_norm_aliases"))

            local loaded = cache_manager:loadCache(test_book)
            assert.is_not_nil(loaded)
            assert.are.equal("Sherlock Holmes", loaded.characters[1].name)
            assert.is_nil(loaded.characters[1]._norm_name)
            assert.is_nil(loaded.characters[1]._norm_aliases)
        end)
    end)

    describe("External JSON Cache Support and Overwrite Protection", function()
        local test_json = test_book .. ".sdr/xray_cache.json"

        it("loads a valid xray_cache.json and defaults entry source to external", function()
            local f = io.open(test_json, "w")
            f:write([[{
                "schema_version": "1.0",
                "book_title": "Dune",
                "external_source": { "name": "BookOrbit", "prevent_overwrite": true },
                "characters": [
                    { "name": "Paul Atreides", "role": "Protagonist" },
                    { "name": "Lady Jessica", "source": "bookorbit" }
                ],
                "timeline": [
                    { "chapter": "Chapter 1", "chapter_index": 1, "event": "The gom jabbar test." }
                ]
            }]])
            f:close()

            local loaded = cache_manager:loadCache(test_book)
            assert.is_not_nil(loaded)
            assert.are.equal("Dune", loaded.book_title)
            assert.are.equal("6.1", loaded.cache_version)
            assert.is_true(loaded._loaded_from_json)
            assert.are.equal("external", loaded.characters[1].source)
            assert.are.equal("bookorbit", loaded.characters[2].source)
            assert.are.equal("external", loaded.timeline[1].source)
            assert.is_table(loaded.locations)
            assert.is_table(loaded.terms)
            assert.is_true(cache_manager:isOverwriteProtected(loaded))
            assert.is_false(cache_manager:isReadOnly(loaded))
        end)

        it("prefers newer xray_cache.json over older xray_cache.lua and vice versa", function()
            cache_manager:saveCache(test_book, { characters = { { name = "LuaAlice" } } })

            local f = io.open(test_json, "w")
            f:write('{"schema_version":"1.0","characters":[{"name":"JsonAlice"}]}')
            f:close()

            local lfs_mock = package.loaded["lfs"]
            local orig_attr = lfs_mock.attributes
            local mtimes = { [test_cache] = 1000, [test_json] = 2000 }
            lfs_mock.attributes = function(path, req)
                local res = orig_attr(path, req)
                if type(res) == "table" and mtimes[path] then
                    res.modification = mtimes[path]
                end
                return res
            end

            local ok_test, err = pcall(function()
                local loaded1 = cache_manager:loadCache(test_book)
                assert.is_not_nil(loaded1)
                assert.are.equal("JsonAlice", loaded1.characters[1].name)

                -- Now make Lua cache newer
                mtimes[test_cache] = 3000
                local loaded2 = cache_manager:loadCache(test_book)
                assert.is_not_nil(loaded2)
                assert.are.equal("LuaAlice", loaded2.characters[1].name)
            end)
            lfs_mock.attributes = orig_attr
            if not ok_test then error(err) end
        end)

        it("falls back to xray_cache.lua when xray_cache.json is malformed or has unsupported version", function()
            cache_manager:saveCache(test_book, { characters = { { name = "SafeLua" } } })
            os.execute("touch -t 202601010000 " .. test_cache)

            local f = io.open(test_json, "w")
            f:write("{ invalid json !!!")
            f:close()
            os.execute("touch -t 202601020000 " .. test_json)

            local loaded = cache_manager:loadCache(test_book)
            assert.is_not_nil(loaded)
            assert.are.equal("SafeLua", loaded.characters[1].name)

            -- Unsupported schema_version
            local f2 = io.open(test_json, "w")
            f2:write('{"schema_version":"99.0","characters":[{"name":"Future"}]}')
            f2:close()
            os.execute("touch -t 202601030000 " .. test_json)

            local loaded2 = cache_manager:loadCache(test_book)
            assert.is_not_nil(loaded2)
            assert.are.equal("SafeLua", loaded2.characters[1].name)
        end)

        it("rejects oversized xray_cache.json files safely", function()
            local orig_max = cache_manager.MAX_JSON_CACHE_BYTES
            cache_manager.MAX_JSON_CACHE_BYTES = 32
            local f = io.open(test_json, "w")
            f:write('{"schema_version":"1.0","book_title":"WayTooLongForTinyLimit"}')
            f:close()

            local loaded = cache_manager:loadCache(test_book)
            cache_manager.MAX_JSON_CACHE_BYTES = orig_max
            assert.is_nil(loaded)
        end)

        it("refuses saveCache and asyncSaveCache when read_only is true and never modifies xray_cache.json", function()
            local f = io.open(test_json, "w")
            f:write('{"schema_version":"1.0","read_only":true,"characters":[{"name":"Locked"}]}')
            f:close()

            local loaded = cache_manager:loadCache(test_book)
            assert.is_true(cache_manager:isReadOnly(loaded))
            assert.is_true(cache_manager:isOverwriteProtected(loaded))

            assert.is_false(cache_manager:saveCache(test_book, loaded))
            local cb_res = nil
            assert.is_false(cache_manager:asyncSaveCache(test_book, loaded, function(ok) cb_res = ok end))
            assert.is_false(cb_res)

            -- xray_cache.lua was not created
            local f_lua = io.open(test_cache, "r")
            assert.is_nil(f_lua)
        end)

        it("clears both xray_cache.lua and xray_cache.json on clearCache", function()
            cache_manager:saveCache(test_book, { characters = { { name = "LuaChar" } } })
            local f = io.open(test_json, "w")
            f:write('{"schema_version":"1.0","characters":[{"name":"JsonChar"}]}')
            f:close()

            assert.is_true(cache_manager:clearCache(test_book))
            assert.is_nil(io.open(test_cache, "r"))
            assert.is_nil(io.open(test_json, "r"))
        end)

        it("respects external_source.prevent_overwrite = false while keeping read_only false", function()
            local data = {
                external_source = { name = "BookOrbit", prevent_overwrite = false }
            }
            assert.is_false(cache_manager:isOverwriteProtected(data))
            assert.is_false(cache_manager:isReadOnly(data))
        end)
    end)
end)
