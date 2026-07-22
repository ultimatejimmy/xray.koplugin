-- xray_utils_spec.lua
require("spec.spec_helper")
local utils = require("xray_utils")
local device = require("device")

describe("xray_utils", function()
    it("identifies PW1 (K5) as a low power device", function()
        device.isKindle = function() return true end
        device.getModel = function() return "K5" end
        assert.is_true(utils:isLowPowerDevice())
    end)

    it("identifies modern devices as not low power", function()
        device.isKindle = function() return true end
        device.getModel = function() return "K11" end -- Newer Kindle
        assert.is_false(utils:isLowPowerDevice())
    end)

    it("identifies older Kobo devices as low power", function()
        device.isKindle = function() return false end
        device.isKobo = function() return true end
        device.isKoboV2 = function() return false end
        assert.is_true(utils:isLowPowerDevice())
    end)

    describe("isLowPowerForScan", function()
        it("identifies modern Kindles (K11) as low power for scanning", function()
            device.isKindle = function() return true end
            device.isKobo = function() return false end
            device.isPocketBook = function() return false end
            device.isAndroid = function() return false end
            assert.is_true(utils:isLowPowerForScan())
        end)

        it("identifies WSL/desktop as not low power for scanning", function()
            device.isKindle = function() return false end
            device.isKobo = function() return false end
            device.isPocketBook = function() return false end
            device.isAndroid = function() return false end
            assert.is_false(utils:isLowPowerForScan())
        end)
    end)

    describe("getFriendlyError", function()
        local loc = {
            t = function(self, key, arg)
                if arg then return key .. ":" .. tostring(arg) end
                return key
            end
        }

        it("maps error_quota to quota exceeded", function()
            local title, desc = utils:getFriendlyError("error_quota", nil, loc)
            assert.are.equal("error_quota_title", title)
            assert.are.equal("error_quota_desc", desc)
        end)

        it("maps error_timeout to timeout", function()
            local title, desc = utils:getFriendlyError("error_timeout", nil, loc)
            assert.are.equal("error_timeout_title", title)
            assert.are.equal("error_timeout_desc", desc)
        end)

        it("maps 401 API error to invalid api key", function()
            local title, desc = utils:getFriendlyError("error_api", "401 Unauthorized", loc)
            assert.are.equal("error_api_key_title", title)
            assert.are.equal("error_api_key_desc", desc)
        end)

        it("maps 403 API error to permission denied", function()
            local title, desc = utils:getFriendlyError("error_api", "403 Forbidden", loc)
            assert.are.equal("error_model_access_title", title)
            assert.are.equal("error_model_access_desc", desc)
        end)

        it("maps 429 API error to quota exceeded", function()
            local title, desc = utils:getFriendlyError("error_api", "Error 429: Rate Limit", loc)
            assert.are.equal("error_quota_title", title)
            assert.are.equal("error_quota_desc", desc)
        end)

        it("maps 503 API error to service unavailable", function()
            local title, desc = utils:getFriendlyError("error_api", "503 Service Unavailable", loc)
            assert.are.equal("error_service_down_title", title)
            assert.are.equal("error_service_down_desc", desc)
        end)

        it("maps 404 API error to model not found", function()
            local title, desc = utils:getFriendlyError("error_api", "404 Not Found", loc)
            assert.are.equal("error_model_not_found_title", title)
            assert.are.equal("error_model_not_found_desc", desc)
        end)

        it("surfaces 400 API error details instead of blaming the API key", function()
            -- Issue #86: a 400 is a malformed/rejected request (e.g. invalid
            -- model name), not an authentication failure. Show the detail.
            local title, desc = utils:getFriendlyError("error_api", "HTTP 400: custom1 is not a valid model ID", loc)
            assert.are.equal("error_unknown_title", title)
            assert.are.equal("error_unknown_desc:HTTP 400: custom1 is not a valid model ID", desc)
        end)

        it("handles unknown errors by returning the raw message", function()
            local title, desc = utils:getFriendlyError("error_something_weird", "Crazy error", loc)
            assert.are.equal("error_unknown_title", title)
            assert.are.equal("error_unknown_desc:Crazy error", desc)
        end)
    end)
end)
