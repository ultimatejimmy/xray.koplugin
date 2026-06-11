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
    end)
end)
