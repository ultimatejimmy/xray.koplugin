-- AIHelper - Google Gemini & ChatGPT for X-Ray
local ok_http, http = pcall(require, "socket.http")
local ok_https, https = pcall(require, "ssl.https")
local ok_ltn12, ltn12 = pcall(require, "ltn12")
local ok_socket, socket = pcall(require, "socket")
local ok_socketutil, socketutil = pcall(require, "socketutil")

local logger = require("logger")
local plugin_path = ((...) or ""):match("(.-)[^%.]+$") or ""
local XRayLogger = require(plugin_path .. "xray_logger")
local Trapper = require("ui/trapper")

-- Optimization: Use rapidjson if available
local json_ok, json = pcall(require, "json")
if not json_ok then
    rapidjson_ok, json = pcall(require, "rapidjson")
end

-- Single source of truth for default AI models
local DEFAULT_AI = {
    primary   = { provider = "gemini", model = "gemini-3.5-flash" },
    secondary = { provider = "gemini", model = "gemini-3.1-flash-lite" },
}

local AIHelper = {
    path = ".",
    providers = {
        gemini = {
            name = "Google Gemini",
            enabled = true,
            api_key = nil,
        },
        chatgpt = {
            name = "ChatGPT",
            enabled = true,
            api_key = nil,
            endpoint = "https://api.openai.com/v1/chat/completions",
        },
        deepseek = {
            name = "DeepSeek",
            enabled = true,
            api_key = nil,
            endpoint = "https://api.deepseek.com/chat/completions",
        },
        claude = {
            name = "Anthropic Claude",
            enabled = true,
            api_key = nil,
            endpoint = "https://api.anthropic.com/v1/messages",
        },
        custom1 = {
            name = "Custom API 1",
            enabled = true,
            api_key = nil,
            endpoint = "",
            model = nil,
        },
        custom2 = {
            name = "Custom API 2",
            enabled = true,
            api_key = nil,
            endpoint = "",
            model = nil,
        }
    },
    default_provider = nil,
    current_language = "en",
    prompts = nil,
    trap_widget = nil,
}

-- Custom logger for X-Ray
function AIHelper:log(message)
    XRayLogger:log(message)
end

