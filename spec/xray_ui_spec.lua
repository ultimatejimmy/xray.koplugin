-- xray_ui_spec.lua
require("spec/spec_helper")
local xray_ui = require("xray_ui")

describe("xray_ui", function()
    local plugin

    before_each(function()
        plugin = createMockPlugin()
        -- Mix in UI methods
        for k, v in pairs(xray_ui) do
            plugin[k] = v
        end
        -- Reset UI tracker
        _G.ui_tracker.shown = {}
        _G.ui_tracker.last_shown = nil
        _G.ui_tracker.closed = {}
    end)

    describe("showLanguageSelection", function()
        it("should show a ButtonDialog with language options", function()
            plugin:showLanguageSelection()
            local last = _G.ui_tracker.last_shown
            assert.is_not_nil(last)
            assert.are.equal("ButtonDialog", last.type)
            assert.are.equal("menu_language", last.args.title)
            -- Check that we have multiple buttons
            assert.is_true(#last.args.buttons > 5)
        end)
    end)

    describe("closeAllMenus", function()
        it("should close active menus and set them to nil", function()
            plugin.char_menu = { type = "MockMenu" }
            plugin.xray_menu = { type = "MockMenu" }
            
            plugin:closeAllMenus()
            
            assert.is_nil(plugin.char_menu)
            assert.is_nil(plugin.xray_menu)
            -- Should have called UIManager:close twice for our menus
            -- Plus others in the list
            assert.is_true(#_G.ui_tracker.closed >= 2)
        end)
    end)

    describe("showCharacters", function()
        it("should show a Menu even if no characters, containing Fetch More", function()
            plugin.characters = {}
            plugin:showCharacters()
            local last = _G.ui_tracker.last_shown
            assert.are.equal("Menu", last.type)
            assert.truthy(last.args.title:find("menu_characters"))
            assert.are.equal(1, #last.args.item_table)
            assert.truthy(last.args.item_table[1].text:find("menu_fetch_more_chars"))
        end)

        it("should show a Menu if characters exist", function()
            plugin.characters = { { name = "Alice", description = "Test" } }
            plugin:showCharacters()
            local last = _G.ui_tracker.last_shown
            assert.are.equal("Menu", last.type)
            assert.truthy(last.args.title:find("menu_characters"))
            -- Verify Alice is in the menu
            local found = false
            for _, item in ipairs(last.args.item_table) do
                if item.text:find("Alice") then found = true; break end
            end
            assert.is_true(found)
        end)
    end)

    describe("showCharacterDetails", function()
        it("should show details dialog", function()
            local char = { name = "Bob", description = "A builder" }
            plugin:showCharacterDetails(char)
            local last = _G.ui_tracker.last_shown
            assert.is_not_nil(last)
            -- Based on logic, if no related entries, it shows a ConfirmBox
            assert.are.equal("ConfirmBox", last.type)
            assert.truthy(last.args.text:find("Bob"))
            assert.truthy(last.args.text:find("A builder"))
        end)
    end)

    describe("showMergeFlow", function()
        it("should show primary picker dialog", function()
            plugin.characters = { { name = "A" }, { name = "B" } }
            plugin:showMergeFlow(plugin.characters, "characters")
            local last = _G.ui_tracker.last_shown
            assert.are.equal("ButtonDialog", last.type)
            assert.are.equal("merge_pick_primary", last.args.title)
        end)
    end)

    describe("showTerms", function()
        it("should show a Menu even if no terms, containing Fetch More", function()
            plugin.terms = {}
            plugin:showTerms()
            local last = _G.ui_tracker.last_shown
            assert.are.equal("Menu", last.type)
            assert.truthy(last.args.title:find("menu_terms"))
            assert.are.equal(1, #last.args.item_table)
            assert.truthy(last.args.item_table[1].text:find("menu_fetch_more_terms"))
        end)

        it("should show a Menu if terms exist", function()
            plugin.terms = { { name = "Muggle", definition = "Non-magical person" } }
            plugin:showTerms()
            local last = _G.ui_tracker.last_shown
            assert.are.equal("Menu", last.type)
            assert.truthy(last.args.title:find("menu_terms"))
            -- Verify Muggle is in the menu
            local found = false
            for _, item in ipairs(last.args.item_table) do
                if item.text:find("Muggle") then found = true; break end
            end
            assert.is_true(found)
        end)
    end)
end)
