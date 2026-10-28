require("spec.spec_helper")

local UIManager = require("ui/uimanager")
local XRayPlugin = dofile("xray.koplugin/main.lua")

describe("X-Ray Book Type Detection and Archive Format Protection", function()
    local plugin
    local async_detect_called, async_detect_args
    local saved_caches
    local underlines_cleared, underlines_applied, scan_triggered
    local original_schedule

    local function createMockPlugin(doc_file, props)
        local p = setmetatable({}, { __index = XRayPlugin })
        p.destroyed = false
        p.ui = {
            document = {
                file = doc_file,
                getProps = function() return props or {} end
            }
        }
        p.book_data = {}
        p.loc = {
            t = function(_, str) return nil end
        }
        p.ai_helper = {
            settings = {
                unit_disabled_book_types = { "manga", "graphic_novel", "children", "poetry" }
            },
            hasApiKey = function() return true end,
            detectBookTypeAsync = function(self_ai, title, author, series, desc, res_file)
                async_detect_called = async_detect_called + 1
                table.insert(async_detect_args, {
                    title = title,
                    author = author,
                    series = series,
                    desc = desc,
                    res_file = res_file
                })
                return 12345 -- mock pid
            end,
            checkAsyncResult = function(self_ai, res_file, pid)
                return nil -- pending
            end
        }
        p.cache_manager = {
            asyncSaveCache = function(self_cm, file, data)
                table.insert(saved_caches, { file = file, data = data })
            end
        }
        p.clearUnitUnderlines = function()
            underlines_cleared = underlines_cleared + 1
        end
        p.applyUnitUnderlines = function()
            underlines_applied = underlines_applied + 1
        end
        p.scanBookForUnits = function()
            scan_triggered = scan_triggered + 1
        end
        p.loadUnitCache = function()
            return false
        end
        p.log = function() end
        return p
    end

    before_each(function()
        async_detect_called = 0
        async_detect_args = {}
        saved_caches = {}
        underlines_cleared = 0
        underlines_applied = 0
        scan_triggered = 0
        original_schedule = UIManager.scheduleIn
        UIManager.scheduleIn = function(self_ui, delay, fn)
            -- mock scheduler
        end
    end)

    after_each(function()
        UIManager.scheduleIn = original_schedule
    end)

    describe("detectBookTypeHeuristic", function()
        it("detects .cbz, .cbr, .cb7, and .cbt as manga with high confidence", function()
            local formats = { "comic.cbz", "manga.cbr", "book.cb7", "strip.cbt", "ARCHIVE.CBZ" }
            for _, f in ipairs(formats) do
                local p = createMockPlugin("/books/" .. f)
                local btype, confident = p:detectBookTypeHeuristic()
                assert.are.equal("manga", btype)
                assert.is_true(confident)
            end
        end)

        it("detects subjects with high confidence", function()
            local p = createMockPlugin("/books/novel.epub", { subject = "Science Fiction" })
            local btype, confident = p:detectBookTypeHeuristic()
            assert.are.equal("prose_fiction", btype)
            assert.is_true(confident)

            local p2 = createMockPlugin("/books/food.epub", { subject = "Cooking, Recipes" })
            local btype2, confident2 = p2:detectBookTypeHeuristic()
            assert.are.equal("cookbook", btype2)
            assert.is_true(confident2)
        end)

        it("detects fallback text extensions with low confidence", function()
            local p = createMockPlugin("/books/test.epub", { title = "My Story" })
            local btype, confident = p:detectBookTypeHeuristic()
            assert.are.equal("prose_fiction", btype)
            assert.is_false(confident)
        end)
    end)

    describe("getEffectiveBookType", function()
        it("returns manga for archive formats even if cached book_type_label was corrupted to prose_fiction", function()
            local p = createMockPlugin("/books/chapter1.cbz")
            p.book_data = {
                book_type_label = "prose_fiction",
                book_type_detected_by_ai = true
            }
            assert.are.equal("manga", p:getEffectiveBookType())
        end)

        it("allows graphic_novel for archive formats", function()
            local p = createMockPlugin("/books/chapter1.cbz")
            p.book_data = {
                book_type_label = "graphic_novel",
                book_type_confident = true
            }
            assert.are.equal("graphic_novel", p:getEffectiveBookType())
        end)

        it("respects explicit user override even on archive formats", function()
            local p = createMockPlugin("/books/chapter1.cbz")
            p.book_data = {
                book_type_label = "manga",
                book_type_label_override = "prose_nonfiction"
            }
            assert.are.equal("prose_nonfiction", p:getEffectiveBookType())
        end)
    end)

    describe("triggerBookTypeDetection", function()
        it("saves book_type_confident = true and skips AI on initial open of a .cbz", function()
            local p = createMockPlugin("/books/manga_vol1.cbz")
            p:triggerBookTypeDetection()

            assert.are.equal("manga", p.book_data.book_type_label)
            assert.is_true(p.book_data.book_type_confident)
            assert.is_false(p.book_data.book_type_detected_by_ai)
            assert.are.equal(0, async_detect_called)
            assert.are.equal(1, #saved_caches)
            assert.are.equal(1, underlines_cleared) -- manga is disabled in unit settings
            assert.are.equal(0, scan_triggered)
        end)

        it("skips AI on subsequent opens of confident cached .cbz (Issue #145 fix)", function()
            local p = createMockPlugin("/books/manga_vol1.cbz")
            p.book_data = {
                book_type_label = "manga",
                book_type_confident = true,
                book_type_detected_by_ai = false
            }
            p:triggerBookTypeDetection()

            assert.are.equal(0, async_detect_called)
            assert.are.equal(1, underlines_cleared)
            assert.are.equal(0, scan_triggered)
        end)

        it("self-heals legacy cache (book_type_confident == nil) and skips AI on .cbz", function()
            local p = createMockPlugin("/books/manga_chapter3.cbz")
            p.book_data = {
                cache_version = "6.0",
                book_type_label = "manga",
                book_type_detected_by_ai = false
                -- book_type_confident is nil (as in old caches)
            }
            p:triggerBookTypeDetection()

            assert.is_true(p.book_data.book_type_confident)
            assert.is_false(p.book_data.book_type_detected_by_ai)
            assert.are.equal(0, async_detect_called)
            assert.are.equal(1, #saved_caches) -- healed cache persisted
        end)

        it("self-heals corrupted cache where AI answered prose_fiction on a .cbz", function()
            local p = createMockPlugin("/books/manga_chapter4.cbz")
            p.book_data = {
                cache_version = "6.0",
                book_type_label = "prose_fiction",
                book_type_detected_by_ai = true
            }
            p:triggerBookTypeDetection()

            assert.are.equal("manga", p.book_data.book_type_label)
            assert.is_true(p.book_data.book_type_confident)
            assert.is_false(p.book_data.book_type_detected_by_ai)
            assert.are.equal(0, async_detect_called)
            assert.are.equal(1, underlines_cleared)
            assert.are.equal(0, scan_triggered)
        end)

        it("rejects AI background override if it completes on an archive format", function()
            local p = createMockPlugin("/books/manga_chapter5.cbz")
            p.book_data = {
                book_type_label = "manga",
                book_type_confident = false,
                book_type_detected_by_ai = false
            }

            local scheduled_cb
            UIManager.scheduleIn = function(self_ui, delay, fn)
                scheduled_cb = fn
            end

            -- Simulate AI returning prose_fiction
            p.ai_helper.checkAsyncResult = function()
                return { book_type_label = "prose_fiction" }
            end

            -- Trigger refinement
            p:triggerBookTypeDetection()

            -- Execute poll result
            if scheduled_cb then scheduled_cb() end

            -- Must NOT have changed to prose_fiction
            assert.are.equal("manga", p.book_data.book_type_label)
            assert.is_true(p.book_data.book_type_confident)
        end)

        it("clears underlines and never scans when book type is disabled, even if unit cache exists", function()
            local p = createMockPlugin("/books/comic.cbz")
            p.book_data = {
                book_type_label = "manga",
                book_type_confident = true,
                book_type_detected_by_ai = false
            }
            p.loadUnitCache = function() return true end -- unit cache exists on disk

            p:triggerBookTypeDetection()

            assert.are.equal(1, underlines_cleared)
            assert.are.equal(0, underlines_applied)
            assert.are.equal(0, scan_triggered)
        end)

        it("triggers AI refinement for low-confidence text books but only once concurrently", function()
            local p = createMockPlugin("/books/novel.epub", { title = "A Mystery" })
            p:triggerBookTypeDetection()

            assert.are.equal("prose_fiction", p.book_data.book_type_label)
            assert.is_false(p.book_data.book_type_confident)
            assert.are.equal(1, async_detect_called)

            -- Calling again while in-flight should NOT trigger second call
            p:triggerBookTypeDetection()
            assert.are.equal(1, async_detect_called)
        end)

        it("triggers scan only once during initial detection even when AI refinement completes", function()
            local p = createMockPlugin("/books/novel.epub", { title = "A Mystery" })
            local poll_cb
            UIManager.scheduleIn = function(self_ui, delay, fn)
                poll_cb = fn
            end
            p.ai_helper.checkAsyncResult = function()
                return { book_type_label = "prose_fiction" }
            end

            p:triggerBookTypeDetection()
            assert.are.equal(1, scan_triggered)

            -- When AI background refinement finishes, it must NOT trigger a second scan
            if poll_cb then poll_cb() end
            assert.are.equal(1, scan_triggered)
            assert.are.equal(1, underlines_applied)
        end)
    end)

    describe("getBookTypeFilterMenu", function()
        it("displays Heuristic when detected via heuristic or archive format", function()
            local p = createMockPlugin("/books/comic.cbz")
            p.book_data = {
                book_type_label = "manga",
                book_type_confident = true,
                book_type_detected_by_ai = false
            }
            local menu = p:getBookTypeFilterMenu()
            assert.is_table(menu)
            assert.is_string(menu[1].text)
            assert.is_truthy(menu[1].text:find("%(Heuristic%)"))
            assert.is_falsy(menu[1].text:find("%(AI%)"))
        end)

        it("displays AI when detected by AI", function()
            local p = createMockPlugin("/books/novel.epub")
            p.book_data = {
                book_type_label = "prose_fiction",
                book_type_confident = true,
                book_type_detected_by_ai = true
            }
            local menu = p:getBookTypeFilterMenu()
            assert.is_table(menu)
            assert.is_string(menu[1].text)
            assert.is_truthy(menu[1].text:find("%(AI%)"))
        end)
    end)
end)
