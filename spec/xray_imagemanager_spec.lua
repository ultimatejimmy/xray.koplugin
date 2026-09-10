-- spec/xray_imagemanager_spec.lua
require("spec.spec_helper")
local ImageManager = require("xray_imagemanager")
local SeriesManager = require("xray_seriesmanager")

describe("xray_imagemanager", function()
    local img_mgr
    local series_mgr

    before_each(function()
        img_mgr = ImageManager:new()
        series_mgr = SeriesManager:new()
        os.execute("mkdir -p /tmp/koreader/settings/xray/series")
    end)

    after_each(function()
        os.execute("rm -rf /tmp/koreader")
    end)

    describe("generateImageId", function()
        it("creates consistent safe id from href", function()
            local id = img_mgr:generateImageId("images/map_westlands.png", 1)
            assert.are.equal("images_map_westlands.png_1", id)

            local id2 = img_mgr:generateImageId("OEBPS/Images/Diagram#1.jpg", 14)
            assert.are.equal("OEBPS_Images_Diagram_1.jpg_14", id2)
        end)
    end)

    describe("classifyImage", function()
        it("detects maps correctly", function()
            assert.are.equal("map", img_mgr:classifyImage("Map of the Westlands", "img01.jpg"))
            assert.are.equal("map", img_mgr:classifyImage("World Overview", "images/karte_welt.png"))
            assert.are.equal("map", img_mgr:classifyImage("Plano de la Ciudad", "plano.jpg"))
        end)

        it("detects diagrams and trees correctly", function()
            assert.are.equal("diagram", img_mgr:classifyImage("House Lineage", "tree.png"))
            assert.are.equal("diagram", img_mgr:classifyImage("Ship Layout Diagram", "ship_floorplan.jpg"))
            assert.are.equal("diagram", img_mgr:classifyImage("Battle Chart", "chart.svg"))
        end)

        it("detects general illustrations", function()
            assert.are.equal("illustration", img_mgr:classifyImage("Figure 1", "fig1.jpg"))
            assert.are.equal("illustration", img_mgr:classifyImage("Plate IV", "plate4.jpg"))
        end)
    end)

    describe("isOrnamental and filterImages", function()
        it("filters out decorative ornaments and tiny icons in standard mode", function()
            local ornamental = { title = "Divider Ornament", href = "images/fleuron_sep.png", width = 30, height = 30 }
            assert.is_true(img_mgr:isOrnamental(ornamental, "standard"))

            local map = { title = "Map of Randland", href = "images/map.jpg", width = 1600, height = 1200 }
            assert.is_false(img_mgr:isOrnamental(map, "standard"))
        end)

        it("includes all images when filter_mode is 'all'", function()
            local ornamental = { title = "Divider Ornament", href = "images/fleuron_sep.png", width = 30, height = 30 }
            assert.is_false(img_mgr:isOrnamental(ornamental, "all"))
        end)

        it("filters non-large images when filter_mode is 'large_only'", function()
            local med_img = { title = "Small icon", href = "img.png", width = 200, height = 200 }
            assert.is_true(img_mgr:isOrnamental(med_img, "large_only"))

            local large_map = { title = "Large Map", href = "big_map.png", width = 1200, height = 900 }
            assert.is_false(img_mgr:isOrnamental(large_map, "large_only"))
        end)
    end)

    describe("getFilteredImages and Spoilers", function()
        local test_images

        before_each(function()
            test_images = {
                { id = "img1", title = "Map of Caemlyn", page = 10, is_favorite = false },
                { id = "img2", title = "Battle of Dumai's Wells", page = 500, is_favorite = false },
                { id = "img3", title = "World Map", page = 5, is_favorite = true },
                { id = "img4", title = "Hidden Sketch", page = 20, is_hidden = true },
            }
        end)

        it("orders favorites first, then by page order", function()
            local res = img_mgr:getFilteredImages(test_images, "all", 200, "standard")
            assert.are.equal(3, #res)
            assert.are.equal("img3", res[1].id) -- Favorite first
            assert.are.equal("img1", res[2].id) -- Page 10
            assert.are.equal("img2", res[3].id) -- Page 500
        end)

        it("flags spoilers accurately based on current reading page", function()
            local res = img_mgr:getFilteredImages(test_images, "all", 200, "standard")
            -- img1 (page 10) <= current_page (200) -> not spoiler
            assert.is_false(res[2].is_spoiler)
            -- img2 (page 500) > current_page (200) -> spoiler
            assert.is_true(res[3].is_spoiler)
        end)

        it("filters only favorites in favorites tab", function()
            local res = img_mgr:getFilteredImages(test_images, "favorites", 200, "standard")
            assert.are.equal(1, #res)
            assert.are.equal("img3", res[1].id)
        end)

        it("filters hidden items in hidden tab", function()
            local res = img_mgr:getFilteredImages(test_images, "hidden", 200, "standard")
            assert.are.equal(1, #res)
            assert.are.equal("img4", res[1].id)
        end)
    end)

    describe("toggleFavorite, rename, hide", function()
        local book_data

        before_each(function()
            book_data = {
                images = {
                    { id = "img1", title = "Original Map", page = 15, is_favorite = false, is_hidden = false }
                }
            }
        end)

        it("toggles favorite state", function()
            local fav = img_mgr:toggleFavorite(book_data, "img1")
            assert.is_true(fav)
            assert.is_true(book_data.images[1].is_favorite)

            local unfav = img_mgr:toggleFavorite(book_data, "img1")
            assert.is_false(unfav)
            assert.is_false(book_data.images[1].is_favorite)
        end)

        it("renames image title", function()
            local ok = img_mgr:renameImage(book_data, "img1", "Updated Realm Map")
            assert.is_true(ok)
            assert.are.equal("Updated Realm Map", book_data.images[1].title)
            assert.is_true(book_data.images[1].custom_title)
        end)

        it("sets image rotation", function()
            local ok = img_mgr:setImageRotation(book_data, "img1", 90)
            assert.is_true(ok)
            assert.are.equal(90, book_data.images[1].rotation)
        end)

        it("sets image zoom and pan", function()
            local ok = img_mgr:setImageZoom(book_data, "img1", 2.5, -40, 60)
            assert.is_true(ok)
            assert.are.equal(2.5, book_data.images[1].zoom_level)
            assert.are.equal(-40, book_data.images[1].pan_x)
            assert.are.equal(60, book_data.images[1].pan_y)
        end)

        it("toggles hidden state", function()
            local hidden = img_mgr:toggleHideImage(book_data, "img1")
            assert.is_true(hidden)
            assert.is_true(book_data.images[1].is_hidden)
        end)
    end)

    describe("series images integration", function()
        it("saves and retrieves series images up to current book index", function()
            local slug = "stormlight_test"
            local book1_map = { id = "s_img1", title = "Roshar Map", source_book_index = 1, source_book_title = "Way of Kings" }
            local book3_map = { id = "s_img2", title = "Urithiru Map", source_book_index = 3, source_book_title = "Oathbringer" }

            series_mgr:saveSeriesImage(slug, book1_map)
            series_mgr:saveSeriesImage(slug, book3_map)

            -- When reading Book 2, reader should only see Book 1 maps
            local for_book2 = series_mgr:getSeriesImages(slug, 2)
            assert.are.equal(1, #for_book2)
            assert.are.equal("Roshar Map", for_book2[1].title)

            -- When reading Book 3, reader sees both
            local for_book3 = series_mgr:getSeriesImages(slug, 3)
            assert.are.equal(2, #for_book3)
        end)

        it("strictly isolates images to the requested series slug and ignores other series", function()
            local lotr_slug = "middle_earth_test"
            local cormoran_slug = "cormoran_strike_test"

            local shire_map = { id = "shire", title = "Shire Map", source_book_index = 1 }
            local london_map = { id = "london", title = "Soho Map", source_book_index = 1 }

            series_mgr:saveSeriesImage(lotr_slug, shire_map)
            series_mgr:saveSeriesImage(cormoran_slug, london_map)

            -- Cormoran Strike must ONLY return London map, never Shire map
            local cormoran_imgs = series_mgr:getSeriesImages(cormoran_slug, 1)
            assert.are.equal(1, #cormoran_imgs)
            assert.are.equal("london", cormoran_imgs[1].id)

            -- Middle Earth must ONLY return Shire map
            local lotr_imgs = series_mgr:getSeriesImages(lotr_slug, 1)
            assert.are.equal(1, #lotr_imgs)
            assert.are.equal("shire", lotr_imgs[1].id)
        end)

        it("refuses to save or return images for generic 'series' slug", function()
            local dummy = { id = "orphan", title = "Orphan Map" }
            assert.is_false(series_mgr:saveSeriesImage("series", dummy))
            assert.is_false(series_mgr:saveSeriesImage("", dummy))
            assert.is_false(series_mgr:saveSeriesImage(nil, dummy))

            assert.are.same({}, series_mgr:getSeriesImages("series", 1))
            assert.are.same({}, series_mgr:getSeriesImages("", 1))
            assert.are.same({}, series_mgr:getSeriesImages(nil, 1))
        end)

        it("getSeriesInfo resolves series metadata and returns nil for standalone books", function()
            -- Book with metadata
            local props = { series = "Cormoran Strike", series_index = 3 }
            local info = series_mgr:getSeriesInfo({}, props, "Career of Evil", "Robert Galbraith")
            assert.is_not_nil(info)
            assert.are.equal("cormoran_strike", info.slug)
            assert.are.equal(3, info.index)

            -- Standalone book without series
            local standalone_props = { title = "To Kill a Mockingbird" }
            local standalone_info = series_mgr:getSeriesInfo({}, standalone_props, "To Kill a Mockingbird", "Harper Lee")
            assert.is_nil(standalone_info)
        end)
    end)

    describe("resolveImagePage", function()
        it("always resolves cover images to page 1 and marks page_resolved", function()
            local cover_entry = { id = "img_cover", title = "Cover", href = "cover.jpeg", page = 45 }
            local res = img_mgr:resolveImagePage(nil, cover_entry)
            assert.are.equal(1, res)
            assert.are.equal(1, cover_entry.page)
            assert.is_true(cover_entry.page_resolved)
        end)

        it("returns immediately without disk lookup if entry already has valid page and is page_resolved", function()
            local mock_ui = {
                document = {
                    file = "/path/to/book.epub",
                    getPageCount = function() return 500 end,
                }
            }
            local entry = { id = "img1", title = "Map of Roshar", href = "images/map.jpg", page = 42, page_resolved = true }
            local res = img_mgr:resolveImagePage(mock_ui, entry)
            assert.are.equal(42, res)
        end)

        it("resolves and marks page_resolved when spine data is available", function()
            local mock_ui = {
                document = {
                    file = "/path/to/book.epub",
                    getPageCount = function() return 500 end,
                }
            }
            img_mgr._epub_spine_cache = {
                ["/path/to/book.epub"] = {
                    spine_items = { "text/map.xhtml" },
                    file_to_toc_idx = { ["map.xhtml"] = 1 },
                    flat_toc = { { title = "Map", page = 88 } },
                    spine_page_map = { [1] = 88 },
                    spine_contents = { ["text/map.xhtml"] = '<img src="map.jpg"/>' },
                    image_to_spine = {},
                }
            }
            local entry = { id = "img1", title = "Map", href = "map.jpg", page = 15, page_resolved = false }
            local res = img_mgr:resolveImagePage(mock_ui, entry)
            assert.are.equal(88, res)
            assert.are.equal(88, entry.page)
            assert.is_true(entry.page_resolved)
        end)

        it("falls back to entry page when no document is open", function()
            local entry = { id = "img1", title = "Map", href = "map.jpg", page = 12 }
            local res = img_mgr:resolveImagePage(nil, entry)
            assert.are.equal(12, res)
        end)
    end)

    describe("buildSpinePageMap", function()
        it("accurately anchors spine items from TOC CFI xpointers and interpolates", function()
            local spine_items = { "cover.xhtml", "map.xhtml", "title.xhtml", "ch01.xhtml", "ch02.xhtml" }
            local manifest_id_to_spine = { cover = 1, map = 2, title = 3, ch01 = 4, ch02 = 5 }
            local mock_ui = {
                document = {
                    getToc = function()
                        return {
                            { title = "Cover", page = 1, xpointer = "/6/2[cover]!" },
                            { title = "Map of Wilderland", page = 4, xpointer = "/6/4[map]!" },
                            { title = "Chapter 1", page = 10, xpointer = "/6/8[ch01]!" },
                            { title = "Chapter 2", page = 30, xpointer = "/6/10[ch02]!" },
                        }
                    end,
                },
            }

            local map, toc = img_mgr:buildSpinePageMap(mock_ui, spine_items, manifest_id_to_spine, 300)
            assert.are.equal(1, map[1]) -- Cover is page 1
            assert.are.equal(4, map[2]) -- Map is page 4
            assert.are.equal(10, map[4]) -- Chapter 1 is page 10
            assert.are.equal(30, map[5]) -- Chapter 2 is page 30
            -- Title (spine 3) is between Spine 2 (page 4) and Spine 4 (page 10)
            assert.is_true(map[3] >= 4 and map[3] <= 10)
            assert.are.equal(4, #toc)
        end)

        it("accurately anchors spine items from file_to_toc_idx without needing CFIs", function()
            local spine_items = { "text/cover.xhtml", "text/part1.xhtml", "text/part20.xhtml", "text/part24.xhtml" }
            local file_to_toc_idx = {
                ["cover.xhtml"] = 1,
                ["part1.xhtml"] = 2,
                ["part20.xhtml"] = 20,
                ["part24.xhtml"] = 24,
            }
            local mock_ui = {
                document = {
                    getToc = function()
                        local entries = {}
                        for i = 1, 24 do entries[i] = { title = "Chapter " .. i, page = 10 * i } end
                        entries[1] = { title = "Cover", page = 1 }
                        entries[2] = { title = "Chapter 1", page = 2 }
                        entries[20] = { title = "Chapter 19", page = 470 }
                        entries[24] = { title = "Chapter 24", page = 488 }
                        return entries
                    end,
                },
            }

            local map, toc = img_mgr:buildSpinePageMap(mock_ui, spine_items, {}, 516, file_to_toc_idx)
            assert.are.equal(1, map[1]) -- Cover is page 1
            assert.are.equal(2, map[2]) -- part1 is page 2
            assert.are.equal(470, map[3]) -- part20 is page 470
            assert.are.equal(488, map[4]) -- part24 is page 488
        end)
    end)

    describe("extractImageToFile", function()
        it("returns nil and does not accept empty 0-byte cached files", function()
            local empty_file = "/tmp/koreader/empty_img.jpg"
            local f = io.open(empty_file, "w")
            f:close()

            local img = {
                id = "test_empty_1",
                href = "test_empty.jpg",
                cached_file = empty_file,
            }
            local result = img_mgr:extractImageToFile("/tmp/nonexistent.epub", img)
            assert.is_nil(result)
        end)

        it("returns cached_file if non-empty file exists", function()
            local valid_file = "/tmp/koreader/valid_img.jpg"
            local f = io.open(valid_file, "w")
            f:write("dummy-image-bytes")
            f:close()

            local img = {
                id = "test_valid_1",
                href = "test_valid.jpg",
                cached_file = valid_file,
            }
            local result = img_mgr:extractImageToFile("/tmp/nonexistent.epub", img)
            assert.are.equal(valid_file, result)
        end)
    end)
end)
