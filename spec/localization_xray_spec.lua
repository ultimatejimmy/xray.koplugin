-- spec/localization_xray_spec.lua
require("spec.spec_helper")

local json = require("json")
local utils = require("xray_utils")
local DataStorage = require("datastorage")

describe("Localization and Atomic File Operations (Issue #164)", function()
    local test_dir = "/tmp/koreader_test_issue_164"
    local settings_dir = test_dir .. "/settings"
    local xray_dir = settings_dir .. "/xray"
    local settings_file = xray_dir .. "/settings.json"

    before_each(function()
        os.execute("rm -rf " .. test_dir)
        os.execute("mkdir -p " .. xray_dir)
        DataStorage.getSettingsDir = function() return settings_dir end
    end)

    after_each(function()
        os.execute("rm -rf " .. test_dir)
    end)

    describe("xray_utils:atomicWriteFile", function()
        it("writes file content successfully", function()
            local target = test_dir .. "/test_atomic.json"
            local content = '{"test":123,"status":"ok"}'
            local ok, err = utils:atomicWriteFile(target, content)
            assert.is_true(ok)
            assert.is_nil(err)

            local f = io.open(target, "r")
            assert.is_not_nil(f)
            local read_back = f:read("*a")
            f:close()
            assert.are.equal(content, read_back)
        end)

        it("overwrites existing file cleanly", function()
            local target = test_dir .. "/test_overwrite.json"
            utils:atomicWriteFile(target, '{"initial":true}')
            local ok = utils:atomicWriteFile(target, '{"updated":true}')
            assert.is_true(ok)

            local f = io.open(target, "r")
            local read_back = f:read("*a")
            f:close()
            assert.are.equal('{"updated":true}', read_back)
        end)
    end)

    describe("Localization:saveLanguageToJson", function()
        local Localization

        before_each(function()
            package.loaded["localization_xray"] = nil
            Localization = require("localization_xray")
            Localization.available_languages = { "en", "de", "fr", "es" }
        end)

        it("does not rewrite settings.json if language is already the same", function()
            local initial_data = { language = "en", provider = "gemini", api_key = "secret" }
            utils:atomicWriteFile(settings_file, json.encode(initial_data))

            -- Modify mtime or verify file write avoidance by checking content
            local ok = Localization:saveLanguageToJson(xray_dir, settings_file, "en")
            assert.is_true(ok)

            local f = io.open(settings_file, "r")
            local decoded = json.decode(f:read("*a"))
            f:close()
            assert.are.equal("secret", decoded.api_key)
            assert.are.equal("gemini", decoded.provider)
            assert.are.equal("en", decoded.language)
        end)

        it("does not overwrite 'auto' preference with resolved language", function()
            local initial_data = { language = "auto", provider = "gemini", model = "flash" }
            utils:atomicWriteFile(settings_file, json.encode(initial_data))

            -- Calling saveLanguageToJson with resolved language "en"
            local ok = Localization:saveLanguageToJson(xray_dir, settings_file, "en")
            assert.is_true(ok)

            local f = io.open(settings_file, "r")
            local decoded = json.decode(f:read("*a"))
            f:close()
            assert.are.equal("auto", decoded.language)
            assert.are.equal("gemini", decoded.provider)
        end)

        it("does not overwrite 'book' preference with resolved language", function()
            local initial_data = { language = "book", provider = "chatgpt" }
            utils:atomicWriteFile(settings_file, json.encode(initial_data))

            local ok = Localization:saveLanguageToJson(xray_dir, settings_file, "fr")
            assert.is_true(ok)

            local f = io.open(settings_file, "r")
            local decoded = json.decode(f:read("*a"))
            f:close()
            assert.are.equal("book", decoded.language)
            assert.are.equal("chatgpt", decoded.provider)
        end)

        it("does NOT overwrite damaged or cut-short settings.json", function()
            local corrupted_content = '{"provider":"gemini","gemini_api_key":"my-valuable-key",'
            local f = io.open(settings_file, "w")
            f:write(corrupted_content)
            f:close()

            local ok = Localization:saveLanguageToJson(xray_dir, settings_file, "en")
            assert.is_false(ok)

            -- The corrupted file must NOT have been replaced with {"language":"en"}!
            local check_f = io.open(settings_file, "r")
            local actual_content = check_f:read("*a")
            check_f:close()
            assert.are.equal(corrupted_content, actual_content)
        end)

        it("updates language when user selects a different concrete language", function()
            local initial_data = { language = "en", provider = "gemini" }
            utils:atomicWriteFile(settings_file, json.encode(initial_data))

            local ok = Localization:saveLanguageToJson(xray_dir, settings_file, "de")
            assert.is_true(ok)

            local f = io.open(settings_file, "r")
            local decoded = json.decode(f:read("*a"))
            f:close()
            assert.are.equal("de", decoded.language)
            assert.are.equal("gemini", decoded.provider)
        end)
    end)

    describe("Localization:setLanguage", function()
        local Localization

        before_each(function()
            package.loaded["localization_xray"] = nil
            Localization = require("localization_xray")
            Localization.available_languages = { "en", "de", "fr" }
            Localization.current_language = "en"
            Localization.translations = { test_key = "Hello" }
        end)

        it("returns true immediately without reloading if language is already active", function()
            local reloaded = false
            Localization.loadTranslations = function()
                reloaded = true
            end

            local result = Localization:setLanguage("en")
            assert.is_true(result)
            assert.is_false(reloaded)
        end)

        it("reloads translations when switching to a different language", function()
            local reloaded_lang = nil
            Localization.loadTranslations = function(self)
                reloaded_lang = self.current_language
            end

            local result = Localization:setLanguage("de")
            assert.is_true(result)
            assert.are.equal("de", Localization.current_language)
            assert.are.equal("de", reloaded_lang)
        end)
    end)

    describe("AIHelper settings backup on corruption", function()
        it("backs up corrupted settings.json to settings.json.corrupted", function()
            local corrupted_content = '{"default_provider":"gemini", incomplete_json...'
            local f = io.open(settings_file, "w")
            f:write(corrupted_content)
            f:close()

            package.loaded["xray_aihelper"] = nil
            local AIHelper = require("xray_aihelper")
            AIHelper.path = "xray.koplugin"
            AIHelper:loadSettings()

            local bak_file = settings_file .. ".corrupted"
            local bak_f = io.open(bak_file, "r")
            assert.is_not_nil(bak_f)
            local backed_up_content = bak_f:read("*a")
            bak_f:close()
            assert.are.equal(corrupted_content, backed_up_content)
        end)
    end)
end)
