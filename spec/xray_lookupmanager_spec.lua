-- xray_lookupmanager_spec.lua
require("spec/spec_helper")

describe("xray_lookupmanager", function()
    local LookupManager
    local lm
    local plugin

    setup(function()
        LookupManager = require("xray_lookupmanager")
        plugin = createMockPlugin()
        plugin.characters = {}
        plugin.historical_figures = {}
        plugin.locations = {}
        lm = LookupManager:new(plugin)
    end)

    describe("normalize", function()
        it("should lowercase and strip non-alphanumeric at ends", function()
            assert.are.equal("hello", lm:normalize("...Hello!"))
            assert.are.equal("john's", lm:normalize("John's"))
            assert.are.equal("watson", lm:normalize("Watson,"))
        end)

        it("should normalize Cyrillic Russian text with and without punctuation", function()
            assert.are.equal("раскольников", lm:normalize("Раскольников"))
            assert.are.equal("раскольников", lm:normalize("«Раскольников»"))
            assert.are.equal("раскольников", lm:normalize("“Раскольников”"))
            assert.are.equal("раскольников", lm:normalize("...Раскольников!"))
            assert.are.equal("родион раскольников", lm:normalize("Родион Раскольников"))
            assert.are.equal("война и мир", lm:normalize("«Война и мир»"))
        end)

        it("should normalize CJK and Latin-extended text", function()
            assert.are.equal("阿q", lm:normalize("「阿Q」"))
            assert.are.equal("红楼梦", lm:normalize("《红楼梦》"))
            assert.are.equal("émile zola", lm:normalize("“Émile Zola”"))
            assert.are.equal("łódź", lm:normalize("Łódź,"))
        end)
    end)

    describe("lookupAll", function()
        before_each(function()
            plugin.characters = {
                { name = "Sherlock Holmes", _norm_name = "sherlock holmes", aliases = {"Sherlock"}, _norm_aliases = {"sherlock"} },
                { name = "John Watson", _norm_name = "john watson" }
            }
            plugin.locations = {
                { name = "221B Baker Street", _norm_name = "221b baker street" }
            }
        end)

        it("should find exact match", function()
            local results = lm:lookupAll("John Watson")
            assert.are.equal(1, #results)
            assert.are.equal("John Watson", results[1].item.name)
            assert.are.equal(100, results[1].score)
        end)

        it("should find exact alias match", function()
            local results = lm:lookupAll("Sherlock")
            assert.are.equal(1, #results)
            assert.are.equal("Sherlock Holmes", results[1].item.name)
            assert.are.equal(95, results[1].score)
        end)

        it("should find contains match", function()
            local results = lm:lookupAll("Holmes")
            assert.are.equal(1, #results)
            assert.are.equal("Sherlock Holmes", results[1].item.name)
            assert.are.equal(50, results[1].score)
        end)

        it("should find contained match", function()
            local results = lm:lookupAll("John Watson and someone else")
            assert.are.equal(1, #results)
            assert.are.equal("John Watson", results[1].item.name)
            assert.are.equal(50, results[1].score)
        end)

        it("should prioritize better matches", function()
            -- Add a character whose alias is a substring of another
            table.insert(plugin.characters, { name = "Holmes Senior", _norm_name = "holmes senior" })
            
            local results = lm:lookupAll("Sherlock Holmes")
            -- "Sherlock Holmes" matches exactly.
            -- "Holmes Senior" might match partially (query contains "holmes").
            assert.are.equal(100, results[1].score)
            assert.are.equal("Sherlock Holmes", results[1].item.name)
        end)

        it("should filter out partial matches when an exact match is present", function()
            -- Add "Coherence" which is a substring/partial match
            plugin.terms = {
                { name = "associative coherence", _norm_name = "associative coherence" },
                { name = "Coherence", _norm_name = "coherence" }
            }
            local results = lm:lookupAll("associative coherence")
            -- Should only return "associative coherence" (score 100), not "Coherence" (score 30)
            assert.are.equal(1, #results)
            assert.are.equal("associative coherence", results[1].item.name)
            assert.are.equal(100, results[1].score)
        end)

        it("should correctly lookup Cyrillic characters, aliases, and inflected forms (Issue #116)", function()
            plugin.characters = {
                { name = "Родион Раскольников", aliases = {"Раскольников", "Родя"} },
                { name = "Софья Семёновна Мармеладова", aliases = {"Соня", "Сонечка"} }
            }
            plugin.historical_figures = {
                { name = "Наполеон I Бонапарт", aliases = {"Наполеон"} }
            }
            plugin.locations = {
                { name = "Санкт-Петербург", aliases = {"Петербург", "Питер"} }
            }
            plugin.terms = {
                { name = "Жёлтый билет" }
            }

            -- Exact match on full Cyrillic name
            local r1 = lm:lookupAll("Родион Раскольников")
            assert.are.equal(1, #r1)
            assert.are.equal("Родион Раскольников", r1[1].item.name)
            assert.are.equal(100, r1[1].score)

            -- Exact match on Cyrillic alias
            local r2 = lm:lookupAll("Раскольников")
            assert.are.equal(1, #r2)
            assert.are.equal("Родион Раскольников", r2[1].item.name)
            assert.are.equal(95, r2[1].score)

            -- Cyrillic alias with Russian guillemets «...»
            local r3 = lm:lookupAll("«Раскольников»")
            assert.are.equal(1, #r3)
            assert.are.equal("Родион Раскольников", r3[1].item.name)
            assert.are.equal(95, r3[1].score)

            -- Short nickname alias
            local r4 = lm:lookupAll("Родя")
            assert.are.equal(1, #r4)
            assert.are.equal("Родион Раскольников", r4[1].item.name)
            assert.are.equal(95, r4[1].score)

            -- Inflected Russian form in text matching base alias
            local r5 = lm:lookupAll("Раскольникова")
            assert.are.equal(1, #r5)
            assert.are.equal("Родион Раскольников", r5[1].item.name)
            assert.are.equal(40, r5[1].score)

            -- Historical figure in Russian
            local r6 = lm:lookupAll("Наполеон")
            assert.are.equal(1, #r6)
            assert.are.equal("Наполеон I Бонапарт", r6[1].item.name)
            assert.are.equal(95, r6[1].score)

            -- Location in Russian
            local r7 = lm:lookupAll("Питер")
            assert.are.equal(1, #r7)
            assert.are.equal("Санкт-Петербург", r7[1].item.name)
            assert.are.equal(95, r7[1].score)

            -- Term in Russian with 'ё'
            local r8 = lm:lookupAll("жёлтый билет")
            assert.are.equal(1, #r8)
            assert.are.equal("Жёлтый билет", r8[1].item.name)
            assert.are.equal(100, r8[1].score)
        end)
    end)

    describe("handleLookup table text payloads", function()
        before_each(function()
            plugin.characters = {
                { name = "Sherlock Holmes", aliases = {"Sherlock"} },
                { name = "John Watson" }
            }
        end)

        it("unwraps table text payloads and looks up correctly", function()
            local shown = false
            plugin.showCharacterDetails = function() shown = true end
            lm:handleLookup({ text = "John Watson" }, 1, 2)
            assert.is_true(shown)
        end)

        it("unwraps Cyrillic table text payload and shows character details", function()
            plugin.characters = {
                { name = "Родион Раскольников", aliases = {"Раскольников"} }
            }
            local shown_item = nil
            plugin.showCharacterDetails = function(self, item) shown_item = item end
            lm:handleLookup({ text = "Раскольников" }, 1, 2)
            assert.is_not_nil(shown_item)
            assert.are.equal("Родион Раскольников", shown_item.name)
        end)
    end)

    describe("showResult normalization", function()
        local called
        before_each(function()
            called = {}
            plugin.showCharacterDetails = function(self, item, opts) called.character = { item = item, opts = opts } end
            plugin.showHistoricalFigureDetails = function(self, item, opts) called.historical = { item = item, opts = opts } end
            plugin.showLocationDetails = function(self, item, opts) called.location = { item = item, opts = opts } end
            plugin.showTermDetails = function(self, item, opts) called.term = { item = item, opts = opts } end
        end)

        it("dispatches correctly for capitalized and whitespace-formatted item types", function()
            local item = { name = "Test Entity" }

            lm:showResult(item, "Character")
            assert.is_not_nil(called.character)
            assert.are.equal(item, called.character.item)
            assert.are.equal("in_text", called.character.opts.source)

            lm:showResult(item, "Historical Figure")
            assert.is_not_nil(called.historical)
            assert.are.equal(item, called.historical.item)

            lm:showResult(item, "historical")
            assert.is_not_nil(called.historical)

            lm:showResult(item, "LOCATION")
            assert.is_not_nil(called.location)

            lm:showResult(item, "Term")
            assert.is_not_nil(called.term)
        end)
    end)
end)
