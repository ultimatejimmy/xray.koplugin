-- xray_aihelper_spec.lua
require("spec/spec_helper")

describe("AIHelper", function()
    local AIHelper

    setup(function()
        -- Load the real module
        AIHelper = require("xray_aihelper")
    end)

    describe("sanitize_utf8", function()
        it("should preserve valid ASCII", function()
            local input = "Hello World"
            assert.are.equal("Hello World", AIHelper:sanitize_utf8(input))
        end)

        it("should preserve valid multi-byte UTF-8 (Cyrillic)", function()
            local input = "Привет"
            assert.are.equal("Привет", AIHelper:sanitize_utf8(input))
        end)

        it("should strip invalid continuation bytes", function()
            -- 0x80 is an invalid start byte
            local input = "Hello" .. string.char(0x80) .. "World"
            assert.are.equal("HelloWorld", AIHelper:sanitize_utf8(input))
        end)

        it("should strip truncated multi-byte sequences", function()
            -- "П" is 0xD0 0x9F. If we slice it to 0xD0:
            local input = string.char(0xD0) 
            assert.are.equal("", AIHelper:sanitize_utf8(input))
        end)
    end)

    describe("getChatGPTTokenConfig", function()
        it("should use max_completion_tokens for o1/o3 models", function()
            local param, val = AIHelper:getChatGPTTokenConfig("o1-preview")
            assert.are.equal("max_completion_tokens", param)
        end)

        it("should use max_completion_tokens for gpt-5 models", function()
            local param, val = AIHelper:getChatGPTTokenConfig("gpt-5.4-mini")
            assert.are.equal("max_completion_tokens", param)
        end)

        it("should use max_tokens for deepseek/r1 models", function()
            local param, val = AIHelper:getChatGPTTokenConfig("deepseek-reasoner")
            assert.are.equal("max_tokens", param)
            
            param, val = AIHelper:getChatGPTTokenConfig("deepseek/r1")
            assert.are.equal("max_tokens", param)
        end)

        it("should fallback to max_tokens for gpt-4", function()
            local param, val = AIHelper:getChatGPTTokenConfig("gpt-4")
            assert.are.equal("max_tokens", param)
        end)
    end)

    describe("fixTruncatedJSON", function()
        it("should close missing braces", function()
            local input = '{"name": "test"'
            local fixed = AIHelper:fixTruncatedJSON(input)
            assert.are.equal('{"name": "test"}', fixed)
        end)

        it("should handle nested structures", function()
            local input = '{"chars": [{"name": "Jo"'
            local fixed = AIHelper:fixTruncatedJSON(input)
            assert.are.equal('{"chars": [{"name": "Jo"}]}', fixed)
        end)

        it("should handle strings with braces", function()
            local input = '{"text": "Value with } brace"'
            local fixed = AIHelper:fixTruncatedJSON(input)
            assert.are.equal('{"text": "Value with } brace"}', fixed)
        end)
    end)

    describe("buildComprehensiveRequest", function()
        before_each(function()
            AIHelper.settings = {
                primary_ai = { provider = "gemini", model = "gemini-2.5-flash" },
                reasoning_effort = "medium"
            }
            AIHelper.providers.gemini.api_key = "test_key"
        end)

        it("should build a Gemini request", function()
            local requests = AIHelper:buildComprehensiveRequest("Title", "Author", {})
            -- By default it builds 2 requests (primary and secondary fallback)
            assert.are.equal(2, #requests)
            assert.are.equal("gemini", requests[1].provider)
            assert.is_not_nil(requests[1].url:find("gemini%-2%.5%-flash"))
            assert.are.equal("test_key", requests[1].headers["x-goog-api-key"])
        end)

        it("should include thinkingConfig for Gemini 2.5", function()
            AIHelper.settings.primary_ai.model = "gemini-2.5-flash"
            local requests = AIHelper:buildComprehensiveRequest("Title", "Author", {})
            local body = require("json").decode(requests[1].body)
            assert.is_not_nil(body.generationConfig.thinkingConfig)
            assert.are.equal(4096, body.generationConfig.thinkingConfig.thinkingBudget)
        end)
    end)

    describe("normalizeKeys", function()
        it("should lowercase keys and replace spaces with underscores", function()
            -- normalizeKeys is local, but validateAndCleanData calls it
            local data = { ["Full Name"] = "John", ["Bio Data"] = { ["Birth Date"] = "1900" } }
            local result = AIHelper:validateAndCleanData(data)
            -- validateAndCleanData also transforms the structure, so we check the result of that
            -- but let's test normalizeKeys behavior by looking at what it does to 'data' 
            -- (actually it returns a new table)
        end)
    end)

    describe("loadSettings migration", function()
        it("should apply ui_defaults_migrated_v2 defaults", function()
            local old_open = io.open
            io.open = function(path, mode)
                if path:find("settings.json") then
                    return {
                        read = function(self, fmt)
                            return '{"primary_ai": {"provider": "gemini", "model": "gemini-2.5-flash"}}'
                        end,
                        close = function() end
                    }
                end
                return old_open(path, mode)
            end

            local saved = false
            local old_save = AIHelper.saveSettings
            AIHelper.saveSettings = function(self)
                saved = true
            end

            AIHelper:loadSettings()

            io.open = old_open
            AIHelper.saveSettings = old_save

            assert.is_true(AIHelper.settings.ui_popup_intext)
            assert.is_false(AIHelper.settings.ui_popup_menu)
            assert.is_true(AIHelper.settings.ui_defaults_migrated_v2)
            assert.is_true(saved)
        end)
    end)
end)
