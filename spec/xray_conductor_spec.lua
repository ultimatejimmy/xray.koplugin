-- spec/xray_conductor_spec.lua
-- Unit tests for Storefront Memory Conductor integration (xray_conductor, Level 1 MemoryReclaim, Level 2 slots)
require("spec/spec_helper")

describe("Storefront Memory Conductor Integration", function()
    local conductor
    local main_plugin

    before_each(function()
        package.loaded["storefront_conductor"] = nil
        package.loaded["xray_conductor"] = nil
        conductor = require("xray_conductor")
        main_plugin = dofile("xray.koplugin/main.lua")
    end)

    after_each(function()
        package.loaded["storefront_conductor"] = nil
        package.loaded["xray_conductor"] = nil
    end)

    describe("Standalone Fallback (without Storefront)", function()
        it("reports unavailable and executes runSlot immediately", function()
            assert.is_false(conductor.isAvailable())
            assert.is_nil(conductor.get())
            assert.is_false(conductor.reclaimMemory("soft", "xray"))
            assert.is_nil(conductor.getMemoryStatus())
            assert.is_nil(conductor.getStats())

            local ran = false
            local done_ref = nil
            conductor.runSlot(nil, {
                task = "standalone_test",
                run = function(done)
                    ran = true
                    done_ref = done
                    done()
                    done() -- idempotent
                end,
            })
            assert.is_true(ran)
            assert.are.equal("function", type(done_ref))
        end)

        it("register returns false cleanly when Storefront is absent", function()
            local plugin = createMockPlugin()
            assert.is_false(conductor.register(plugin))
        end)
    end)

    describe("Level 2 Conductor Integration (with mocked storefront_conductor)", function()
        local recorded_register
        local recorded_slots
        local recorded_reclaim

        before_each(function()
            recorded_register = nil
            recorded_slots = {}
            recorded_reclaim = {}
            package.loaded["storefront_conductor"] = {
                registerPlugin = function(opts)
                    recorded_register = opts
                end,
                requestSlot = function(opts)
                    table.insert(recorded_slots, opts)
                    return { id = #recorded_slots }
                end,
                reclaimMemory = function(level, exclude)
                    table.insert(recorded_reclaim, { level = level, exclude = exclude })
                end,
                getMemoryStatus = function()
                    return { available_kb = 60000, is_low_memory_device = true }
                end,
                getStats = function()
                    return { slots_requested = 3, slots_deduplicated = 1 }
                end,
            }
            package.loaded["xray_conductor"] = nil
            conductor = require("xray_conductor")
        end)

        it("detects availability, forwards reclaimMemory, getMemoryStatus, and getStats", function()
            assert.is_true(conductor.isAvailable())
            assert.is_true(conductor.reclaimMemory("soft", "xray"))
            assert.are.equal(1, #recorded_reclaim)
            assert.are.equal("soft", recorded_reclaim[1].level)
            assert.are.equal("xray", recorded_reclaim[1].exclude)

            local status = conductor.getMemoryStatus()
            assert.is_table(status)
            assert.are.equal(60000, status.available_kb)

            local stats = conductor.getStats()
            assert.is_table(stats)
            assert.are.equal(3, stats.slots_requested)
            assert.are.equal(1, stats.slots_deduplicated)
        end)

        it("enforces one-shot done() idempotency, forwards dedupe_key/lease_s, and guards stale docs", function()
            local doc_a = { file = "/books/a.epub" }
            local doc_b = { file = "/books/b.epub" }
            local plugin = createMockPlugin()
            plugin.ui = { document = doc_a }

            local raw_done_calls = 0
            local inner_ran = false
            conductor.runSlot(plugin, {
                task = "stale_test",
                priority = "idle_bg",
                dedupe_key = "xray:stale_test",
                lease_s = 120,
                subprocess = true,
                document = doc_a,
                run = function(done)
                    inner_ran = true
                    done()
                    done()
                end,
            })

            assert.are.equal(1, #recorded_slots)
            assert.are.equal("xray", recorded_slots[1].plugin)
            assert.are.equal("idle_bg", recorded_slots[1].priority)
            assert.are.equal("xray:stale_test", recorded_slots[1].dedupe_key)
            assert.are.equal(120, recorded_slots[1].lease_s)
            assert.is_true(recorded_slots[1].subprocess)

            -- Simulate document changing before slot is dispatched
            plugin.ui.document = doc_b
            recorded_slots[1].run(function()
                raw_done_calls = raw_done_calls + 1
            end)
            assert.is_false(inner_ran)
            assert.are.equal(1, raw_done_calls)

            -- Now test normal dispatch with multiple done() calls
            plugin.ui.document = doc_a
            raw_done_calls = 0
            recorded_slots[1].run(function()
                raw_done_calls = raw_done_calls + 1
            end)
            assert.is_true(inner_ran)
            assert.are.equal(1, raw_done_calls)
        end)

        it("propagates cancel and on_rejected callbacks", function()
            local plugin = createMockPlugin()
            local cancelled = false
            local rejected_reason = nil
            local raw_done_calls = 0

            conductor.runSlot(plugin, {
                task = "cancel_test",
                run = function() end,
                cancel = function() cancelled = true end,
                on_rejected = function(reason) rejected_reason = reason end,
            })

            recorded_slots[1].run(function() raw_done_calls = raw_done_calls + 1 end)
            recorded_slots[1].cancel()
            assert.is_true(cancelled)
            assert.are.equal(1, raw_done_calls)

            recorded_slots[1].on_rejected("low_memory")
            assert.are.equal("low_memory", rejected_reason)
        end)

        it("registers XRayPlugin on init and wires is_foreground, on_reclaim, on_cancel_bg", function()
            local inst = createMockPlugin()
            for k, v in pairs(main_plugin) do inst[k] = v end
            inst.path = "xray.koplugin/"
            inst:init()

            assert.is_not_nil(recorded_register)
            assert.are.equal("xray", recorded_register.plugin)
            assert.is_false(recorded_register.is_foreground())

            inst.xray_menu = { dummy = true }
            assert.is_true(recorded_register.is_foreground())
            inst.xray_menu = nil

            -- on_reclaim("soft") clears caches when no menu is open
            inst._cached_toc = { { title = "Ch1", page = 1 } }
            inst._box_cache_sig = "sig1"
            recorded_register.on_reclaim("soft")
            assert.is_nil(inst._cached_toc)
            assert.is_nil(inst._box_cache_sig)

            -- on_cancel_bg cancels background work without crashing
            inst.pending_background_fetch = true
            recorded_register.on_cancel_bg()
            assert.is_false(inst.pending_background_fetch)

            inst:destroy()
        end)
    end)

    describe("Level 1 onMemoryReclaim Event", function()
        it("returns false and respects foreground open state on soft reclaim", function()
            local inst = createMockPlugin()
            for k, v in pairs(main_plugin) do inst[k] = v end
            inst.path = "xray.koplugin/"
            inst:init()

            local tile_cleared = false
            local entity_cleared = false
            local seq_cancelled = false
            inst.clearTileCaches = function() tile_cleared = true end
            inst.clearEntityUnderlines = function() entity_cleared = true end
            inst.cancelSequentialChapterScan = function() seq_cancelled = true end

            -- Foreground menu open: soft reclaim preserves caches
            inst.char_menu = { open = true }
            inst._cached_toc = { { title = "Ch1" } }
            local ret1 = inst:onMemoryReclaim("soft")
            assert.is_false(ret1)
            assert.is_false(tile_cleared)
            assert.is_not_nil(inst._cached_toc)

            -- Foreground menu closed: soft reclaim clears tile & TOC caches, keeps entity underlines
            inst.char_menu = nil
            local ret2 = inst:onMemoryReclaim("soft")
            assert.is_false(ret2)
            assert.is_true(tile_cleared)
            assert.is_nil(inst._cached_toc)
            assert.is_false(entity_cleared)

            -- Critical reclaim: also clears entity underlines and halts non-manual sequential scan
            inst.is_sequential_scan_active = true
            inst.active_sequential_is_manual = false
            local ret3 = inst:onMemoryReclaim("critical")
            assert.is_false(ret3)
            assert.is_true(entity_cleared)
            assert.is_true(seq_cancelled)

            inst:destroy()
        end)
    end)
end)
