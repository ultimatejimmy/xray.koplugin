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
            assert.are.equal("6.0", loaded.cache_version)
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
    end)
end)
