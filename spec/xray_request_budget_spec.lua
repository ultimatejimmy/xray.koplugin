require("spec/spec_helper")
local AIHelper = require("xray_aihelper")
local json = require("json")

describe("background request budgets", function()
    local helper
    before_each(function()
        helper = setmetatable({ settings = {}, log = function() end }, { __index = AIHelper })
    end)
    local function request(provider, input, book, limit)
        local req = { provider = provider, model = "test", body = input }
        req.token_budget = { book_text = book, book_limit = 800000, input_limit = limit }
        return req
    end
    it("accepts the book ceiling and rejects one token over it", function()
        local req = request("gemini", "prompt", "excerpts", 900000)
        assert.is_true(helper:checkRequestBudget(req, function(_, book) return book and 800000 or 810000 end))
        assert.is_false(helper:checkRequestBudget(req, function(_, book) return book and 800001 or 810001 end))
    end)
    it("budgets prompt overhead separately from book excerpts", function()
        local req = request("gemini", "prompt", "excerpts", 100)
        assert.is_false(helper:checkRequestBudget(req, function(_, book) return book and 50 or 101 end))
    end)
    it("uses conservative byte estimates for unsupported token counters", function()
        local req = request("custom1", string.rep("漢", 40), "text", 100)
        assert.is_false(helper:checkRequestBudget(req))
    end)
    it("reserves configured output and honors model-specific context overrides", function()
        helper.settings.model_context_limits = { small = 32768 }
        local budget = helper:getRequestBudget({ provider = "custom1", model = "small",
            body = json.encode({ max_tokens = 8192 }) }, "text")
        assert.are.equal(22528, budget.input_limit)
    end)
    it("rejects a request that fits primary but exceeds fallback capacity", function()
        local primary = request("gemini", string.rep("a", 1000), "text", 2000)
        local fallback = request("custom1", primary.body, "text", 500)
        assert.is_true(helper:checkRequestBudget(primary))
        assert.is_false(helper:checkRequestBudget(fallback))
    end)
    it("builds Gemini count requests including the system instruction", function()
        local req = request("gemini", json.encode({ contents = {{ parts = {{ text = "prompt" }} }},
            systemInstruction = { parts = {{ text = "rules" }} } }), "book", 1000)
        req.url = "https://generativelanguage.googleapis.com/v1beta/models/test:generateContent"
        local tokens = helper:countRequestTokens(req, false, function(url, _, body)
            assert.is_truthy(url:find(":countTokens$"))
            assert.are.equal("rules", json.decode(body).generateContentRequest.systemInstruction.parts[1].text)
            return { totalTokens = 25 }
        end)
        assert.are.equal(25, tokens)
    end)
    it("counts book excerpts separately for Claude", function()
        local req = request("claude", json.encode({ model = "test", messages = {} }), "book", 1000)
        req.url = "https://api.anthropic.com/v1/messages"
        assert.are.equal(12, helper:countRequestTokens(req, true, function(url, _, body)
            assert.is_truthy(url:find("/messages/count_tokens$"))
            assert.are.equal("book", json.decode(body).messages[1].content)
            return { input_tokens = 12 }
        end))
    end)
    it("falls back to estimates when counting is unavailable", function()
        local req = request("gemini", "prompt", "book", 100)
        assert.is_true(helper:checkRequestBudget(req, function() return nil end))
    end)
    it("classifies context, credential, configuration and transient errors", function()
        assert.are.equal("error_context", helper:classifyRequestError(400, "input token count exceeds maximum"))
        assert.are.equal("error_auth", helper:classifyRequestError(403, "forbidden"))
        assert.are.equal("error_config", helper:classifyRequestError(404, "model not found"))
        assert.are.equal("error_api", helper:classifyRequestError(429, "rate limit"))
    end)
end)

describe("async context rejection handling", function()
    local helper, requests, attempted, result_file, saved_modules
    local modules = { "ffi", "ffi/util", "posix.unistd", "socket.http", "ssl.https", "ltn12", "socketutil" }

    before_each(function()
        saved_modules = {}
        for _, name in ipairs(modules) do saved_modules[name] = package.loaded[name] end
        result_file = os.tmpname()
        attempted = {}
        requests = {
            { url = "https://primary.invalid", provider = "custom1", model = "primary", body = "{}" },
            { url = "https://fallback.invalid", provider = "custom2", model = "fallback", body = "{}" },
        }
        -- Execute the real child callback in-process, with no network or process exits.
        package.loaded["ffi"] = { cdef = function() end, C = {
            _exit = function() end,
            waitpid = function(pid) return pid end,
        } }
        package.loaded["posix.unistd"] = { _exit = function() end }
        package.loaded["ffi/util"] = { runInSubProcess = function(callback)
            callback(1234, nil)
            return 1234
        end }
        package.loaded["socket.http"] = { request = function(request)
            attempted[#attempted + 1] = request.url
            if request.url == requests[1].url then
                request.sink(json.encode({ error = { message = "maximum context length exceeded" } }))
                return 1, 400, {}
            end
            request.sink(json.encode({ choices = {{ message = { content = json.encode({
                characters = {{ name = "Alice", description = "Fallback result" }},
                locations = {}, timeline = {},
            }) } }} }))
            return 1, 200, {}
        end }
        package.loaded["ssl.https"] = {}
        package.loaded["ltn12"] = { source = { string = function(body)
            return function() local chunk = body; body = nil; return chunk end
        end } }
        package.loaded["socketutil"] = {
            set_timeout = function() end,
            reset_timeout = function() end,
            table_sink = function(parts)
                return function(chunk) if chunk then parts[#parts + 1] = chunk end; return 1 end
            end,
        }
        -- Reload locally so the helper captures the mocked FFI without replacing the shared module.
        helper = assert(loadfile("xray.koplugin/xray_aihelper.lua"))("xray_aihelper")
        helper.settings = {}
        helper.log = function() end
    end)

    after_each(function()
        for _, name in ipairs(modules) do package.loaded[name] = saved_modules[name] end
        os.remove(result_file)
    end)

    it("uses the manual fallback when the primary rejects the context size", function()
        local pid = helper:makeRequestAsync(requests, result_file)
        local data = helper:checkAsyncResult(result_file, pid)
        assert.same({ requests[1].url, requests[2].url }, attempted)
        assert.is_table(data)
        assert.are.equal("Alice", data.characters[1].name)
    end)

    it("returns a background context error for batch splitting without trying the fallback", function()
        for _, request in ipairs(requests) do
            request.token_budget = { book_text = "book", book_limit = 800000, input_limit = 1000 }
        end
        local pid = helper:makeRequestAsync(requests, result_file)
        local data, code = helper:checkAsyncResult(result_file, pid)
        assert.same({ requests[1].url }, attempted)
        assert.is_false(data)
        assert.are.equal("error_context", code)
    end)
end)
