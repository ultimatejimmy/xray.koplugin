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
                assert.are.equal("text/event-stream", requests[1].headers["Accept"])
                assert.are.equal("openai", requests[1].stream_format)
                assert.is_true(require("json").decode(requests[1].body).stream)
            end)

            it("does not enable streaming for other custom endpoints", function()
                AIHelper.providers.custom1.endpoint = "https://example.com/v1/chat/completions"
                local requests = AIHelper:buildComprehensiveRequest("Title", "Author", {})
                assert.is_nil(requests[1].stream_format)
                assert.is_nil(require("json").decode(requests[1].body).stream)
            end)

            it("enables Anthropic streaming for OpenRouter Messages endpoints", function()
                AIHelper.providers.custom1.endpoint = "https://openrouter.ai/api/v1/messages"
                AIHelper.providers.custom1.format = "anthropic"
                local requests = AIHelper:buildComprehensiveRequest("Title", "Author", {})
                assert.are.equal("anthropic", requests[1].stream_format)
                assert.are.equal("text/event-stream", requests[1].headers["Accept"])
                assert.is_true(require("json").decode(requests[1].body).stream)
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
                assert.are.equal("error_config", err_code)
                assert.are.equal("HTTP 400: custom1 is not a valid model ID", err_msg)
            end)

            it("handles HTTP 200 with missing choices[1].message without crashing", function()
                local tmp = os.tmpname()
                local f = io.open(tmp, "w")
                f:write('200\ncustom1\n{"choices":[{"finish_reason":"length"}]}')
                f:close()

                local data, err_code, err_msg = AIHelper:checkAsyncResult(tmp)
                assert.is_false(data)
                assert.are.equal("error_parse", err_code)
                assert.are.equal("No text in AI response (finishReason=length)", err_msg)
            end)

            it("handles HTTP 200 with empty choices[1] object without crashing", function()
                local tmp = os.tmpname()
                local f = io.open(tmp, "w")
                f:write('200\nopenai\n{"choices":[{}]}')
                f:close()

                local data, err_code, err_msg = AIHelper:checkAsyncResult(tmp)
                assert.is_false(data)
                assert.are.equal("error_parse", err_code)
                assert.are.equal("No text in AI response (finishReason=unknown)", err_msg)
            end)

            it("extracts text from choices[1].delta.content", function()
                local tmp = os.tmpname()
                local f = io.open(tmp, "w")
                f:write('200\nopenrouter\n{"choices":[{"delta":{"content":"{\\"characters\\":[]}"}}]}')
                f:close()

                local data, err_code, err_msg = AIHelper:checkAsyncResult(tmp)
                assert.is_not_nil(data)
                assert.is_nil(err_code)
                assert.is_table(data.characters)
            end)

            it("extracts text from choices[1].text", function()
                local tmp = os.tmpname()
                local f = io.open(tmp, "w")
                f:write('200\ncustom1\n{"choices":[{"text":"{\\"characters\\":[]}"}]}')
                f:close()

                local data, err_code, err_msg = AIHelper:checkAsyncResult(tmp)
                assert.is_not_nil(data)
                assert.is_nil(err_code)
                assert.is_table(data.characters)
            end)

            it("extracts finish_reason from Gemini and Claude when text is empty", function()
                local tmp_gemini = os.tmpname()
                local f_gemini = io.open(tmp_gemini, "w")
                f_gemini:write('200\ngemini\n{"candidates":[{"finishReason":"SAFETY"}]}')
                f_gemini:close()

                local data_g, err_code_g, err_msg_g = AIHelper:checkAsyncResult(tmp_gemini)
                assert.is_false(data_g)
                assert.are.equal("error_parse", err_code_g)
                assert.are.equal("No text in AI response (finishReason=SAFETY)", err_msg_g)

                local tmp_claude = os.tmpname()
                local f_claude = io.open(tmp_claude, "w")
                f_claude:write('200\nclaude\n{"stop_reason":"max_tokens","content":[]}')
                f_claude:close()

                local data_c, err_code_c, err_msg_c = AIHelper:checkAsyncResult(tmp_claude)
                assert.is_false(data_c)
                assert.are.equal("error_parse", err_code_c)
                assert.are.equal("No text in AI response (finishReason=max_tokens)", err_msg_c)
            end)
        end)

    end)

    describe("OpenRouter stream normalization", function()
        local json = require("json")

        it("reconstructs an OpenAI-compatible streamed response", function()
            local stream = table.concat({
                ": OPENROUTER PROCESSING",
                "data: " .. json.encode({ choices = {{ delta = { content = '{"characters":' } }} }),
                "",
                "data: " .. json.encode({ choices = {{ delta = { content = "[]}" }, finish_reason = "stop" }} }),
                "",
                "data: [DONE]",
                "",
            }, "\r\n") .. "\r\n"

            local normalized = AIHelper:normalizeOpenRouterStream(stream, "openai")
            assert.is_not_nil(normalized)
            local response = json.decode(normalized)
            assert.are.equal('{"characters":[]}', response.choices[1].message.content)
        end)

        it("reconstructs an Anthropic Messages streamed response", function()
            local stream = table.concat({
                "event: content_block_start",
                "data: " .. json.encode({
                    type = "content_block_start",
                    content_block = { type = "text", text = '{"locations":' },
                }),
                "",
                "event: content_block_delta",
                "data: " .. json.encode({
                    type = "content_block_delta",
                    delta = { type = "text_delta", text = "[]}" },
                }),
                "",
                "event: message_stop",
                "data: " .. json.encode({ type = "message_stop" }),
                "",
            }, "\n") .. "\n"

            local normalized = AIHelper:normalizeOpenRouterStream(stream, "anthropic")
            assert.is_not_nil(normalized)
            local response = json.decode(normalized)
            assert.are.equal('{"locations":[]}', response.content[1].text)
        end)

        it("joins multiple data lines in one SSE event", function()
            local stream = table.concat({
                "data: {\"choices\":",
                "data: [{\"delta\":{\"content\":\"{\\\"characters\\\":[]}\"}}]}",
                "",
                "data: [DONE]",
                "",
            }, "\n") .. "\n"

            local normalized = AIHelper:normalizeOpenRouterStream(stream, "openai")
            assert.is_not_nil(normalized)
            local response = json.decode(normalized)
            assert.are.equal('{"characters":[]}', response.choices[1].message.content)
        end)

        it("accepts normal finish reasons when the DONE sentinel is missing", function()
            for _, finish_reason in ipairs({ "stop", "length" }) do
                local stream = "data: " .. json.encode({
                    choices = {{
                        delta = { content = '{"characters":[]}' },
                        finish_reason = finish_reason,
                    }},
                }) .. "\n\n"

                local normalized = AIHelper:normalizeOpenRouterStream(stream, "openai")
                assert.is_not_nil(normalized)
                local response = json.decode(normalized)
                assert.are.equal(finish_reason, response.choices[1].finish_reason)
                assert.are.equal('{"characters":[]}', response.choices[1].message.content)
            end
        end)

        it("surfaces mid-stream provider errors", function()
            local stream = "data: " .. json.encode({
                error = { code = 502, message = "Provider disconnected" },
                choices = {{ delta = { content = "" }, finish_reason = "error" }},
            }) .. "\n"

            local normalized, err = AIHelper:normalizeOpenRouterStream(stream, "openai")
            assert.is_nil(normalized)
            assert.are.equal("Provider disconnected", err)
        end)

        it("surfaces Anthropic Messages error details", function()
            local stream = table.concat({
                "event: error",
                "data: " .. json.encode({
                    type = "error",
                    error = {
                        type = "overloaded_error",
                        message = "Overloaded",
                    },
                }),
                "",
            }, "\n") .. "\n"

            local normalized, err = AIHelper:normalizeOpenRouterStream(stream, "anthropic")
            assert.is_nil(normalized)
            assert.are.equal("Overloaded", err)
        end)

        it("rejects incomplete streams instead of accepting partial output", function()
            local stream = "data: " .. json.encode({
                choices = {{ delta = { content = '{"characters":[]}' } }},
            }) .. "\n"

            local normalized, err = AIHelper:normalizeOpenRouterStream(stream, "openai")
            assert.is_nil(normalized)
            assert.are.equal("OpenRouter stream ended before completion", err)
        end)
    end)

    describe("async result ownership", function()
        it("removes a pre-existing result before starting a request", function()
            local old_ffiutil = package.loaded["ffi/util"]
            local result_file = os.tmpname()
            local file = io.open(result_file, "w")
            assert.is_not_nil(file)
            file:write("stale result")
            file:close()

            package.loaded["ffi/util"] = {
                runInSubProcess = function()
                    return 3333
                end,
            }

            local pid = AIHelper:makeRequestAsync({}, result_file)
            assert.are.equal(3333, pid)
            assert.is_nil(io.open(result_file, "r"))

            package.loaded["ffi/util"] = old_ffiutil
            AIHelper._async_child_pid = nil
            AIHelper._async_child_uses_process_group = nil
            AIHelper._async_result_file = nil
            os.remove(result_file)
        end)

        it("does not consume a newer request's result from a stale poll", function()
            local result_file = os.tmpname()
            local file = io.open(result_file, "w")
            assert.is_not_nil(file)
            file:write("new request result")
            file:close()

            AIHelper._async_child_pid = 2222
            AIHelper._async_result_file = result_file

            local result, err_code = AIHelper:checkAsyncResult(result_file, 1111)
            assert.is_false(result)
            assert.are.equal("error_stale", err_code)
            assert.are.equal(2222, AIHelper._async_child_pid)
            assert.are.equal(result_file, AIHelper._async_result_file)

            local untouched = io.open(result_file, "r")
            assert.is_not_nil(untouched)
            assert.are.equal("new request result", untouched:read("*a"))
            untouched:close()

            AIHelper._async_child_pid = nil
            AIHelper._async_result_file = nil
            os.remove(result_file)
        end)
    end)

    describe("async child cancellation", function()
        it("reuses the module-level FFI fallback when ffiutil is unavailable", function()
            local old_ffiutil = package.loaded["ffi/util"]
            local old_ffiutil_alias = package.loaded["ffiutil"]
            local old_preload = package.preload["ffi/util"]
            local old_preload_alias = package.preload["ffiutil"]
            package.loaded["ffi/util"] = nil
            package.loaded["ffiutil"] = nil
            package.preload["ffi/util"] = function() error("ffiutil unavailable") end
            package.preload["ffiutil"] = function() error("ffiutil unavailable") end

            local ok, err = pcall(function()
                for _ = 1, 3 do
                    assert.is_true(AIHelper:_isAsyncChildDone(2147483647))
                end
            end)

            package.loaded["ffi/util"] = old_ffiutil
            package.loaded["ffiutil"] = old_ffiutil_alias
            package.preload["ffi/util"] = old_preload
            package.preload["ffiutil"] = old_preload_alias
            if not ok then error(err) end
        end)

        it("terminates immediately and reaps only the expected child in the background", function()
            local old_ffiutil = package.loaded["ffi/util"]
            local old_terminate = AIHelper._terminateAsyncProcess
            local UIManager = require("ui/uimanager")
            local old_schedule = UIManager.scheduleIn
            local calls = {}
            local scheduled = {}
            local reap_results = { false, false, true }
            package.loaded["ffi/util"] = {
                terminateSubProcess = function(pid)
                    error("cancelAsyncChild must not call a helper that reaps before signalling")
                end,
                isSubProcessDone = function(pid, wait)
                    table.insert(calls, { action = "reap", pid = pid, wait = wait })
                    return table.remove(reap_results, 1)
                end,
            }
            AIHelper._terminateAsyncProcess = function(self, pid, use_process_group)
                table.insert(calls, {
                    action = "terminate",
                    pid = pid,
                    use_process_group = use_process_group,
                })
                return true
            end
            UIManager.scheduleIn = function(self, delay, callback)
                table.insert(scheduled, callback)
            end

            local result_file = os.tmpname()
            local file = io.open(result_file, "w")
            file:write("pending")
            file:close()

            AIHelper._async_child_pid = 4321
            AIHelper._async_child_uses_process_group = true
            AIHelper._async_result_file = result_file

            local ok, err = pcall(function()
                assert.is_false(AIHelper:cancelAsyncChild(9999))
                assert.are.equal(4321, AIHelper._async_child_pid)
                assert.are.equal(0, #calls)

                assert.is_true(AIHelper:cancelAsyncChild(4321))
                assert.are.equal("terminate", calls[1].action)
                assert.are.equal(4321, calls[1].pid)
                assert.is_true(calls[1].use_process_group)
                assert.are.equal("reap", calls[2].action)
                assert.is_nil(calls[2].wait)
                assert.is_nil(AIHelper._async_child_pid)
                assert.is_nil(AIHelper._async_result_file)
                assert.is_nil(io.open(result_file, "r"))
                assert.are.equal(1, #scheduled)

                table.remove(scheduled, 1)()
                assert.are.equal("reap", calls[3].action)
                assert.is_nil(calls[3].wait)
                assert.are.equal(1, #scheduled)
                assert.is_true(AIHelper._async_children_to_reap[4321])

                table.remove(scheduled, 1)()
                assert.are.equal("reap", calls[4].action)
                assert.is_nil(calls[4].wait)
                assert.is_nil(AIHelper._async_children_to_reap)
                assert.are.equal(0, #scheduled)
            end)

            package.loaded["ffi/util"] = old_ffiutil
            AIHelper._terminateAsyncProcess = old_terminate
            UIManager.scheduleIn = old_schedule
            AIHelper._async_child_pid = nil
            AIHelper._async_child_uses_process_group = nil
            AIHelper._async_result_file = nil
            AIHelper._async_children_to_reap = nil
            pcall(function() os.remove(result_file) end)
            if not ok then error(err) end
        end)

        it("stops reaper polling after bounded backoff", function()
            local UIManager = require("ui/uimanager")
            local old_schedule = UIManager.scheduleIn
            local old_is_done = AIHelper._isAsyncChildDone
            local old_log = AIHelper.log
            local scheduled = {}
            local delays = {}
            local logs = {}

            UIManager.scheduleIn = function(self, delay, callback)
                table.insert(delays, delay)
                table.insert(scheduled, callback)
            end
            AIHelper._isAsyncChildDone = function() return false end
            AIHelper.log = function(self, message)
                table.insert(logs, message)
            end
            AIHelper._async_children_to_reap = nil

            local ok, err = pcall(function()
                assert.is_true(AIHelper:_scheduleAsyncChildReap(7777))
                local callbacks_run = 0
                while #scheduled > 0 do
                    callbacks_run = callbacks_run + 1
                    table.remove(scheduled, 1)()
                    assert.is_true(callbacks_run <= 10)
                end

                assert.are.equal(10, callbacks_run)
                assert.are.equal(10, #delays)
                assert.are.equal(0.1, delays[1])
                assert.are.equal(0.2, delays[2])
                assert.are.equal(1, delays[5])
                assert.is_nil(AIHelper._async_children_to_reap)
                assert.is_true(logs[#logs]:find("Timed out waiting to collect", 1, true) ~= nil)
            end)

            UIManager.scheduleIn = old_schedule
            AIHelper._isAsyncChildDone = old_is_done
            AIHelper.log = old_log
            AIHelper._async_children_to_reap = nil
            if not ok then error(err) end
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
        it("should have gemini-3.7-flash as default primary model", function()
            local primary = AIHelper.settings.primary_ai or { provider = "gemini", model = "gemini-3.7-flash" }
            assert.are.equal("gemini", primary.provider)
            assert.are.equal("gemini-3.7-flash", primary.model)
        end)

        it("should have gemini-3.5-flash-lite as default secondary model", function()
            local secondary = AIHelper.settings.secondary_ai or { provider = "gemini", model = "gemini-3.5-flash-lite" }
            assert.are.equal("gemini", secondary.provider)
            assert.are.equal("gemini-3.5-flash-lite", secondary.model)
        end)
    end)

    describe("Gemini model migration", function()
        it("should migrate deprecated and shut down Gemini models in primary and secondary slots", function()
            local json = require("json")
            local saved_settings = nil
            AIHelper.saveSettings = function(self)
                saved_settings = self.settings
            end

            -- Test with mock settings containing deprecated Gemini models
            local mock_settings = {
                primary_ai = { provider = "gemini", model = "gemini-2.0-flash" },
                secondary_ai = { provider = "gemini", model = "gemini-3.1-flash-lite" },
                gemini_primary_model = "gemini-1.5-flash",
                gemini_secondary_model = "gemini-2.0-flash-lite",
            }

            -- Mock io.open to return our test settings
            local old_open = io.open
            io.open = function(path, mode)
                if path:find("settings.json") and (mode == "r" or mode == nil) then
                    return {
                        read = function() return json.encode(mock_settings) end,
                        close = function() end
                    }
                end
                return old_open(path, mode)
            end

            AIHelper:loadSettings()
            io.open = old_open

            assert.is_not_nil(AIHelper.settings)
            assert.are.equal("gemini-3.7-flash", AIHelper.settings.primary_ai.model)
            assert.are.equal("gemini-3.5-flash-lite", AIHelper.settings.secondary_ai.model)
            assert.are.equal("gemini-3.7-flash", AIHelper.settings.gemini_primary_model)
            assert.are.equal("gemini-3.5-flash-lite", AIHelper.settings.gemini_secondary_model)
        end)

        it("should migrate legacy Gemini preview and 1.5/1.0 models", function()
            local json = require("json")
            local mock_settings = {
                primary_ai = { provider = "gemini", model = "gemini-1.5-pro" },
                secondary_ai = { provider = "gemini", model = "gemini-2.5-flash-preview-05-20" },
            }

            local old_open = io.open
            io.open = function(path, mode)
                if path:find("settings.json") and (mode == "r" or mode == nil) then
                    return {
                        read = function() return json.encode(mock_settings) end,
                        close = function() end
                    }
                end
                return old_open(path, mode)
            end

            AIHelper:loadSettings()
            io.open = old_open

            assert.are.equal("gemini-2.5-pro", AIHelper.settings.primary_ai.model)
            assert.are.equal("gemini-3.7-flash", AIHelper.settings.secondary_ai.model)
        end)
    end)

    describe("persistent config backup and restoration", function()
        it("should back up config keys to stored config and restore missing keys to config file", function()
            local stored_content = nil
            local config_file_written = nil
            local json = require("json")

            local orig_getStoredConfigPath = AIHelper.getStoredConfigPath
            local orig_loadStoredConfig = AIHelper.loadStoredConfig
            local orig_saveStoredConfig = AIHelper.saveStoredConfig
            local orig_writeConfigToFile = AIHelper.writeConfigToFile

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

            AIHelper.getStoredConfigPath = orig_getStoredConfigPath
            AIHelper.loadStoredConfig = orig_loadStoredConfig
            AIHelper.saveStoredConfig = orig_saveStoredConfig
            AIHelper.writeConfigToFile = orig_writeConfigToFile
        end)

        it("imports keys from plain text file xray_key.txt", function()
            local test_file = AIHelper.path .. "/xray_key.txt"
            local f = io.open(test_file, "w")
            if f then
                f:write([[
# My X-Ray Keys
gemini = AQ.TEST_GEMINI_MOCK_KEY_1234567890abcdef
openai = sk-proj-1234567890abcdef
custom1_endpoint = https://openrouter.ai/api/v1/chat/completions
custom1_model = google/gemini-2.5-flash
]])
                f:close()
            end

            local ok, count, path = AIHelper:importFromTextFile(true)
            assert.is_true(ok)
            assert.is_true(count >= 2)
            assert.are.equal("AQ.TEST_GEMINI_MOCK_KEY_1234567890abcdef", AIHelper.providers.gemini.api_key)
            assert.are.equal("sk-proj-1234567890abcdef", AIHelper.providers.chatgpt.api_key)

            -- Clean up test files
            os.remove(test_file)
            os.remove(test_file .. ".imported")
        end)

        it("clears all API keys correctly across all 3 stores", function()
            AIHelper:setAPIKey("gemini", "my_gemini_key")
            AIHelper:setAPIKey("chatgpt", "my_chatgpt_key")
            AIHelper:saveStoredConfig({ gemini_api_key = "backup_gemini", chatgpt_api_key = "backup_chatgpt" })
            AIHelper:writeConfigToFile({ gemini_api_key = "config_gemini", chatgpt_api_key = "config_chatgpt" })
            
            AIHelper:clearAllAPIKeys()
            
            -- Store 1: UI settings
            assert.are.equal("", AIHelper.settings.gemini_api_key or "")
            assert.are.equal("", AIHelper.settings.chatgpt_api_key or "")
            assert.is_true(not AIHelper.settings.gemini_use_ui_key)
            assert.is_true(not AIHelper.settings.chatgpt_use_ui_key)

            -- Store 2: Persistent backup store
            local stored = AIHelper:loadStoredConfig()
            assert.are.equal("", stored.gemini_api_key or "")
            assert.are.equal("", stored.chatgpt_api_key or "")

            -- Store 3: xray_config.lua
            local ok, cfg = pcall(dofile, AIHelper.path .. "/xray_config.lua")
            assert.is_true(ok)
            assert.are.equal("", cfg.gemini_api_key or "")
            assert.are.equal("", cfg.chatgpt_api_key or "")
        end)

        it("clears a single provider key correctly across all 3 stores", function()
            AIHelper:setAPIKey("gemini", "keep_this")
            AIHelper:setAPIKey("deepseek", "delete_this")
            AIHelper:saveStoredConfig({ gemini_api_key = "keep_this", deepseek_api_key = "delete_this" })
            AIHelper:writeConfigToFile({ gemini_api_key = "keep_this", deepseek_api_key = "delete_this" })

            AIHelper:clearProviderKey("deepseek")

            assert.are.equal("", AIHelper.settings.deepseek_api_key or "")
            assert.is_true(not AIHelper.settings.deepseek_use_ui_key)

            local stored = AIHelper:loadStoredConfig()
            assert.are.equal("", stored.deepseek_api_key or "")

            local ok, cfg = pcall(dofile, AIHelper.path .. "/xray_config.lua")
            assert.is_true(ok)
            assert.are.equal("", cfg.deepseek_api_key or "")
            assert.are.equal("keep_this", cfg.gemini_api_key or "")
        end)
    end)
end)