-- Strip invalid UTF-8 sequences and disallowed control bytes from a string.
-- Byte-based string.sub() throughout the plugin can slice multi-byte UTF-8
-- characters mid-sequence, leaving an invalid prefix/suffix that makes the
-- JSON request body non-parseable to strict APIs like OpenAI's.
function AIHelper:sanitize_utf8(s)
    if not s or s == "" then return s or "" end
    local out, i, len = {}, 1, #s
    while i <= len do
        local b = s:byte(i)
        if b < 0x80 then
            -- ASCII: keep printable + tab/LF/CR, replace other C0 controls with space
            if b >= 0x20 or b == 0x09 or b == 0x0A or b == 0x0D then
                out[#out+1] = string.char(b)
            else
                out[#out+1] = " "
            end
            i = i + 1
        elseif b < 0xC2 then
            -- Stray continuation byte (0x80-0xBF) or overlong start (0xC0-0xC1): drop
            i = i + 1
        elseif b < 0xE0 then
            -- 2-byte sequence
            local b2 = s:byte(i + 1)
            if b2 and b2 >= 0x80 and b2 < 0xC0 then
                out[#out+1] = s:sub(i, i + 1)
                i = i + 2
            else
                i = i + 1
            end
        elseif b < 0xF0 then
            -- 3-byte sequence
            local b2, b3 = s:byte(i + 1), s:byte(i + 2)
            if b2 and b3 and b2 >= 0x80 and b2 < 0xC0 and b3 >= 0x80 and b3 < 0xC0 then
                out[#out+1] = s:sub(i, i + 2)
                i = i + 3
            else
                i = i + 1
            end
        elseif b < 0xF5 then
            -- 4-byte sequence
            local b2, b3, b4 = s:byte(i + 1), s:byte(i + 2), s:byte(i + 3)
            if b2 and b3 and b4
                and b2 >= 0x80 and b2 < 0xC0
                and b3 >= 0x80 and b3 < 0xC0
                and b4 >= 0x80 and b4 < 0xC0 then
                out[#out+1] = s:sub(i, i + 3)
                i = i + 4
            else
                i = i + 1
            end
        else
            -- Invalid leading byte (0xF5-0xFF)
            i = i + 1
        end
    end
    return table.concat(out)
end

-- Backward compatibility for internal calls
local sanitize_utf8 = function(s) return AIHelper:sanitize_utf8(s) end

function AIHelper:getChatGPTTokenConfig(model)
    -- OpenAI reasoning models (o1, o3) and newer generations (gpt-5+) REQUIRE max_completion_tokens.
    -- Modern flagship models (gpt-4o, gpt-4o-mini) also support it.
    if model:find("^o[13]") or model:find("^gpt%-5") or model:find("^gpt%-4o") then
        return "max_completion_tokens", 32000
    end
    
    -- DeepSeek (all v4 models) and older GPT-4 models do NOT support max_completion_tokens 
    -- in their official APIs and will return a 400 error. They require the standard max_tokens.
    if model:find("deepseek") or model:find("%-r1") or model:find("/r1") then
        return "max_tokens", 32000
    end
    
    -- Raise the default from 8192 to 16384 for other models.
    return "max_tokens", 16384
end

function AIHelper:setTrapWidget(trap_widget) self.trap_widget = trap_widget end
function AIHelper:resetTrapWidget() self.trap_widget = nil end

function AIHelper:makeRequest(url, headers, request_body, timeout, maxtime)
    -- Increased default timeout to 600s (10m) to accommodate reasoning models at xhigh effort
    timeout = timeout or 600; maxtime = maxtime or 1200
    local function performRequest()
        local http_req = require("socket.http"); local https_req = require("ssl.https")
        local ltn12_req = require("ltn12"); local socketutil_req = require("socketutil")
        https_req.cert_verify = false; socketutil_req:set_timeout(timeout, maxtime)
        local response_body = {}
        local request = { url = url, method = "POST", headers = headers or {}, source = ltn12_req.source.string(request_body or ""), sink = socketutil_req.table_sink(response_body) }
        local ok, code, response_headers, status
        local pcall_ok, pcall_err = pcall(function() ok, code, response_headers, status = http_req.request(request) end)
        if not pcall_ok then return nil, "error_crash", tostring(pcall_err) end
        socketutil_req:reset_timeout()
        local response_text = table.concat(response_body)
        if response_headers and response_headers["content-length"] then
            local clen = tonumber(response_headers["content-length"])
            if clen and #response_text < clen then return nil, "error_incomplete", "Incomplete response" end
        end
        if ok == nil and (code == "timeout" or tostring(code):find("timeout")) then return nil, "error_timeout", "Connection timed out" end
        return ok, code, response_text, status
    end
    
    if self.trap_widget and Trapper and Trapper.dismissableRunInSubprocess then
        local completed, ok, code, response_text, status = Trapper:dismissableRunInSubprocess(performRequest, self.trap_widget)
        if not completed then return nil, "USER_CANCELLED", "Request cancelled" end
        return ok, code, response_text, status
    else
        return performRequest()
    end
end

-- Build all possible HTTP request parameters (primary and fallback) for a comprehensive fetch.
-- Returns: { {url, headers, body, provider, model}, ... } or nil, error_code, error_msg
function AIHelper:buildComprehensiveRequest(title, author, context, prompt_override)
    local prompt = prompt_override or self:createPrompt(title, author, context, "comprehensive_xray")
    local primary = self.settings.primary_ai or DEFAULT_AI.primary
    local secondary = self.settings.secondary_ai or DEFAULT_AI.secondary

    local requests = {}
    for _, ai in ipairs({ primary, secondary }) do
        local config = self.providers[ai.provider]
        if config and config.api_key and config.api_key ~= "" then
            local url, headers, body
            if ai.provider == "gemini" then
                local model = ai.model or DEFAULT_AI.primary.model
                local system_instruction_text = self.prompts and self.prompts.system_instruction or "Return valid JSON ONLY."
                url = "https://generativelanguage.googleapis.com/v1beta/models/" .. model .. ":generateContent"
                headers = { ["Content-Type"] = "application/json", ["x-goog-api-key"] = config.api_key }
                
                local gen_config = { temperature = 0.2, maxOutputTokens = 16384 } -- default
                local current_effort = self.settings and self.settings.reasoning_effort
                
                -- Check for thinking support (Gemini 2.5 series and Gemini 3 series)
                if current_effort and (model:find("thinking") or model:find("2%.5") or model:find("3%.0") or model:find("3%.1") or model:find("pro") or model:find("flash")) then
                    if model:find("gemini%-3") then
                        -- Gemini 3 series uses thinkingLevel
                        local level_map = { low = "low", medium = "medium", high = "high" }
                        gen_config.thinkingConfig = { 
                            includeThoughts = true,
                            thinkingLevel = level_map[current_effort] or "medium" 
                        }
                        -- Ensure maxOutputTokens leaves room for the response
                        gen_config.maxOutputTokens = 16384
                    else
                        -- Gemini 2.5 series uses thinkingBudget (integer)
                        local budget_map = { low = 1024, medium = 4096, high = 16384 }
                        local budget = budget_map[current_effort] or 4096
                        
                        -- Capping for constrained models if necessary (1.5 models were pre-thinking, 2.0-flash is 8k limit)
                        if (model:find("1%.5") or model:find("2%.0%-flash")) and budget > 2000 then
                            self:log(string.format("AIHelper: Constrained Gemini %s detected — capping thinking budget from %d to 2000 (limit=8192)", model, budget))
                            budget = 2000
                            gen_config.maxOutputTokens = 8192
                        else
                            gen_config.maxOutputTokens = budget + 8000
                        end
                        
                        gen_config.thinkingConfig = { 
                            includeThoughts = true,
                            thinkingBudget = budget 
                        }
                    end
                end
                
                body = json.encode({
                    contents = {{ role = "user", parts = {{ text = prompt }} }},
                    system_instruction = { parts = {{ text = system_instruction_text }} },
                    safetySettings = {
                        { category = "HARM_CATEGORY_SEXUALLY_EXPLICIT", threshold = "BLOCK_NONE" },
                        { category = "HARM_CATEGORY_HATE_SPEECH", threshold = "BLOCK_NONE" },
                        { category = "HARM_CATEGORY_HARASSMENT", threshold = "BLOCK_NONE" },
                        { category = "HARM_CATEGORY_DANGEROUS_CONTENT", threshold = "BLOCK_NONE" }
                    },
                    generationConfig = gen_config
                })
            elseif ai.provider == "claude" then
                local model = ai.model or "claude-3-7-sonnet-latest"
                url = config.endpoint or "https://api.anthropic.com/v1/messages"
                headers = { ["Content-Type"] = "application/json", ["x-api-key"] = config.api_key, ["anthropic-version"] = "2023-06-01" }
                local system_instruction_text = (self.prompts and self.prompts.system_instruction or "Return valid JSON ONLY.") .. " You MUST output strictly valid JSON, starting with '{'."
                
                local req_body = {
                    model = model,
                    max_tokens = 8192,  -- default for non-thinking models; overridden below
                    system = system_instruction_text,
                    messages = {
                        { role = "user", content = prompt },
                        { role = "assistant", content = "{" }
                    }
                }
                
                if model:find("sonnet") or model:find("opus") or model:find("haiku") then
                    local current_effort = self.settings and self.settings.reasoning_effort
                    if current_effort then
                        local effort_map = { low = 2048, medium = 4096, high = 8192 }
                        local budget = effort_map[current_effort] or 4096
                        -- Haiku has a hard max_tokens limit of 8192; silently cap budget to leave room for output.
                        -- Claude thinking tokens count against max_tokens, so max_tokens must be > budget_tokens.
                        if model:find("haiku") and budget > 2000 then
                            self:log(string.format("AIHelper: Haiku detected — capping thinking budget from %d to 2000 (haiku max_tokens=8192)", budget))
                            budget = 2000
                            req_body.max_tokens = 8192
                        else
                            -- For sonnet/opus: dynamically scale max_tokens to always leave 8000 tokens for the JSON response.
                            -- Without this, at 'high' effort budget_tokens==max_tokens leaving zero room for output.
                            local output_reserve = 8000
                            req_body.max_tokens = budget + output_reserve
                        end
                        -- Claude extended thinking configuration
                        req_body.thinking = { type = "enabled", budget_tokens = budget }
                    end
                end
                
                body = json.encode(req_body)
            else
                local model = ai.model or "gpt-4o-mini"
                url = config.endpoint or "https://api.openai.com/v1/chat/completions"
                headers = { ["Content-Type"] = "application/json", ["Authorization"] = "Bearer " .. config.api_key }
                local system_instruction_text = self.prompts and self.prompts.system_instruction or "Return valid JSON ONLY."
                local is_openai_reasoning = (model:find("^gpt%-5") or model:find("^o[13]"))
                if is_openai_reasoning then
                    system_instruction_text = system_instruction_text .. " You MUST output strictly valid JSON, starting with '{'."
                else
                    -- OpenAI requires the word 'json' to appear somewhere in messages when using json_object mode.
                    -- Append a guaranteed-ASCII sentinel so localized prompts never trigger a 400 error.
                    if not system_instruction_text:lower():find("json") then
                        system_instruction_text = system_instruction_text .. " Respond in JSON format."
                    end
                end

                local instruction_role = "system"
                if is_openai_reasoning then
                    instruction_role = "developer"
                end

                local token_param, token_val = self:getChatGPTTokenConfig(model)
                local req_body = { 
                    model = model, 
                    messages = {
                        { role = instruction_role, content = system_instruction_text },
                        { role = "user", content = prompt }
                    }, 
                    response_format = { type = "json_object" },
                    [token_param] = token_val
                }
                
                -- DeepSeek V4 models reason inherently; official API does not support reasoning_effort and will return a 400 error.
                -- We only apply token ceiling adjustments here. Also catches legacy deepseek-reasoner stored values.
                if ai.provider == "deepseek" and (model:find("reasoner") or model:find("v4") or model:find("deepseek")) then
                    -- No effort mapping for official DeepSeek API to avoid 400 errors.
                    -- The 32k token ceiling is already handled by getChatGPTTokenConfig.
                end

                -- OpenAI gpt-5 and o-series: inject reasoning_effort (xhigh is a valid OpenAI value).
                -- IMPORTANT: response_format={json_object} is incompatible with reasoning_effort and causes a 400 error.
                -- When reasoning is active, drop response_format and rely on the system prompt JSON instruction.
                -- Also raise max_completion_tokens: GPT-5 models support 128k output; at xhigh effort
                -- OpenAI recommends reserving ~25k for reasoning, so 65k is a safe ceiling.
                if (ai.provider == "chatgpt" or ai.provider == "custom1" or ai.provider == "custom2")
                    and (model:find("^gpt%-5") or model:find("^o[13]")) then
                    local current_effort = self.settings and self.settings.reasoning_effort
                    if current_effort then
                        req_body.reasoning_effort = current_effort
                        req_body.response_format = nil  -- incompatible with reasoning_effort
                        if current_effort == "high" then
                            req_body[token_param] = 65000
                            self:log(string.format("AIHelper: OpenAI %s at %s effort — dropping json_object mode, raising max_completion_tokens to 65000", model, current_effort))
                        end
                    end
                end
                
                if ai.provider == "custom1" or ai.provider == "custom2" then
                    if (config.endpoint or ""):find("openrouter.ai") then
                        headers["HTTP-Referer"]      = "https://github.com/koreader/koreader-xray-plugin"
                        headers["X-OpenRouter-Title"] = "KOReader X-Ray"
                    end
                    -- Per-slot "Is Reasoning Model" setting: raise token ceiling to accommodate reasoning chains
                    local is_reasoning = self.settings and self.settings[ai.provider .. "_is_reasoning"]
                    if is_reasoning then
                        req_body["max_completion_tokens"] = 32000
                        self:log(string.format("AIHelper: Custom slot %s marked as reasoning model — using 32000 token ceiling", ai.provider))
                    end
                end
                
                body = json.encode(req_body)
            end
            table.insert(requests, { url = url, headers = headers, body = body, provider = ai.provider, model = ai.model })
        end
    end
    
    if #requests > 0 then
        return requests
    end
    return nil, "error_api", "No API key configured"
end

-- Check if at least one API key is configured
function AIHelper:hasApiKey()
    if self.providers.gemini and self.providers.gemini.api_key and self.providers.gemini.api_key ~= "" then return true end
    if self.providers.chatgpt and self.providers.chatgpt.api_key and self.providers.chatgpt.api_key ~= "" then return true end
    if self.providers.deepseek and self.providers.deepseek.api_key and self.providers.deepseek.api_key ~= "" then return true end
    if self.providers.claude and self.providers.claude.api_key and self.providers.claude.api_key ~= "" then return true end
    if self.providers.custom1 and self.providers.custom1.api_key and self.providers.custom1.api_key ~= "" then return true end
    if self.providers.custom2 and self.providers.custom2.api_key and self.providers.custom2.api_key ~= "" then return true end
    return false
end

-- Fork a child process to perform the HTTP request. Returns true if started.
function AIHelper:makeRequestAsync(request_params, result_file)
    local ok_ffi, ffiutil = pcall(require, "ffi/util")
    if not ok_ffi then
        ok_ffi, ffiutil = pcall(require, "ffiutil")
    end
    
    local function child_logic(pid, write_fd)
        local child_ok, child_err = pcall(function()
            self:log("AIHelper Child: Started background process")
            local http_req = require("socket.http")
            local https_req = require("ssl.https")
            local ltn12_req = require("ltn12")
            local socketutil_req = require("socketutil")
            https_req.cert_verify = false
            -- Increased timeout to 600s (10m) to accommodate reasoning models computing in the background
            socketutil_req:set_timeout(600, 1200)

            local requests = request_params
            if request_params.url then requests = { request_params } end -- Handle single request fallback

            local success_found = false
            for i, req in ipairs(requests) do
                self:log(string.format("AIHelper Child: Sending request %d/%d to %s (%s)", i, #requests, req.provider, req.model or "default"))
                
                local ok, code, response_headers, status, response_text, code_num
                local attempts = 0
                local max_attempts = 2

                while attempts < max_attempts do
                    attempts = attempts + 1
                    local response_body = {}
                    local request = {
                        url = req.url,
                        method = "POST",
                        headers = req.headers or {},
                        source = ltn12_req.source.string(req.body or ""),
                        sink = socketutil_req.table_sink(response_body)
                    }
                    ok, code, response_headers, status = http_req.request(request)
                    response_text = table.concat(response_body)
                    code_num = tonumber(code)

                    if code_num == 503 and attempts < max_attempts then
                        self:log("AIHelper Child: 503 Service Overloaded — retrying in 2s...")
                        socket.sleep(2)
                    else
                        break
                    end
                end

                -- Mirror the content-length completeness check from makeRequest (lines 167-170)
                if response_headers and response_headers["content-length"] then
                    local clen = tonumber(response_headers["content-length"])
                    if clen and #response_text < clen then
                        self:log(string.format(
                            "AIHelper Child: Incomplete response from %s — got %d bytes, expected %d. Treating as failure.",
                            req.provider, #response_text, clen))
                        code_num = nil -- prevents falling into the code_num==200 block below
                    end
                end

                self:log("AIHelper Child: Request finished with code " .. tostring(code))

                -- Add pacing after transient failures to avoid "cascading" quota/load issues on fallback
                if code_num == 429 or code_num == 503 then
                    self:log("AIHelper Child: Transient error " .. tostring(code_num) .. " — pacing fallback (2s)")
                    socket.sleep(2)
                end

                if code_num == 200 then
                    -- Quick JSON validation before accepting the response
                    local json_req = require("json")
                    local valid_json = false
                    local parse_ok, parsed = pcall(json_req.decode, response_text)
                    if parse_ok and parsed then
                        -- Gemini wraps content in candidates[].content.parts[].text
                        if parsed.candidates and parsed.candidates[1] then
                            local ai_text = ""
                            local parts = parsed.candidates[1].content and parsed.candidates[1].content.parts or {}
                            for _, p in ipairs(parts) do
                                if p.text and not p.thought then
                                    ai_text = ai_text .. p.text
                                end
                            end
                            local finish_reason = (parsed.candidates[1] and parsed.candidates[1].finishReason) or "STOP"
                            if #ai_text == 0 then
                                self:log("AIHelper Child: Gemini ai_text empty. finishReason=" .. finish_reason)
                            end
                            if #ai_text > 0 then
                                local inner_ok, inner = pcall(json_req.decode, ai_text)
                                valid_json = inner_ok and inner ~= nil
                                if not valid_json then
                                    -- Try to find JSON boundaries for truncated responses
                                    local first_brace = ai_text:find("{", 1, true)
                                    if first_brace then
                                        -- Part B: Try to repair before giving up
                                        local repaired = self:fixTruncatedJSON(ai_text:sub(first_brace))
                                        local repair_ok, repair_data = pcall(json_req.decode, repaired)
                                        if repair_ok and repair_data then
                                            self:log("AIHelper Child: fixTruncatedJSON succeeded for " .. req.provider)
                                            local synthetic = json_req.encode({
                                                candidates = {{
                                                    content = { parts = {{ text = repaired }} },
                                                    finishReason = "STOP"
                                                }}
                                            })
                                            response_text = synthetic
                                            valid_json = true
                                        else
                                            self:log("AIHelper Child: Quick repair unsuccessful; handing off to main thread for advanced parsing")
                                            valid_json = true -- Fall back to main thread's repair if child fails but it has a brace
                                        end
                                    end
                                end
                            end
                        -- ChatGPT wraps content in choices[].message.content
                        elseif parsed.choices and parsed.choices[1] then
                            local content = parsed.choices[1].message and parsed.choices[1].message.content
                            if content then
                                local inner_ok, inner = pcall(json_req.decode, content)
                                valid_json = inner_ok and inner ~= nil
                                if not valid_json then
                                    local first_brace = content:find("{", 1, true)
                                    if first_brace then
                                        local repaired = self:fixTruncatedJSON(content:sub(first_brace))
                                        local repair_ok, repair_data = pcall(json_req.decode, repaired)
                                        if repair_ok and repair_data then
                                            self:log("AIHelper Child: fixTruncatedJSON succeeded for ChatGPT/" .. req.provider)
                                            local synthetic = json_req.encode({
                                                choices = {{
                                                    message = { content = repaired, role = "assistant" }
                                                }}
                                            })
                                            response_text = synthetic
                                            valid_json = true
                                        else
                                            self:log("AIHelper Child: Quick repair unsuccessful; handing off to main thread for advanced parsing")
                                            valid_json = true
                                        end
                                    end
                                end
                            end
                        end
                    end
                    
                    if valid_json then
                        -- Success! Write result to file and exit loop
                        local f = io.open(result_file, "w")
                        if f then
                            f:write(tostring(code) .. "\n")
                            f:write(req.provider .. "\n")
                            f:write(response_text)
                            f:close()
                            self:log("AIHelper Child: Result written to " .. result_file)
                            success_found = true
                            break
                        else
                            self:log("AIHelper Child: Failed to open result file " .. result_file)
                        end
                    else
                        self:log(string.format("AIHelper Child: Provider %s returned 200 but JSON is invalid/truncated. Trying fallback.", req.provider))
                        -- Fall through to try the next provider
                        if i == #requests then
                            -- Last provider also failed validation — write it anyway so main thread can attempt repair
                            local f = io.open(result_file, "w")
                            if f then
                                f:write(tostring(code) .. "\n")
                                f:write(req.provider .. "\n")
                                f:write(response_text)
                                f:close()
                            end
                        end
                    end
                else
                    self:log(string.format("AIHelper Child: Provider %s failed with code %s", req.provider, tostring(code)))
                    -- If it's the last one, write the error
                    if i == #requests then
                        local f = io.open(result_file, "w")
                        if f then
                            f:write(tostring(code) .. "\n")
                            f:write(req.provider .. "\n")
                            f:write(response_text)
                            f:close()
                        end
                    end
                end
            end
            socketutil_req:reset_timeout()
        end)
        
        if not child_ok then
            self:log("AIHelper Child: CRITICAL ERROR: " .. tostring(child_err))
            local f = io.open(result_file, "w")
            if f then
                f:write("ERROR\n")
                f:write("unknown\n")
                f:write(tostring(child_err))
                f:close()
            end
        end

        -- Close write_fd if provided by runInSubProcess
        if write_fd and write_fd > 0 then
            pcall(function() 
                local ffi = require("ffi")
                ffi.cdef[[ int close(int fd); ]]
                ffi.C.close(write_fd) 
            end)
        end

        -- Exit child cleanly
        local ffi_ok, ffi = pcall(require, "ffi")
        if ffi_ok then
            pcall(function()
                ffi.cdef[[ void _exit(int status); ]]
                ffi.C._exit(0)
            end)
        end
        local posix_ok, posix = pcall(require, "posix.unistd")
        if posix_ok and posix and posix._exit then
            posix._exit(0)
        else
            os.exit(0)
        end
    end

    -- Method 1: ffiutil.runInSubProcess (Preferred KOReader pattern)
    if ok_ffi and ffiutil and ffiutil.runInSubProcess then
        self:log("AIHelper: Trying ffiutil.runInSubProcess")
        local pid, read_fd = ffiutil.runInSubProcess(child_logic, true)
        if pid and pid > 0 then
            self:log("AIHelper: runInSubProcess started PID " .. tostring(pid))
            -- We don't need the pipe for now as we use the result_file
            if read_fd and read_fd > 0 then
                pcall(function() 
                    local ffi = require("ffi")
                    ffi.cdef[[ int close(int fd); ]]
                    ffi.C.close(read_fd) 
                end)
            end
            self._async_child_pid = pid
            return pid
        end
    end

    -- Method 2: Manual fork fallbacks
    local fork = nil
    if ok_ffi and ffiutil and ffiutil.fork then
        fork = ffiutil.fork
    else
        local ok_posix, posix = pcall(require, "posix.unistd")
        if not ok_posix then ok_posix, posix = pcall(require, "posix") end
        if ok_posix and posix and posix.fork then
            fork = posix.fork
        else
            local ok_f, ffi = pcall(require, "ffi")
            if ok_f then
                pcall(function()
                    ffi.cdef[[ int fork(void); ]]
                    fork = ffi.C.fork
                end)
            end
        end
    end
    
    if fork then
        local pid = fork()
        if pid == 0 then
            child_logic(0, nil)
            return true -- unreachable
        elseif pid and pid > 0 then
            self:log("AIHelper: Manual fork started PID " .. tostring(pid))
            self._async_child_pid = pid
            return pid
        end
    end

    self:log("AIHelper: All background fetch methods failed")
    return false
end

-- Check if the async result file exists and parse it. Returns:
--   nil (still pending)
--   book_data table (success)
--   false, error_code, error_msg (failed)
function AIHelper:checkAsyncResult(result_file)
    local f = io.open(result_file, "r")
    if not f then return nil end  -- still pending

    local content = f:read("*a")
    f:close()
    os.remove(result_file)

    -- Reap child process to prevent zombies
    if self._async_child_pid then
        pcall(function()
            local posix_sys = require("posix.sys.wait")
            posix_sys.wait(self._async_child_pid, posix_sys.WNOHANG)
        end)
        self._async_child_pid = nil
    end

    -- Parse: first line = code, second line = provider, rest = response body
    local first_newline = content:find("\n")
    if not first_newline then return false, "error_parse", "Malformed async result (empty or no newline)" end
    local code_str = content:sub(1, first_newline - 1)
    local rest = content:sub(first_newline + 1)
    local second_newline = rest:find("\n")
    if not second_newline then return false, "error_parse", "Malformed async result (no provider line)" end
    local provider = rest:sub(1, second_newline - 1)
    local response_text = rest:sub(second_newline + 1)

    if code_str == "ERROR" then
        return false, "error_api", response_text
    end

    local code_num = tonumber(code_str)
    if code_num ~= 200 or not response_text or #response_text == 0 then
        return false, "error_api", "HTTP " .. tostring(code_num)
    end

    -- Parse the response based on provider
    local success, data = pcall(json.decode, response_text)
    if not success then return false, "error_parse", "JSON decode failed" end

    local ai_text = ""
    if provider == "gemini" then
        if data.candidates and data.candidates[1] and
           data.candidates[1].content and data.candidates[1].content.parts then
            local parts = data.candidates[1].content.parts
            for _, p in ipairs(parts) do
                if p.text and not p.thought then
                    ai_text = ai_text .. p.text
                end
            end
        end
    elseif provider == "claude" then
        if data.content and data.content[1] and data.content[1].text then
            -- Prepend the '{' that we prefilled in the request
            ai_text = "{" .. data.content[1].text
        end
    else
        if data.choices and data.choices[1] then
            ai_text = data.choices[1].message.content
        end
    end

    if not ai_text or #ai_text == 0 then
        local finish_reason = (data.candidates and data.candidates[1] and data.candidates[1].finishReason) or "unknown"
        self:log("AIHelper: Gemini ai_text empty. finishReason=" .. finish_reason)
        return false, "error_parse", "No text in AI response (finishReason=" .. finish_reason .. ")"
    end

    local parsed_data, parse_err = self:parseAIResponse(ai_text)
    if parsed_data then
        return parsed_data
    else
        return false, "error_parse", tostring(parse_err)
    end
end

function AIHelper:cancelAsyncChild()
    if self._async_child_pid then
        self:log("AIHelper: Cancelling async child process PID " .. tostring(self._async_child_pid))
        pcall(function()
            local ffi = require("ffi")
            ffi.cdef[[
                int kill(int pid, int sig);
                int waitpid(int pid, int *status, int options);
            ]]
            ffi.C.kill(self._async_child_pid, 9) -- SIGKILL
            ffi.C.waitpid(self._async_child_pid, nil, 1) -- WNOHANG = 1
        end)
        pcall(function()
            local posix_sys = require("posix.sys.wait")
            posix_sys.wait(self._async_child_pid, posix_sys.WNOHANG)
        end)
        self._async_child_pid = nil
    end
end

function AIHelper:init(path)
    self.path = path or "plugins/xray.koplugin"
    
    -- Cleanup orphaned temporary files from previous sessions
    pcall(function()
        local ok, lfs = pcall(require, "libs/libkoreader-lfs")
        if not ok or type(lfs) ~= "table" then
            ok, lfs = pcall(require, "lfs")
        end
        if ok and lfs and lfs.dir then
            for file in lfs.dir(self.path) do
                if file:find("^tmp_ai_res_.-%.json$") then
                    os.remove(self.path .. "/" .. file)
                end
            end
        end
    end)
    
    self:loadConfig()
    self:loadSettings()
    self:loadLanguage()
    self:log("AIHelper initialized")
end


function AIHelper:loadConfig()
    local new_config_file = self.path .. "/xray_config.lua"
    local old_config_file = self.path .. "/config.lua"
    
    -- Graceful migration for existing config.lua users
    local old_f = io.open(old_config_file, "r")
    if old_f then
        old_f:close()
        local old_success, old_config = pcall(dofile, old_config_file)
        if old_success and type(old_config) == "table" then
            local has_keys = false
            if old_config.gemini_api_key and #old_config.gemini_api_key > 0 then has_keys = true end
            if old_config.chatgpt_api_key and #old_config.chatgpt_api_key > 0 then has_keys = true end
            if has_keys then
                self:log("AIHelper: Migrating user keys from old config.lua to xray_config.lua")
                local new_f = io.open(new_config_file, "r")
                if new_f then
                    local new_text = new_f:read("*a")
                    new_f:close()
                    if old_config.gemini_api_key and #old_config.gemini_api_key > 0 then
                        local safe_key = old_config.gemini_api_key:gsub("%%", "%%%%")
                        new_text = new_text:gsub('gemini_api_key%s*=%s*""', 'gemini_api_key = "' .. safe_key .. '"')
                    end
                    if old_config.chatgpt_api_key and #old_config.chatgpt_api_key > 0 then
                        local safe_key = old_config.chatgpt_api_key:gsub("%%", "%%%%")
                        new_text = new_text:gsub('chatgpt_api_key%s*=%s*""', 'chatgpt_api_key = "' .. safe_key .. '"')
                    end

                    local out_f = io.open(new_config_file, "w")
                    if out_f then
                        out_f:write(new_text)
                        out_f:close()
                    end
                end
                os.remove(old_config_file)
            else
                os.remove(old_config_file)
            end
        else
            os.rename(old_config_file, old_config_file .. ".bak")
        end
    end

    local success, config = pcall(dofile, new_config_file)
    self.config_keys = { gemini = nil, chatgpt = nil, deepseek = nil, claude = nil, custom1 = nil, custom2 = nil }
    if success and config then
        if config.gemini_api_key then self.providers.gemini.api_key = config.gemini_api_key; self.config_keys.gemini = config.gemini_api_key end
        if config.gemini_primary_model then self.providers.gemini.primary_model = config.gemini_primary_model end
        if config.gemini_secondary_model then self.providers.gemini.secondary_model = config.gemini_secondary_model end
        if config.chatgpt_api_key then self.providers.chatgpt.api_key = config.chatgpt_api_key; self.config_keys.chatgpt = config.chatgpt_api_key end
        if config.chatgpt_model then self.providers.chatgpt.model = config.chatgpt_model end
        if config.deepseek_api_key then self.providers.deepseek.api_key = config.deepseek_api_key; self.config_keys.deepseek = config.deepseek_api_key end
        if config.claude_api_key then self.providers.claude.api_key = config.claude_api_key; self.config_keys.claude = config.claude_api_key end
        if config.default_provider then self.default_provider = config.default_provider end
        
        for _, slot in ipairs({"custom1", "custom2"}) do
            if config[slot .. "_api_key"]  then self.providers[slot].api_key  = config[slot .. "_api_key"];  self.config_keys[slot] = config[slot .. "_api_key"] end
            if config[slot .. "_endpoint"] then self.providers[slot].endpoint = config[slot .. "_endpoint"] end
            if config[slot .. "_model"]    then self.providers[slot].model    = config[slot .. "_model"]    end
        end
    end
end

function AIHelper:loadSettings()
    self.settings = self.settings or {}
    local DataStorage = require("datastorage")
    local xray_dir = DataStorage:getSettingsDir() .. "/xray"
    
    local ok, lfs = pcall(require, "libs/libkoreader-lfs")
    if not ok or type(lfs) ~= "table" then
        ok, lfs = pcall(require, "lfs")
    end
    
    local settings = {}
    
    if not ok or type(lfs) ~= "table" then
        self:log("AIHelper: Settings will be in-memory only (lfs module missing)")
        lfs = nil
    else
        if lfs.attributes(xray_dir, "mode") ~= "directory" then
            lfs.mkdir(xray_dir)
        end
    end

    
    local settings_file = xray_dir .. "/settings.json"
    
    -- Migration from old .txt files
    local migrated = false
    local function migrate_file(filename, key)
        local f = io.open(xray_dir .. "/" .. filename, "r")
        if f then
            local val = f:read("*a"):match("^%s*(.-)%s*$")
            f:close()
            if val and #val > 0 then
                settings[key] = val
                migrated = true
            end
            os.remove(xray_dir .. "/" .. filename)
        end
    end
    
    migrate_file("default_provider.txt", "default_provider")
    migrate_file("gemini_api_key.txt", "gemini_api_key")
    migrate_file("chatgpt_api_key.txt", "chatgpt_api_key")
    migrate_file("language.txt", "language")
    
    -- Load existing settings.json if it exists
    local f = io.open(settings_file, "r")
    if f then
        local content = f:read("*a")
        f:close()
        local success, decoded = pcall(json.decode, content)
        if success and type(decoded) == "table" then
            for k, v in pairs(decoded) do
                settings[k] = v
            end
        end
    end
    
    -- Ensure config values are used as initial defaults if not in settings.json
    if not settings.gemini_primary_model then settings.gemini_primary_model = self.providers.gemini.primary_model end
    if not settings.gemini_secondary_model then settings.gemini_secondary_model = self.providers.gemini.secondary_model end
    if not settings.chatgpt_model then settings.chatgpt_model = self.providers.chatgpt.model end

    -- Description length defaults (chars per entity type)
    if not settings.char_desc_len     then settings.char_desc_len     = 200 end
    if not settings.loc_desc_len      then settings.loc_desc_len      = 100 end
    if not settings.timeline_event_len then settings.timeline_event_len = 80  end
    if not settings.hist_fig_bio_len  then settings.hist_fig_bio_len  = 100 end
    if not settings.term_def_len       then settings.term_def_len       = 100      end
    if not settings.default_book_mode  then settings.default_book_mode  = "auto"   end
    if not settings.terms_visibility   then settings.terms_visibility   = "always" end
    if settings.series_context_enabled == nil then settings.series_context_enabled = true end
    
    -- Migration to unified Primary and Secondary AI logic
    if type(settings.primary_ai) ~= "table" then
        local def_prov = settings.default_provider or "gemini"
        if def_prov == "gemini" then
            settings.primary_ai = { provider = "gemini", model = settings.gemini_primary_model or DEFAULT_AI.primary.model }
        else
            settings.primary_ai = { provider = "chatgpt", model = settings.chatgpt_model or "gpt-5.4-mini" }
        end
        migrated = true
    end
    
    if type(settings.secondary_ai) ~= "table" then
        settings.secondary_ai = { provider = "gemini", model = settings.gemini_secondary_model or DEFAULT_AI.secondary.model }
        migrated = true
    end
    
    -- Migrate legacy DeepSeek model names to v4 API names (deprecated 2026-07-24)
    local deepseek_model_map = {
        ["deepseek-chat"]     = "deepseek-v4-flash",
        ["deepseek-reasoner"] = "deepseek-v4-pro",
    }
    local function migrate_deepseek_model(ai_slot)
        if type(settings[ai_slot]) == "table" and settings[ai_slot].provider == "deepseek" then
            local old = settings[ai_slot].model
            if old and deepseek_model_map[old] then
                self:log(string.format("AIHelper: Migrating DeepSeek model '%s' -> '%s' in %s", old, deepseek_model_map[old], ai_slot))
                settings[ai_slot].model = deepseek_model_map[old]
                migrated = true
            end
        end
    end
    migrate_deepseek_model("primary_ai")
    migrate_deepseek_model("secondary_ai")

    -- One-time migration to set the new UI defaults: footnote style for in-text, classic style for menu
    if settings.ui_defaults_migrated_v2 == nil then
        settings.ui_popup_intext = true
        settings.ui_popup_menu = false
        settings.ui_defaults_migrated_v2 = true
        migrated = true
    end

    if migrated then
        self.settings = settings
        self:saveSettings()
    end
    
    -- Migrate Extra High reasoning effort to High (Extra High is being removed)
    if settings.reasoning_effort == "xhigh" then
        settings.reasoning_effort = "high"
    end
    
    self.settings = settings
    
    -- If no language is set, default to KOReader's system language
    if not settings.language then
        local gettext = require("gettext")
        local ko_lang = gettext.getLanguage and gettext.getLanguage()
        if not ko_lang and G_reader_settings then
            ko_lang = G_reader_settings:readSetting("language")
        end
        
        if ko_lang then
            -- Normalize language code
            local lang = ko_lang:sub(1, 2):lower()
            if ko_lang:lower():find("zh_cn") or ko_lang:lower():find("zh-cn") then
                lang = "zh_CN"
            elseif ko_lang:lower():find("pt_br") or ko_lang:lower():find("pt-br") then
                lang = "pt_br"
            end
            
            -- Only auto-set if it's one of our supported languages
            local supported = { en=1, de=1, fr=1, ru=1, zh_CN=1, tr=1, pt_br=1, es=1, uk=1, hu=1 }
            if supported[lang] then
                settings.language = lang
                migrated = true
            end
        end
    end

    self.current_language = settings.language or "en"
    
    if settings.gemini_api_key then 
        if settings.gemini_use_ui_key ~= false then
            self.providers.gemini.api_key = settings.gemini_api_key
            self.providers.gemini.ui_key_active = true
        else
            self.providers.gemini.ui_key_active = false
        end
    end
    
    if settings.chatgpt_api_key then 
        if settings.chatgpt_use_ui_key ~= false then
            self.providers.chatgpt.api_key = settings.chatgpt_api_key
            self.providers.chatgpt.ui_key_active = true
        else
            self.providers.chatgpt.ui_key_active = false
        end
    end
    
    if settings.deepseek_api_key then 
        if settings.deepseek_use_ui_key ~= false then
            self.providers.deepseek.api_key = settings.deepseek_api_key
            self.providers.deepseek.ui_key_active = true
        else
            self.providers.deepseek.ui_key_active = false
        end
    end
    
    if settings.claude_api_key then 
        if settings.claude_use_ui_key ~= false then
            self.providers.claude.api_key = settings.claude_api_key
            self.providers.claude.ui_key_active = true
        else
            self.providers.claude.ui_key_active = false
        end
    end
    
    for _, slot in ipairs({"custom1", "custom2"}) do
        if settings[slot .. "_api_key"] then
            if settings[slot .. "_use_ui_key"] ~= false then
                self.providers[slot].api_key = settings[slot .. "_api_key"]
                self.providers[slot].ui_key_active = true
            else
                self.providers[slot].ui_key_active = false
            end
        end
        if settings[slot .. "_endpoint"] then self.providers[slot].endpoint = settings[slot .. "_endpoint"] end
        if settings[slot .. "_model"] then self.providers[slot].model = settings[slot .. "_model"] end
    end
    
    self:loadLanguage()
end

function AIHelper:saveSettings(new_settings)
    local DataStorage = require("datastorage")
    local xray_dir = DataStorage:getSettingsDir() .. "/xray"
    local ok, lfs = pcall(require, "libs/libkoreader-lfs")
    if not ok or type(lfs) ~= "table" then
        ok, lfs = pcall(require, "lfs")
    end
    if not ok or type(lfs) ~= "table" then
        self:log("AIHelper: saveSettings skipped (lfs missing)")
        return
    end
    if lfs.attributes(xray_dir, "mode") ~= "directory" then
        lfs.mkdir(xray_dir)
    end

    
    self.settings = self.settings or {}
    if new_settings then
        for k, v in pairs(new_settings) do
            self.settings[k] = v
        end
    end
    
    local settings_file = xray_dir .. "/settings.json"
    local f = io.open(settings_file, "w")
    if f then
        f:write(json.encode(self.settings))
        f:close()
    end
end

function AIHelper:loadLanguage()
    local en_file = self.path .. "/prompts/en.lua"
    local ok_en, en_prompts = pcall(dofile, en_file)
    self.prompts = ok_en and en_prompts or {}
    if self.current_language ~= "en" then
        local loc_file = self.path .. "/prompts/" .. self.current_language .. ".lua"
        local ok_loc, loc_prompts = pcall(dofile, loc_file)
        if ok_loc and type(loc_prompts) == "table" then for k, v in pairs(loc_prompts) do self.prompts[k] = v end end
    end
end

function AIHelper:createPrompt(title, author, context, section_name, targeted_word)
    if not self.prompts then self:loadLanguage() end
    section_name = section_name or "character_section"
    local template = self.prompts[section_name] or self.prompts.character_section
    local enhanced_title, enhanced_author, extra_context = title or "Unknown", author or "Unknown", ""
    if context then
        if context.series then enhanced_title = enhanced_title .. " | Series: " .. context.series end
        if context.book_text then extra_context = extra_context .. "\n\nBOOK TEXT CONTEXT:\n" .. context.book_text end
        -- Chapter data is relevant for comprehensive fetches and targeted single-word lookups
        if section_name == "comprehensive_xray" or section_name == "single_word_lookup" then
            if context.chapter_titles and #context.chapter_titles > 0 then
                local numbered_chapters = {}
                for i, t in ipairs(context.chapter_titles) do
                    table.insert(numbered_chapters, string.format("%d. %s", i, t))
                end
                extra_context = extra_context .. "\n\nLIST OF CHAPTERS (Provide EXACTLY 1 event for EACH, in order):\n[TOTAL CHAPTER COUNT: " .. #context.chapter_titles .. "]\n" .. table.concat(numbered_chapters, "\n")
            end
            if context.chapter_samples then extra_context = extra_context .. "\n\nCHAPTER SAMPLES:\n" .. context.chapter_samples end
        end
        if context.annotations then extra_context = extra_context .. "\n\nUSER HIGHLIGHTS:\n" .. context.annotations end
        if context.book_type then
            extra_context = extra_context .. "\n\nCRITICAL: The book type is already known to be: " .. context.book_type .. ". You MUST declare \"book_type\" as \"" .. context.book_type .. "\" at the JSON root and follow the extraction rules for " .. context.book_type .. " books."
        end
        -- Merge mode: tell AI what we already know
        local has_merge_data = false
        local _merge_char_len = (self.settings and self.settings.char_desc_len) or 200
        local merge_instructions = "\n\nMERGE MODE INSTRUCTIONS:\nYou are UPDATING an existing X-Ray.\n- For entities (Characters, Locations, Historical Figures) that already exist, synthesize a completely rewritten, cohesive summary combining the EXISTING KNOWLEDGE with any new information found in the text.\n- Write a solid summary that is not repetitive.\n- Descriptions MUST NOT exceed " .. tostring(_merge_char_len) .. " characters.\n- If there is no new information, return the existing description (or a refined version of it under " .. tostring(_merge_char_len) .. " characters)."
        
        if context.existing_characters and #context.existing_characters > 0 then
            local existing_lines = {}
            local sample_text = context.book_text or ""
            for _, c in ipairs(context.existing_characters) do
                if c.name and c.description then
                    -- Optimized context trimming checks (Name, aliases, first-name fallback)
                    local found_in_sample = false
                    local name_lower = c.name:lower()
                    local sample_lower = sample_text:lower()
                    if sample_lower:find(name_lower, 1, true) then
                        found_in_sample = true
                    else
                        if c.aliases then
                            for _, alias in ipairs(c.aliases) do
                                if type(alias) == "string" and #alias > 1 and sample_lower:find(alias:lower(), 1, true) then
                                    found_in_sample = true; break
                                end
                            end
                        end
                        if not found_in_sample then
                            local first_name = c.name:match("^(%S+)")
                            if first_name and #first_name > 3 and sample_lower:find(first_name:lower(), 1, true) then
                                found_in_sample = true
                            end
                        end
                    end

                    if found_in_sample then
                        -- Prompt Anchoring: Send initial + latest description if history is available
                        local desc_str = c.description
                        if c.history and #c.history > 1 then
                            local initial_desc = c.history[1].description
                            local latest_desc = c.history[#c.history].description
                            if initial_desc and latest_desc and initial_desc ~= latest_desc then
                                desc_str = "Initial Introduction: " .. initial_desc .. " | Latest Status: " .. latest_desc
                            end
                        end
                        table.insert(existing_lines, "- " .. c.name .. ": " .. desc_str)
                    else
                        table.insert(existing_lines, "- " .. c.name)
                    end
                end
            end
            if #existing_lines > 0 then
                if not has_merge_data then extra_context = extra_context .. merge_instructions; has_merge_data = true end
                extra_context = extra_context .. "\n\nEXISTING CHARACTER KNOWLEDGE (Context Optimized):\n" .. table.concat(existing_lines, "\n")
            end
        end
        
        if context.existing_historical_figures and #context.existing_historical_figures > 0 then
            local existing_lines = {}
            local sample_text = context.book_text or ""
            for _, h in ipairs(context.existing_historical_figures) do
                if h.name and h.biography then
                    local found_in_sample = false
                    local name_lower = h.name:lower()
                    local sample_lower = sample_text:lower()
                    if sample_lower:find(name_lower, 1, true) then
                        found_in_sample = true
                    else
                        if h.aliases then
                            for _, alias in ipairs(h.aliases) do
                                if type(alias) == "string" and #alias > 1 and sample_lower:find(alias:lower(), 1, true) then
                                    found_in_sample = true; break
                                end
                            end
                        end
                        if not found_in_sample then
                            local first_name = h.name:match("^(%S+)")
                            if first_name and #first_name > 3 and sample_lower:find(first_name:lower(), 1, true) then
                                found_in_sample = true
                            end
                        end
                    end

                    if found_in_sample then
                        local bio_str = h.biography
                        if h.history and #h.history > 1 then
                            local initial_bio = h.history[1].biography
                            local latest_bio = h.history[#h.history].biography
                            if initial_bio and latest_bio and initial_bio ~= latest_bio then
                                bio_str = "Initial Introduction: " .. initial_bio .. " | Latest Status: " .. latest_bio
                            end
                        end
                        table.insert(existing_lines, "- " .. h.name .. ": " .. bio_str)
                    else
                        table.insert(existing_lines, "- " .. h.name)
                    end
                end
            end
            if #existing_lines > 0 then
                if not has_merge_data then extra_context = extra_context .. merge_instructions; has_merge_data = true end
                extra_context = extra_context .. "\n\nEXISTING HISTORICAL FIGURE KNOWLEDGE (Context Optimized):\n" .. table.concat(existing_lines, "\n")
            end
        end
        
        if context.existing_locations and #context.existing_locations > 0 then
            local existing_lines = {}
            local sample_text = context.book_text or ""
            for _, l in ipairs(context.existing_locations) do
                if l.name and l.description then
                    local found_in_sample = false
                    local name_lower = l.name:lower()
                    local sample_lower = sample_text:lower()
                    if sample_lower:find(name_lower, 1, true) then
                        found_in_sample = true
                    else
                        if l.aliases then
                            for _, alias in ipairs(l.aliases) do
                                if type(alias) == "string" and #alias > 1 and sample_lower:find(alias:lower(), 1, true) then
                                    found_in_sample = true; break
                                end
                            end
                        end
                        if not found_in_sample then
                            local first_name = l.name:match("^(%S+)")
                            if first_name and #first_name > 3 and sample_lower:find(first_name:lower(), 1, true) then
                                found_in_sample = true
                            end
                        end
                    end

                    if found_in_sample then
                        local desc_str = l.description
                        if l.history and #l.history > 1 then
                            local initial_desc = l.history[1].description
                            local latest_desc = l.history[#l.history].description
                            if initial_desc and latest_desc and initial_desc ~= latest_desc then
                                desc_str = "Initial Introduction: " .. initial_desc .. " | Latest Status: " .. latest_desc
                            end
                        end
                        table.insert(existing_lines, "- " .. l.name .. ": " .. desc_str)
                    else
                        table.insert(existing_lines, "- " .. l.name)
                    end
                end
            end
            if #existing_lines > 0 then
                if not has_merge_data then extra_context = extra_context .. merge_instructions; has_merge_data = true end
                extra_context = extra_context .. "\n\nEXISTING LOCATION KNOWLEDGE (Context Optimized):\n" .. table.concat(existing_lines, "\n")
            end
        end
    end
    -- Dynamically inject "aliases" into the "terms" JSON schema template.
    -- This inserts `"aliases": ["Alias 1", "Alias 2"],` before `"expanded":` translation-safely.
    if template then
        template = template:gsub('"expanded":', '"aliases": ["Alias 1", "Alias 2"],\n      "expanded":')
    end

    local p = (context and context.reading_percent) or 100
    local success, final_prompt
    if section_name == "single_word_lookup" then
        success, final_prompt = pcall(string.format, template, targeted_word or "???")
    elseif section_name == "more_characters" then
        local exclude = context.exclude_characters or ""
        success, final_prompt = pcall(string.format, template, enhanced_title, enhanced_author, p, exclude, p)
    elseif section_name == "more_terms" then
        local exclude = context.exclude_terms or "None"
        success, final_prompt = pcall(string.format, template, enhanced_title, enhanced_author, p, exclude, p)
    elseif section_name == "series_detect" then
        success, final_prompt = pcall(string.format, template, enhanced_title, enhanced_author)
    elseif section_name == "prior_book_list" then
        local idx = context and context.index or 1
        success, final_prompt = pcall(string.format, template, context.series_name or "Unknown", idx, enhanced_title, enhanced_author, idx - 1)
    elseif section_name == "series_book_summary" then
        local idx = context and context.index or 1
        success, final_prompt = pcall(string.format, template, enhanced_title, enhanced_author, idx, context.series_name or "Unknown")
    else
        success, final_prompt = pcall(string.format, template, enhanced_title, enhanced_author, p, p, p, p, p, p, p, p, p, p, p, p, p, p, p, p, p, p, p, p)
    end

    if section_name == "comprehensive_xray" or section_name == "more_terms" then
        extra_context = extra_context .. "\n- For each term, provide up to 3 alternative names, acronyms, or synonyms in an 'aliases' array. CRITICAL: These aliases MUST be variations or names that actually appear in the provided book text; do not hallucinate external synonyms."
    end
    if not success then final_prompt = string.format("Extract %s data.", section_name) end
    if #extra_context > 0 then final_prompt = final_prompt .. extra_context end

    -- Inject dynamic description-length placeholders.
    -- These replace {MAX_CHAR_DESC}, {NUM_CHARS}, etc. in all prompt templates so
    -- the user's Description Length setting is honoured without needing separate
    -- per-language prompt edits for numeric values.
    do
        local s = self.settings or {}
        local char_len  = math.max(100, math.min(500, s.char_desc_len     or 200))
        local loc_len   = math.max(50,  math.min(300, s.loc_desc_len      or 100))
        local tl_len    = math.max(50,  math.min(200, s.timeline_event_len or 80))
        local hist_len  = math.max(50,  math.min(400, s.hist_fig_bio_len  or 100))
        -- Count scaling: inversely proportional to description length, with floor/cap.
        local num_chars = math.min(40, math.max(10, math.floor(25 * 200 / char_len)))
        local num_locs  = math.min(20, math.max(3,  math.floor(8  * 100 / loc_len)))
        local num_hist  = math.min(15, math.max(3,  math.floor(8  * 100 / hist_len)))
        local term_len  = math.max(50, math.min(300, s.term_def_len or 100))
        local num_terms = 15
        final_prompt = final_prompt
            :gsub("{MAX_CHAR_DESC}",    tostring(char_len))
            :gsub("{NUM_CHARS}",        tostring(num_chars))
            :gsub("{MAX_LOC_DESC}",     tostring(loc_len))
            :gsub("{NUM_LOCS}",         tostring(num_locs))
            :gsub("{MAX_TIMELINE_EVENT}",tostring(tl_len))
            :gsub("{MAX_HIST_BIO}",     tostring(hist_len))
            :gsub("{NUM_HIST}",         tostring(num_hist))
            :gsub("{MAX_TERM_DEF}",     tostring(term_len))
            :gsub("{NUM_TERMS}",        tostring(num_terms))
    end

    -- Strip invalid UTF-8 introduced by byte-based truncation of multi-byte
    -- text (Cyrillic, CJK, curly quotes, etc.) before the prompt is JSON-encoded.
    local before_len = #final_prompt
    final_prompt = sanitize_utf8(final_prompt)
    if #final_prompt ~= before_len then
        self:log(string.format("AIHelper: sanitize_utf8 stripped %d invalid byte(s) from prompt", before_len - #final_prompt))
    end
    return final_prompt
end

function AIHelper:executeUnifiedRequest(prompt)
    local primary = self.settings.primary_ai or DEFAULT_AI.primary
    local secondary = self.settings.secondary_ai or DEFAULT_AI.secondary
    
    local models_to_try = { primary, secondary }
    local last_err = "No models configured."
    
    for _, ai in ipairs(models_to_try) do
        local config = self.providers[ai.provider]
        if not config or not config.api_key or config.api_key == "" then
            self:log("AIHelper: Skipping " .. ai.provider .. " (" .. ai.model .. ") - API Key missing")
            last_err = "API Key not set for " .. (ai.provider == "gemini" and "Google Gemini" or "ChatGPT")
        else
            self:log("AIHelper: Trying unified fallback model: " .. ai.provider .. " / " .. ai.model)
            local result, err_code, err_msg
            if ai.provider == "gemini" then
                result, err_code, err_msg = self:callGemini(prompt, config, ai.model)
            elseif ai.provider == "custom1" or ai.provider == "custom2" then
                result, err_code, err_msg = self:callChatGPT(prompt, config, ai.model or config.model)
            else
                result, err_code, err_msg = self:callChatGPT(prompt, config, ai.model)
            end
            
            if result then return result end
            self:log("AIHelper: Model failed: " .. tostring(err_msg))
            last_err = err_msg or "Unknown API Error"
        end
    end
    return nil, "error_api", last_err
end

function AIHelper:getBookDataSection(title, author, provider_name, context, section_name)
    local prompt = self:createPrompt(title, author, context, section_name)
    return self:executeUnifiedRequest(prompt)
end

function AIHelper:getAuthorData(title, author, provider_name, context)
    local prompt = self:createPrompt(title, author, context, "author_only")
    return self:executeUnifiedRequest(prompt)
end

function AIHelper:getMoreCharacters(title, author, provider_name, context)
    return self:getBookDataSection(title, author, provider_name, context, "more_characters")
end

function AIHelper:getMoreTerms(title, author, provider_name, context)
    return self:getBookDataSection(title, author, provider_name, context, "more_terms")
end

function AIHelper:startAIRequest(title, author, context, section_name, targeted_word)
    local prompt = self:createPrompt(title, author, context, section_name, targeted_word)
    local requests, error_code, error_msg = self:buildComprehensiveRequest(nil, nil, nil, prompt)
    if not requests then return nil, error_code, error_msg end
    
    local unique_id = tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))
    local result_file = self.path .. "/tmp_ai_res_" .. unique_id .. ".json"
    local pid = self:makeRequestAsync(requests, result_file)
    return pid, result_file
end

function AIHelper:lookupSingleWord(text, context)
    local prompt = self:createPrompt(nil, nil, context, "single_word_lookup", text)
    return self:executeUnifiedRequest(prompt)
end

function AIHelper:mergeDescriptionsWithAI(primary_desc, secondary_desc)
    if not self.prompts then self:loadLanguage() end
    local template = self.prompts.merge_descriptions
    if not template then
        self:log("AIHelper: merge_descriptions prompt not found, falling back.")
        return nil
    end
    
    local prompt = string.format(template, primary_desc or "", secondary_desc or "")
    local result, err_code, err_msg = self:executeUnifiedRequest(prompt)
    if result and result.merged_description then
        return result.merged_description
    end
    self:log("AIHelper: mergeDescriptionsWithAI failed: " .. tostring(err_msg))
    return nil
end

function AIHelper:callGemini(prompt, config, current_model)
    current_model = current_model or DEFAULT_AI.primary.model
    local system_instruction_text = self.prompts and self.prompts.system_instruction or "Return valid JSON ONLY."
    self:log("AIHelper: Gemini Prompt prepared")
    
    local url = "https://generativelanguage.googleapis.com/v1beta/models/" .. current_model .. ":generateContent"
    local request_body = json.encode({
        contents = {{ role = "user", parts = {{ text = prompt }} }},
        system_instruction = { parts = {{ text = system_instruction_text }} },
        safetySettings = {
            { category = "HARM_CATEGORY_SEXUALLY_EXPLICIT", threshold = "BLOCK_NONE" },
            { category = "HARM_CATEGORY_HATE_SPEECH",       threshold = "BLOCK_NONE" },
            { category = "HARM_CATEGORY_HARASSMENT",        threshold = "BLOCK_NONE" },
            { category = "HARM_CATEGORY_DANGEROUS_CONTENT", threshold = "BLOCK_NONE" }
        },
        generationConfig = { temperature = 0.2, maxOutputTokens = 16384 }
    })
    self:log("AIHelper: Sending Gemini request (" .. #request_body .. " bytes)")
    local ok, code, response_text, status = self:makeRequest(url, { ["Content-Type"] = "application/json", ["x-goog-api-key"] = config.api_key }, request_body)
    local code_num = tonumber(code)
    self:log("AIHelper: [" .. current_model .. "] Response Code: " .. tostring(code_num))
    self:log("AIHelper: [" .. current_model .. "] Response received (" .. (response_text and #response_text or 0) .. " bytes)")
    
    if code_num == 200 and response_text then
        local success, data = pcall(json.decode, response_text)
        if success and data.candidates and data.candidates[1] then
            local ai_text = ""
            local parts = data.candidates[1].content and data.candidates[1].content.parts or {}
            for _, p in ipairs(parts) do
                if p.text and not p.thought then
                    ai_text = ai_text .. p.text
                end
            end
            
            if #ai_text > 0 then
                local parsed_data, err = self:parseAIResponse(ai_text)
                if parsed_data then
                    return parsed_data
                else
                    self:log("AIHelper: [" .. current_model .. "] Parse failed: " .. tostring(err))
                    return nil, "error_parse", "Parse failed: " .. tostring(err)
                end
            end
        end
    elseif code_num == 429 then return nil, "error_quota", "Quota Exceeded (429)"
    elseif code_num == 503 then self:log("AIHelper: 503 Overload"); socket.sleep(2)
    else
        local error_detail = "HTTP " .. tostring(code_num or code or "Unknown")
        if response_text then
            local s, err_data = pcall(json.decode, response_text)
            if s and err_data and err_data.error then error_detail = err_data.error.message or error_detail end
        end
        return nil, "error_api", error_detail
    end
    return nil, "error_parse", "Failed to return valid JSON."
end

function AIHelper:callChatGPT(prompt, config, current_model)
    local model = current_model or "gpt-4o-mini"
    self:log("AIHelper: Starting ChatGPT request for model: " .. model)
    
    local legacy_models = { ["gpt-4"] = true, ["gpt-3.5-turbo"] = true, ["gpt-4-32k"] = true }
    if legacy_models[model] then
        local err = "Model '" .. model .. "' does not support JSON mode. Please use gpt-4o, gpt-4-turbo, or gpt-4o-mini."
        self:log("AIHelper: " .. err)
        return nil, "error_api", err
    end

    self:log("AIHelper: ChatGPT Prompt prepared")
    local system_instruction_text = self.prompts and self.prompts.system_instruction or "Return valid JSON ONLY."
    local is_openai_reasoning = (model:find("^gpt%-5") or model:find("^o[13]"))
    if is_openai_reasoning then
        system_instruction_text = system_instruction_text .. " You MUST output strictly valid JSON, starting with '{'."
    else
        -- OpenAI requires the word 'json' to appear somewhere in messages when using json_object mode.
        -- Append a guaranteed-ASCII sentinel so localized prompts never trigger a 400 error.
        if not system_instruction_text:lower():find("json") then
            system_instruction_text = system_instruction_text .. " Respond in JSON format."
        end
    end
    
    -- Modern models (gpt-5, o1, o3) use 'developer' role instead of 'system'
    local instruction_role = "system"
    if is_openai_reasoning then
        instruction_role = "developer"
    end

    local token_param, token_val = self:getChatGPTTokenConfig(model)
    local request_payload = { 
        model = model, 
        messages = {
            { role = instruction_role, content = system_instruction_text },
            { role = "user", content = prompt }
        }, 
        response_format = { type = "json_object" }, 
        [token_param] = token_val 
    }

    -- Add reasoning_effort if configured and supported.
    -- xhigh is a valid OpenAI API value; pass through directly.
    -- IMPORTANT: response_format={json_object} is incompatible with reasoning_effort and causes a 400.
    -- When reasoning is active, drop response_format and rely on the system prompt's JSON instruction.
    -- Also raise max_completion_tokens: GPT-5 supports 128k output; at xhigh OpenAI recommends ~25k buffer,
    -- so 65k is a safe ceiling that leaves ample room for both reasoning and the X-Ray JSON.
    if self.settings.reasoning_effort and (model:find("^gpt%-5") or model:find("^o[13]")) then
        local effort = self.settings.reasoning_effort
        request_payload.reasoning_effort = effort
        request_payload.response_format = nil  -- incompatible with reasoning_effort
        if effort == "high" or effort == "xhigh" then
            request_payload[token_param] = 65000
            self:log(string.format("AIHelper: OpenAI %s at %s effort — dropping json_object mode, raising max_completion_tokens to 65000", model, effort))
        end
    end

    local request_body = json.encode(request_payload)
    self:log("AIHelper: Sending ChatGPT request (" .. #request_body .. " bytes)")
    
    local headers = { ["Content-Type"] = "application/json", ["Authorization"] = "Bearer " .. config.api_key }
    if (config.endpoint or ""):find("openrouter.ai") then
        headers["HTTP-Referer"]       = "https://github.com/koreader/koreader-xray-plugin"
        headers["X-OpenRouter-Title"] = "KOReader X-Ray"
    end
    
    local ok, code, response_text = self:makeRequest(config.endpoint or "https://api.openai.com/v1/chat/completions", headers, request_body)
    
    local code_num = tonumber(code)
    self:log("AIHelper: ChatGPT Response Code: " .. tostring(code_num))
    self:log("AIHelper: ChatGPT Response received (" .. (response_text and #response_text or 0) .. " bytes)")
    
    if code_num == 200 and response_text then 
        local success, data = pcall(json.decode, response_text)
        if success and data.choices and data.choices[1] then
            local message = data.choices[1].message
            local content = message.content
            local reasoning = message.reasoning_content
            
            local parsed_data, err = self:parseAIResponse(content)
            if parsed_data then 
                if reasoning then
                    parsed_data.ai_reasoning = reasoning
                end
                return parsed_data 
            end
            self:log("AIHelper: ChatGPT parse failed: " .. tostring(err))
        end
    else
        local error_detail = "HTTP " .. tostring(code_num or code or "Unknown")
        if response_text then
            local s, err_data = pcall(json.decode, response_text)
            if s and err_data and err_data.error then 
                error_detail = err_data.error.message or error_detail 
            end
            self:log("AIHelper: ChatGPT API Error: " .. response_text)
        end
        return nil, "error_api", error_detail
    end
    
    return nil, "error_api", "ChatGPT failed or returned invalid JSON"
end

local function normalizeKeys(t)
    if type(t) ~= "table" then return t end
    local res = {}
    for k, v in pairs(t) do
        local new_k = type(k) == "string" and k:lower():gsub("%s+", "_") or k
        if type(v) == "table" then res[new_k] = normalizeKeys(v) else res[new_k] = v end
    end
    return res
end

function AIHelper:fixTruncatedJSON(s)
    local stack, in_string, escaped = {}, false, false
    for i = 1, #s do
        local c = s:sub(i,i)
        if escaped then escaped = false
        elseif c == "\\" then escaped = true
        elseif c == '"' then in_string = not in_string
        elseif not in_string then
            if c == "{" or c == "[" then table.insert(stack, c)
            elseif c == "}" then if #stack > 0 and stack[#stack] == "{" then table.remove(stack) end
            elseif c == "]" then if #stack > 0 and stack[#stack] == "[" then table.remove(stack) end end
        end
    end
    local res = s
    if in_string then res = res .. '"' end
    
    -- Ensure we remove any trailing commas before closing
    res = res:gsub(",%s*$", "")
    
    for i = #stack, 1, -1 do 
        if stack[i] == "{" then 
            res = res .. "}" 
        else 
            res = res .. "]" 
        end 
    end
    return res
end

-- Backward compatibility for internal calls
local fixTruncatedJSON = function(s) return AIHelper:fixTruncatedJSON(s) end

function AIHelper:parseAIResponse(text)
    if not text or #text == 0 then return nil, "Empty response" end
    
    -- Aggressively clean up markdown and find JSON boundaries
    local json_text = text:gsub("^%s+", ""):gsub("%s+$", "")
    
    -- Method 1: Clean standard markdown blocks
    if json_text:find("^```") then
        json_text = json_text:gsub("^```json%s*", ""):gsub("^```%w*%s*", ""):gsub("```%s*$", "")
    end
    
    -- Method 2: Locate first { and last } if decode fails
    local success, data = pcall(json.decode, json_text)
    if not success then
        self:log("AIHelper: JSON repair needed")
        local first = json_text:find("{", 1, true) or json_text:find("[", 1, true)
        local last_brace = json_text:reverse():find("}", 1, true)
        local last_bracket = json_text:reverse():find("]", 1, true)
        local last_rel = math.max(last_brace or 0, last_bracket or 0)
        
        if first then
             local last = (last_rel > 0) and (#json_text - last_rel + 1) or #json_text
             local extracted = json_text:sub(first, last)
             local fixed = fixTruncatedJSON(extracted)
             
             success, data = pcall(json.decode, fixed)
             if not success and rapidjson_ok then
                 local standard_json = require("json")
                 if standard_json and standard_json ~= json then 
                     success, data = pcall(standard_json.decode, fixed) 
                 end
             end
        end
    end
    
    if success and data then return self:validateAndCleanData(normalizeKeys(data)) end
    self:log("AIHelper: Parse failed. Snippet: " .. tostring(text):sub(1, 150))
    return nil, "Failed to parse JSON"
end

function AIHelper:validateAndCleanData(data)
    if not data then return nil end
    -- Pass-through for single-word lookup results or duplicate review results
    if data.is_valid ~= nil or data.duplicate_pairs ~= nil or data.DuplicatePairs ~= nil then return data end
    
    local strings = self:getFallbackStrings()
    local function ensureString(v, d) return (type(v) == "string" and #v > 0) and v or d or "" end
    
    local chars = data.characters or data.Characters or {}
    local valid_chars = {}
    for _, c in ipairs(chars) do
        if type(c) == "table" then
            table.insert(valid_chars, {
                name = ensureString(c.name or c.full_formal_name or c.full_name or c.formal_name or c.Name, strings.unnamed_character),
                role = ensureString(c.role or c.Role, strings.not_specified):sub(1, 40),
                description = ensureString(c.description or c.bio or c.history or c.desc, strings.no_description),
                gender = ensureString(c.gender or c.Gender, ""),
                occupation = ensureString(c.occupation or c.job or c.Occupation, ""),
                aliases = (type(c.aliases) == "table") and c.aliases or {}
            })
        end
    end
    data.characters = valid_chars
    
    local hists = data.historical_figures or data.historicalfigures or {}
    local valid_hists = {}
    for _, h in ipairs(hists) do
        if type(h) == "table" then
            table.insert(valid_hists, {
                name = ensureString(h.name or h.Name, strings.unnamed_person),
                biography = ensureString(h.biography or h.bio or h.description, strings.no_biography),
                role = ensureString(h.role or h.historical_role, ""):sub(1, 40),
                importance_in_book = ensureString(h.importance_in_book or h.significance, "Mentioned"),
                context_in_book = ensureString(h.context_in_book or h.context, "Historical")
            })
        end
    end
    data.historical_figures = valid_hists
    
    local locs = data.locations or data.Locations or {}
    local valid_locs = {}
    for _, l in ipairs(locs) do
        if type(l) == "table" then
            table.insert(valid_locs, {
                name = ensureString(l.name or l.place or l.Lugar, "Unknown Place"),
                description = ensureString(l.description or l.desc or l.short_desc, ""),
                importance = ensureString(l.importance or l.significance, "")
            })
        end
    end
    data.locations = valid_locs
    
    data.timeline = data.timeline or data.Timeline or {}
    
    -- Sanitize author info if present
    if data.author or data.author_bio or data.author_birth or data.author_death then
        local strings = self:getFallbackStrings()
        local function ensureString(v, d) return (type(v) == "string" and #v > 0) and v or d or "" end
        data.author = ensureString(data.author, strings.unknown_author)
        data.author_bio = ensureString(data.author_bio, strings.no_biography)
        data.author_birth = ensureString(data.author_birth, "---")
        data.author_death = ensureString(data.author_death, "---")
    end
    
    return data
end

function AIHelper:getFallbackStrings()
    return self.prompts and self.prompts.fallback or {}
end

function AIHelper:setAPIKey(p, k) 
    self.providers[p].api_key = k
    self.providers[p].ui_key_active = true
    self:saveSettings({ [p .. "_api_key"] = k, [p .. "_use_ui_key"] = true })
    return true 
end

function AIHelper:setCustomAPIConfig(slot, key, endpoint, model)
    -- slot is "custom1" or "custom2"
    self.providers[slot].api_key        = key
    self.providers[slot].endpoint       = endpoint
    self.providers[slot].model          = model
    self.providers[slot].ui_key_active  = true
    self:saveSettings({
        [slot .. "_api_key"]    = key,
        [slot .. "_use_ui_key"] = true,
        [slot .. "_endpoint"]   = endpoint,
        [slot .. "_model"]      = model,
    })
    return true
end

function AIHelper:setUnifiedModel(type, provider, model)
    if type == "primary" then
        self.settings.primary_ai = { provider = provider, model = model }
    elseif type == "secondary" then
        self.settings.secondary_ai = { provider = provider, model = model }
    end
    self:saveSettings()
    return true
end

function AIHelper:findDuplicates(title, author, entities, entity_type_label, reading_percent)
    if not self.prompts then self:loadLanguage() end
    local template = self.prompts.find_duplicates
    if not template then return nil, "no_prompt", "find_duplicates prompt missing" end

    -- Build compact list string
    local lines = {}
    for _, e in ipairs(entities) do
        local line = "- " .. (e.name or "?")
        -- Include aliases if present (characters)
        if e.aliases and type(e.aliases) == "table" and #e.aliases > 0 then
            line = line .. " (aka: " .. table.concat(e.aliases, ", ") .. ")"
        end
        -- Include a truncated description for context
        local desc = e.description or e.biography or ""
        if #desc > 0 then
            line = line .. ": " .. desc:sub(1, 100)
        end
        table.insert(lines, line)
    end

    local p = reading_percent or 100
    local prompt = string.format(template,
        title or "Unknown", author or "Unknown",
        p, entity_type_label or "entities",
        table.concat(lines, "\n"), p
    )
    prompt = self:sanitize_utf8(prompt)

    local result, err_code, err_msg = self:executeUnifiedRequest(prompt)
    if result and type(result.duplicate_pairs) == "table" then
        return result.duplicate_pairs
    end
    return nil, err_code or "error_parse", err_msg or "No duplicate_pairs in response"
end

function AIHelper:findDuplicatesAsync(title, author, entities, entity_type_label, reading_percent, result_file)
    if not self.prompts then self:loadLanguage() end
    local template = self.prompts.find_duplicates
    if not template then return nil, "no_prompt", "find_duplicates prompt missing" end

    -- Build compact list string
    local lines = {}
    for _, e in ipairs(entities) do
        local line = "- " .. (e.name or "?")
        if e.aliases and type(e.aliases) == "table" and #e.aliases > 0 then
            line = line .. " (aka: " .. table.concat(e.aliases, ", ") .. ")"
        end
        local desc = e.description or e.biography or ""
        if #desc > 0 then
            line = line .. ": " .. desc:sub(1, 100)
        end
        table.insert(lines, line)
    end

    local p = reading_percent or 100
    local prompt = string.format(template,
        title or "Unknown", author or "Unknown",
        p, entity_type_label or "entities",
        table.concat(lines, "\n"), p
    )
    prompt = self:sanitize_utf8(prompt)

    local requests, error_code, error_msg = self:buildComprehensiveRequest(nil, nil, nil, prompt)
    if not requests then return nil, error_code or "error_build", error_msg or "Failed to build request" end

    local pid = self:makeRequestAsync(requests, result_file)
    return pid
end

return AIHelper
