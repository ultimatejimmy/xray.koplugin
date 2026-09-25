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

    describe("flattenTOC", function()
        it("flattens a nested TOC structure with array children", function()
            local nested_toc = {
                { title = "Title Page", page = 1 },
                {
                    title = "Part I", page = 2,
                    { title = "Chapter 1", page = 3 },
                    { title = "Chapter 2", page = 10, { title = "Section 2.1", page = 12 } }
                },
                { title = "Part II", page = 20 }
            }

            local flat = utils:flattenTOC(nested_toc)
            assert.are.equal(6, #flat)
            assert.are.equal("Title Page", flat[1].title)
            assert.are.equal("Part I", flat[2].title)
            assert.are.equal("Chapter 1", flat[3].title)
            assert.are.equal("Chapter 2", flat[4].title)
            assert.are.equal("Section 2.1", flat[5].title)
            assert.are.equal("Part II", flat[6].title)
        end)
    end)

    describe("detectProviderFromKey", function()
        it("detects modern Google Gemini AQ.* keys", function()
            local prov, key = utils:detectProviderFromKey("AQ.TEST_GEMINI_MOCK_KEY_1234567890abcdef")
            assert.are.equal("gemini", prov)
            assert.are.equal("AQ.TEST_GEMINI_MOCK_KEY_1234567890abcdef", key)
        end)

        it("detects classic Google Gemini AIza* keys", function()
            local prov, key = utils:detectProviderFromKey("AIzaSyD-9xK1234567890abcdefghijklmnopqr")
            assert.are.equal("gemini", prov)
            assert.are.equal("AIzaSyD-9xK1234567890abcdefghijklmnopqr", key)
        end)

        it("detects Anthropic Claude sk-ant-* keys", function()
            local prov, key = utils:detectProviderFromKey("sk-ant-api03-abcdef1234567890ghijklmnopqrstuv")
            assert.are.equal("claude", prov)
            assert.are.equal("sk-ant-api03-abcdef1234567890ghijklmnopqrstuv", key)
        end)

        it("detects OpenRouter sk-or-* keys", function()
            local prov, key = utils:detectProviderFromKey("sk-or-v1-abcdef1234567890abcdef1234567890")
            assert.are.equal("custom1", prov)
            assert.are.equal("sk-or-v1-abcdef1234567890abcdef1234567890", key)
        end)

        it("detects OpenAI sk-proj-* and sk-* keys", function()
            local prov, key = utils:detectProviderFromKey("sk-proj-abcdef1234567890abcdef1234567890")
            assert.are.equal("chatgpt", prov)
            assert.are.equal("sk-proj-abcdef1234567890abcdef1234567890", key)
        end)
    end)

    describe("utf8Lower", function()
        it("lowercases ASCII text", function()
            assert.are.equal("hello world", utils:utf8Lower("HELLO WORLD"))
            assert.are.equal("john watson", utils:utf8Lower("John Watson"))
        end)

        it("lowercases Cyrillic text (Russian, Ukrainian, Serbian, Belarusian, Macedonian)", function()
            assert.are.equal("раскольников", utils:utf8Lower("Раскольников"))
            assert.are.equal("раскольников", utils:utf8Lower("РАСКОЛЬНИКОВ"))
            assert.are.equal("война и мир", utils:utf8Lower("Война и Мир"))
            assert.are.equal("ёж", utils:utf8Lower("ЁЖ"))
            assert.are.equal("київ", utils:utf8Lower("КИЇВ"))
            assert.are.equal("україна", utils:utf8Lower("Україна"))
            assert.are.equal("беларусь", utils:utf8Lower("БЕЛАРУСЬ"))
            assert.are.equal("крагујевац", utils:utf8Lower("Крагујевац"))
        end)

        it("lowercases Latin Extended & accented characters", function()
            assert.are.equal("émile zola", utils:utf8Lower("ÉMILE ZOLA"))
            assert.are.equal("łódź", utils:utf8Lower("ŁÓDŹ"))
            assert.are.equal("kraków", utils:utf8Lower("KRAKÓW"))
            assert.are.equal("čapek", utils:utf8Lower("ČAPEK"))
            assert.are.equal("žižek", utils:utf8Lower("ŽIŽEK"))
        end)

        it("lowercases Greek text", function()
            assert.are.equal("αθήνα", utils:utf8Lower("ΑΘΉΝΑ"))
            assert.are.equal("σωκράτησ", utils:utf8Lower("ΣΩΚΡΆΤΗΣ"))
            assert.are.equal("ελλάδα", utils:utf8Lower("ΕΛΛΆΔΑ"))
        end)
    end)

    describe("trimPunctuation", function()
        it("trims ASCII punctuation and whitespace", function()
            assert.are.equal("Hello", utils:trimPunctuation("...Hello!"))
            assert.are.equal("John's", utils:trimPunctuation("  John's  "))
            assert.are.equal("Watson", utils:trimPunctuation("Watson,"))
        end)

        it("trims Unicode quotes, guillemets, and dashes without harming Cyrillic letters", function()
            assert.are.equal("Раскольников", utils:trimPunctuation("«Раскольников»"))
            assert.are.equal("Раскольников", utils:trimPunctuation("“Раскольников”"))
            assert.are.equal("Раскольников", utils:trimPunctuation("—Раскольников—"))
            assert.are.equal("Раскольников", utils:trimPunctuation("...Раскольников!"))
            assert.are.equal("Война и мир", utils:trimPunctuation("«Война и мир»"))
        end)

        it("trims CJK punctuation", function()
            assert.are.equal("阿Q", utils:trimPunctuation("「阿Q」"))
            assert.are.equal("红楼梦", utils:trimPunctuation("《红楼梦》"))
            assert.are.equal("贾宝玉", utils:trimPunctuation("【贾宝玉】"))
        end)
    end)

    describe("Arabic & CJK script detection", function()
        it("detects Arabic script correctly", function()
            assert.is_true(utils:textHasArabic("باريستان سلمي"))
            assert.is_true(utils:textHasArabic("فارس وحارس الملكة"))
            assert.is_true(utils:textHasArabic("Aliases: باريستان الجسور"))
            assert.is_false(utils:textHasArabic("Barristan Selmy"))
            assert.is_false(utils:textHasArabic("Раскольников"))
            assert.is_false(utils:textHasArabic("红楼梦"))
            assert.is_false(utils:textHasArabic(""))
            assert.is_false(utils:textHasArabic(nil))
        end)

        it("detects Arabic font families correctly", function()
            assert.is_true(utils:isArabicFontFamily("Amiri"))
            assert.is_true(utils:isArabicFontFamily("Noto Sans Arabic"))
            assert.is_true(utils:isArabicFontFamily("Scheherazade New"))
            assert.is_true(utils:isArabicFontFamily("Naskh Regular"))
            assert.is_false(utils:isArabicFontFamily("Bookerly"))
            assert.is_false(utils:isArabicFontFamily("Noto Serif"))
            assert.is_false(utils:isArabicFontFamily(nil))
        end)

        it("detects Arabic in entities", function()
            local ar_entity = {
                name = "باريستان سلمي",
                role = "Supporting Protagonist",
                description = "فارس شجاع ومخلص يخدم كحارس لملكة ميرين",
            }
            assert.is_true(utils:entityHasArabic(ar_entity))

            local en_entity = {
                name = "Barristan Selmy",
                role = "Supporting Protagonist",
                description = "A bold knight.",
            }
            assert.is_false(utils:entityHasArabic(en_entity))
        end)

        it("detects CJK in entities", function()
            local cjk_entity = {
                name = "贾宝玉",
                role = "Protagonist",
                description = "红楼梦主角",
            }
            assert.is_true(utils:entityHasCJK(cjk_entity))

            local en_entity = {
                name = "Barristan Selmy",
                role = "Supporting Protagonist",
                description = "A bold knight.",
            }
            assert.is_false(utils:entityHasCJK(en_entity))
        end)
    end)
end)

