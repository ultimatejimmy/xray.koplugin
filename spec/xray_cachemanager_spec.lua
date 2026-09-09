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
    end)
end)

describe("atomic cooperative cache writes", function()
    local UIManager = require("ui/uimanager")
    local cm, tasks, original_schedule, path
    before_each(function()
        path = "/tmp/atomic_book.epub"
        os.execute("mkdir -p /tmp/atomic_book.epub.sdr")
        cm = require("xray_cachemanager"):new()
        tasks = {}
        original_schedule = UIManager.scheduleIn
        UIManager.scheduleIn = function(_, _, callback) tasks[#tasks + 1] = callback end
        assert.is_true(cm:saveCache(path, { last_fetch_page = 10 }))
        tasks = {}
    end)
    after_each(function()
        cm:cancelAsyncSaves()
        UIManager.scheduleIn = original_schedule
        os.execute("rm -rf /tmp/atomic_book.epub.sdr")
    end)
    local function drain()
        while #tasks > 0 do table.remove(tasks, 1)() end
    end
    it("keeps the previous cache readable until rename and snapshots mutable data", function()
        local data = { last_fetch_page = 20, characters = {} }
        for i = 1, 200 do data.characters[i] = { name = "Character " .. i } end
        local done = false
        cm:asyncSaveCache(path, data, function(success) done = success end)
        data.last_fetch_page = 99
        table.remove(tasks, 1)()
        assert.is_false(done)
        assert.are.equal(10, cm:loadCache(path).last_fetch_page)
        drain()
        assert.is_true(done)
        assert.are.equal(20, cm:loadCache(path).last_fetch_page)
    end)
    it("reports failed rename and preserves the previous checkpoint", function()
        local original_rename, result = os.rename
        os.rename = function() return nil, "injected failure" end
        local ok, err = pcall(function()
            cm:asyncSaveCache(path, { last_fetch_page = 20 }, function(success) result = success end)
            drain()
            assert.is_false(result)
            assert.are.equal(10, cm:loadCache(path).last_fetch_page)
        end)
        os.rename = original_rename
        if not ok then error(err) end
    end)
    it("serializes different manager instances writing the same book", function()
        local second = require("xray_cachemanager"):new()
        cm:asyncSaveCache(path, { last_fetch_page = 20 })
        second:asyncSaveCache(path, { last_fetch_page = 30 })
        drain()
        assert.are.equal(30, cm:loadCache(path).last_fetch_page)
    end)
    it("cancels partial writes without truncating the live cache", function()
        local data = { last_fetch_page = 50, characters = {} }
        for i = 1, 200 do data.characters[i] = { name = "Character " .. i } end
        local result
        cm:asyncSaveCache(path, data, function(success) result = success end)
        table.remove(tasks, 1)()
        cm:cancelAsyncSaves()
        drain()
        assert.is_false(result)
        assert.are.equal(10, cm:loadCache(path).last_fetch_page)
    end)
end)
