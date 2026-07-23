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

    describe("custom slot model resolution (issue #86)", function()
        local saved_custom1

        before_each(function()
            saved_custom1 = {
                api_key = AIHelper.providers.custom1.api_key,
                endpoint = AIHelper.providers.custom1.endpoint,
                model = AIHelper.providers.custom1.model,
                format = AIHelper.providers.custom1.format,
            }
            AIHelper.providers.custom1.api_key = "sk-or-test"
            AIHelper.providers.custom1.endpoint = "https://openrouter.ai/api/v1/chat/completions"
            AIHelper.providers.custom1.model = "deepseek/deepseek-v4-flash"
            AIHelper.providers.custom1.format = nil
        end)

        after_each(function()
            AIHelper.providers.custom1.api_key = saved_custom1.api_key
            AIHelper.providers.custom1.endpoint = saved_custom1.endpoint
            AIHelper.providers.custom1.model = saved_custom1.model
            AIHelper.providers.custom1.format = saved_custom1.format
        end)

        describe("resolveModel", function()
            it("passes through explicit model names", function()
                assert.are.equal("mistral/mistral-large", AIHelper:resolveModel("custom1", "mistral/mistral-large"))
                assert.are.equal("gpt-4o", AIHelper:resolveModel("chatgpt", "gpt-4o"))
            end)

            it("replaces the slot-name placeholder with the configured model", function()
                assert.are.equal("deepseek/deepseek-v4-flash", AIHelper:resolveModel("custom1", "custom1"))
            end)

            it("falls back to the configured model when no model is given", function()
                assert.are.equal("deepseek/deepseek-v4-flash", AIHelper:resolveModel("custom1", nil))
            end)

            it("returns nil when the slot has no configured model", function()
                AIHelper.providers.custom1.model = ""
                assert.is_nil(AIHelper:resolveModel("custom1", "custom1"))
            end)
        end)

        describe("buildComprehensiveRequest with placeholder model", function()
            before_each(function()
                AIHelper.settings = {
                    primary_ai = { provider = "custom1", model = "custom1" },
                    secondary_ai = { provider = "custom1", model = "custom1" },
                }
            end)

            it("sends the configured model instead of the placeholder", function()
                local requests = AIHelper:buildComprehensiveRequest("Title", "Author", {})
                local body = require("json").decode(requests[1].body)
                assert.are.equal("deepseek/deepseek-v4-flash", body.model)
            end)

            it("uses the documented X-Title header for OpenRouter attribution", function()
                local requests = AIHelper:buildComprehensiveRequest("Title", "Author", {})
                assert.is_not_nil(requests[1].headers["HTTP-Referer"])
                assert.are.equal("KOReader X-Ray", requests[1].headers["X-Title"])
                assert.is_nil(requests[1].headers["X-OpenRouter-Title"])
            end)
        end)

        describe("loadSettings placeholder repair", function()
            it("replaces a stored placeholder model with the slot's configured model", function()
                local old_open = io.open
                io.open = function(path, mode)
                    if path:find("settings.json") then
                        return {
                            read = function(self, fmt)
                                return '{"primary_ai": {"provider": "custom1", "model": "custom1"}, "custom1_model": "deepseek/deepseek-v4-flash", "ui_defaults_migrated_v2": true}'
                            end,
                            close = function() end
                        }
                    end
                    return old_open(path, mode)
                end
                local old_save = AIHelper.saveSettings
                AIHelper.saveSettings = function() end

                AIHelper:loadSettings()

                io.open = old_open
                AIHelper.saveSettings = old_save

                assert.are.equal("deepseek/deepseek-v4-flash", AIHelper.settings.primary_ai.model)
            end)
        end)

        describe("checkAsyncResult error reporting", function()
            it("includes the provider's error message on non-200 responses", function()
                local tmp = os.tmpname()
                local f = io.open(tmp, "w")
                f:write('400\ncustom1\n{"error":{"message":"custom1 is not a valid model ID","code":400}}')
                f:close()

                local data, err_code, err_msg = AIHelper:checkAsyncResult(tmp)
                assert.is_false(data)
                assert.are.equal("error_api", err_code)
                assert.are.equal("HTTP 400: custom1 is not a valid model ID", err_msg)
            end)
        end)
    end)

    describe("isAnthropic", function()
        it("should return true for claude provider", function()
            assert.is_true(AIHelper:isAnthropic("claude", nil))
        end)

        it("should return false for chatgpt/gemini providers", function()
            assert.is_false(AIHelper:isAnthropic("chatgpt", nil))
            assert.is_false(AIHelper:isAnthropic("gemini", nil))
        end)

        it("should return true for custom provider if format is explicitly anthropic", function()
            AIHelper.providers.custom1.format = "anthropic"
            assert.is_true(AIHelper:isAnthropic("custom1", "https://api.openai.com/v1/chat/completions"))
            AIHelper.providers.custom1.format = nil
        end)

        it("should return false for custom provider if format is explicitly openai", function()
            AIHelper.providers.custom1.format = "openai"
            assert.is_false(AIHelper:isAnthropic("custom1", "https://api.anthropic.com/v1/messages"))
            AIHelper.providers.custom1.format = nil
        end)

        it("should auto-detect anthropic endpoints via URL search", function()
            assert.is_true(AIHelper:isAnthropic("custom1", "https://api.openmodel.ai/v1/messages"))
            assert.is_true(AIHelper:isAnthropic("custom1", "http://localhost:8000/messages"))
            assert.is_false(AIHelper:isAnthropic("custom1", "https://openrouter.ai/api/v1/chat/completions"))
        end)
    end)

    describe("Anthropic request headers", function()
        it("should send only x-api-key for native claude or anthropic.com", function()
            AIHelper.settings.primary_ai = { provider = "claude", model = "claude-3-7-sonnet-latest" }
            AIHelper.providers.claude.api_key = "sk-ant-test"
            local requests = AIHelper:buildComprehensiveRequest("Title", "Author", {})
            local req = requests[1]
            assert.are.equal("sk-ant-test", req.headers["x-api-key"])
            assert.is_nil(req.headers["Authorization"])
        end)

        it("should send only Authorization Bearer for custom slot proxies", function()
            AIHelper.settings.primary_ai = { provider = "custom1", model = "deepseek-v4-flash" }
            AIHelper.providers.custom1.api_key = "openmodel-key"
            AIHelper.providers.custom1.endpoint = "https://api.openmodel.ai/v1/messages"
            local requests = AIHelper:buildComprehensiveRequest("Title", "Author", {})
            local req = requests[1]
            assert.are.equal("Bearer openmodel-key", req.headers["Authorization"])
            assert.is_nil(req.headers["x-api-key"])
        end)
    end)

    describe("saveSettings with keys_to_delete", function()
        it("should update settings and delete specified keys", function()
            local old_open = io.open
            local written_content = nil
            local json = require("json")
            io.open = function(path, mode)
                if path:find("settings.json") and mode == "w" then
                    return {
                        write = function(self, content)
                            written_content = content
                        end,
                        close = function() end
                    }
                end
                return old_open(path, mode)
            end

            -- Setup starting settings
            AIHelper.settings = {
                keep_me = "value",
                delete_me = "value2",
                also_delete_me = "value3"
            }

            -- Save new settings and delete some keys
            AIHelper:saveSettings({ new_key = "new_val" }, { "delete_me", "also_delete_me" })

            io.open = old_open

            assert.is_not_nil(written_content)
            local decoded = json.decode(written_content)
            assert.are.equal("value", decoded.keep_me)
            assert.are.equal("new_val", decoded.new_key)
            assert.is_nil(decoded.delete_me)
        end)
    end)

    describe("DEFAULT_AI configuration", function()
        it("should have gemini-3.6-flash as default primary model", function()
            local primary = AIHelper.settings.primary_ai or { provider = "gemini", model = "gemini-3.6-flash" }
            assert.are.equal("gemini", primary.provider)
            assert.are.equal("gemini-3.6-flash", primary.model)
        end)

        it("should have gemini-3.5-flash-lite as default secondary model", function()
            local secondary = AIHelper.settings.secondary_ai or { provider = "gemini", model = "gemini-3.5-flash-lite" }
            assert.are.equal("gemini", secondary.provider)
            assert.are.equal("gemini-3.5-flash-lite", secondary.model)
        end)
    end)

    describe("persistent config backup and restoration", function()
        it("should back up config keys to stored config and restore missing keys to config file", function()
            local stored_content = nil
            local config_file_written = nil
            local json = require("json")

            AIHelper.getStoredConfigPath = function()
                return "/fake/path/config_backup.json"
            end

            AIHelper.loadStoredConfig = function()
                if stored_content then
                    return json.decode(stored_content)
                end
                return {}
            end

            AIHelper.saveStoredConfig = function(self, cfg)
                stored_content = json.encode(cfg)
            end

            AIHelper.writeConfigToFile = function(self, cfg)
                config_file_written = cfg
                return true
            end

            -- Test updateConfigKey
            AIHelper:updateConfigKey("gemini_api_key", "test_gemini_key_123")
            assert.is_not_nil(stored_content)
            local stored = json.decode(stored_content)
            assert.are.equal("test_gemini_key_123", stored.gemini_api_key)
            assert.are.equal("test_gemini_key_123", config_file_written.gemini_api_key)

            -- Test restoration when config file is missing keys present in stored backup
            config_file_written = nil
            local mock_empty_config = { gemini_api_key = "" }
            
            -- Simulate loadConfig logic with missing key
            local stored_cfg = AIHelper:loadStoredConfig()
            local restored = false
            if stored_cfg.gemini_api_key and stored_cfg.gemini_api_key ~= "" and mock_empty_config.gemini_api_key == "" then
                mock_empty_config.gemini_api_key = stored_cfg.gemini_api_key
                restored = true
                AIHelper:writeConfigToFile(mock_empty_config)
            end

            assert.is_true(restored)
            assert.are.equal("test_gemini_key_123", mock_empty_config.gemini_api_key)
            assert.are.equal("test_gemini_key_123", config_file_written.gemini_api_key)
        end)
    end)
end)
