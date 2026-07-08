-- xray_units_spec.lua
require("spec/spec_helper")

describe("xray_units", function()
    local xray_units

    setup(function()
        xray_units = require("xray_units")
    end)

    describe("convert", function()
        it("converts feet to meters", function()
            local res = xray_units.convert(6, "length", "feet", "m")
            assert.is_true(math.abs(res - 1.8288) < 0.0001)
        end)

        it("converts inches to cm", function()
            local res = xray_units.convert(10, "length", "inch", "cm")
            assert.is_true(math.abs(res - 25.4) < 0.0001)
        end)

        it("converts miles to km", function()
            local res = xray_units.convert(5, "length", "miles", "km")
            assert.is_true(math.abs(res - 8.04672) < 0.0001)
        end)

        it("converts lbs to kg", function()
            local res = xray_units.convert(150, "weight", "lbs", "kg")
            assert.is_true(math.abs(res - 68.0388) < 0.001)
        end)

        it("converts Fahrenheit to Celsius", function()
            local res_hot = xray_units.convert(212, "temp", "f", "c")
            local res_cold = xray_units.convert(32, "temp", "f", "c")
            assert.are.equal(100, res_hot)
            assert.are.equal(0, res_cold)
        end)

        it("converts Celsius to Fahrenheit", function()
            local res = xray_units.convert(37, "temp", "c", "f")
            assert.is_true(math.abs(res - 98.6) < 0.001)
        end)

        it("converts mph to km/h", function()
            local res = xray_units.convert(60, "speed", "mph", "km/h")
            assert.is_true(math.abs(res - 96.5606) < 0.01)
        end)

        it("converts gallons to L", function()
            local res = xray_units.convert(2, "volume", "gallon", "l")
            assert.is_true(math.abs(res - 7.57082) < 0.001)
        end)

        it("converts acres to hectares", function()
            local res = xray_units.convert(10, "area", "acres", "ha")
            assert.is_true(math.abs(res - 4.0468) < 0.001)
        end)
    end)

    describe("formatNumber", function()
        it("uses dot separator for English locale", function()
            local res = xray_units.formatNumber(1.88, "en")
            assert.are.equal("1.88", res)
        end)

        it("uses comma separator for German locale", function()
            local res = xray_units.formatNumber(1.88, "de")
            assert.are.equal("1,88", res)
        end)

        it("strips trailing zeros", function()
            local res1 = xray_units.formatNumber(1.50, "en")
            local res2 = xray_units.formatNumber(2.00, "en")
            assert.are.equal("1.5", res1)
            assert.are.equal("2", res2)
        end)

        it("falls back to dot separator if locale is nil", function()
            local res = xray_units.formatNumber(3.14, nil)
            assert.are.equal("3.14", res)
        end)
    end)

    describe("detectMeasurements", function()
        it("detects numeric + unit: '5 miles'", function()
            local res = xray_units.detectMeasurements("She walked 5 miles in the snow.")
            assert.are.equal(1, #res)
            assert.are.equal("5 miles", res[1].original)
            assert.are.equal("8.05 km", res[1].converted)
            assert.are.equal("length", res[1].category)
        end)

        it("detects compound length: '6 feet 2 inches'", function()
            local res = xray_units.detectMeasurements("He stands 6 feet 2 inches tall.")
            assert.are.equal(1, #res)
            assert.are.equal("6 feet 2 inches", res[1].original)
            assert.are.equal("1.88 m", res[1].converted)
            assert.are.equal("length", res[1].category)
        end)

        it("detects compound symbols: 6'2\"", function()
            local res = xray_units.detectMeasurements("He stands 6'2\" tall.")
            assert.are.equal(1, #res)
            assert.are.equal("6'2\"", res[1].original)
            assert.are.equal("1.88 m", res[1].converted)
            assert.are.equal("length", res[1].category)
        end)

        it("detects compound weights: '10 st 4 lb'", function()
            local res = xray_units.detectMeasurements("The package weighs 10 st 4 lb.")
            assert.are.equal(1, #res)
            assert.are.equal("10 st 4 lb", res[1].original)
            assert.are.equal("65.32 kg", res[1].converted)
            assert.are.equal("weight", res[1].category)
        end)

        it("detects temperatures with degree symbol: '98.6°F', '37°C', '37 °C'", function()
            local res1 = xray_units.detectMeasurements("Body temperature is 98.6°F.")
            assert.are.equal(1, #res1)
            assert.are.equal("98.6°F", res1[1].original)
            assert.are.equal("37 °C", res1[1].converted)

            local res2 = xray_units.detectMeasurements("It is 37°C outside.", "to_imperial")
            assert.are.equal(1, #res2)
            assert.are.equal("37°C", res2[1].original)
            assert.are.equal("98.6 °F", res2[1].converted)

            local res3 = xray_units.detectMeasurements("Water boils at 100 °C.", "to_imperial")
            assert.are.equal(1, #res3)
            assert.are.equal("100 °C", res3[1].original)
            assert.are.equal("212 °F", res3[1].converted)
        end)

        it("detects negative temperatures: '-10°F', '−10°C'", function()
            local res1 = xray_units.detectMeasurements("It is -10°F in the freezer.")
            assert.are.equal(1, #res1)
            assert.are.equal("-10°F", res1[1].original)
            assert.are.equal("-23.33 °C", res1[1].converted)

            -- Unicode minus sign
            local res2 = xray_units.detectMeasurements("It is −10°C outside.", "to_imperial")
            assert.are.equal(1, #res2)
            assert.are.equal("−10°C", res2[1].original)
            assert.are.equal("14 °F", res2[1].converted)
        end)

        it("detects singular, misspelled and variant temperatures: '80 degree Celcius', '80 degrees Celcius', '1 degree fahrenheit'", function()
            local res1 = xray_units.detectMeasurements("The liquid is at 80 degree Celcius.", "to_imperial")
            assert.are.equal(1, #res1)
            assert.are.equal("80 degree Celcius", res1[1].original)
            assert.are.equal("176 °F", res1[1].converted)

            local res1_plural = xray_units.detectMeasurements("The liquid is at 80 degrees Celcius.", "to_imperial")
            assert.are.equal(1, #res1_plural)
            assert.are.equal("80 degrees Celcius", res1_plural[1].original)
            assert.are.equal("176 °F", res1_plural[1].converted)

            local res1_correct_plural = xray_units.detectMeasurements("The liquid is at 80 degrees Celsius.", "to_imperial")
            assert.are.equal(1, #res1_correct_plural)
            assert.are.equal("80 degrees Celsius", res1_correct_plural[1].original)
            assert.are.equal("176 °F", res1_correct_plural[1].converted)

            local res1_correct_singular = xray_units.detectMeasurements("The liquid is at 80 degree Celsius.", "to_imperial")
            assert.are.equal(1, #res1_correct_singular)
            assert.are.equal("80 degree Celsius", res1_correct_singular[1].original)
            assert.are.equal("176 °F", res1_correct_singular[1].converted)

            local res2 = xray_units.detectMeasurements("It is 1 degree fahrenheit.", "to_metric")
            assert.are.equal(1, #res2)
            assert.are.equal("1 degree fahrenheit", res2[1].original)
            assert.are.equal("-17.22 °C", res2[1].converted)
        end)

        it("detects units at end-of-string: '2 m'", function()
            local res = xray_units.detectMeasurements("The height is 2 m", "to_imperial")
            assert.are.equal(1, #res)
            assert.are.equal("2 m", res[1].original)
            assert.are.equal("6.56 feet", res[1].converted)
        end)

        it("avoids mid-digit false matches: '140 lbs' does not match '40 lbs'", function()
            local res = xray_units.detectMeasurements("He weighs 140 lbs.")
            assert.are.equal(1, #res)
            assert.are.equal("140 lbs", res[1].original)
            assert.are.equal("63.5 kg", res[1].converted)
        end)

        it("detects localized unit names: '5 kilómetros', '5 millas', '5 meilen'", function()
            local res1 = xray_units.detectMeasurements("caminó 5 kilómetros hoy.", "to_imperial", nil, "es")
            assert.are.equal(1, #res1)
            assert.are.equal("5 kilómetros", res1[1].original)
            assert.are.equal("3,11 miles", res1[1].converted)

            local res2 = xray_units.detectMeasurements("la isla está a 5 millas.", "to_metric", nil, "es")
            assert.are.equal(1, #res2)
            assert.are.equal("5 millas", res2[1].original)
            assert.are.equal("8,05 km", res2[1].converted)

            local res3 = xray_units.detectMeasurements("Es sind 5 Meilen bis dahin.", "to_metric", nil, "de")
            assert.are.equal(1, #res3)
            assert.are.equal("5 Meilen", res3[1].original)
            assert.are.equal("8,05 km", res3[1].converted)
        end)

        it("detects written numbers: 'three miles'", function()
            local res = xray_units.detectMeasurements("The cabin is three miles away.")
            assert.are.equal(1, #res)
            assert.are.equal("three miles", res[1].original)
            assert.are.equal("4.83 km", res[1].converted)
            assert.are.equal("length", res[1].category)

            local res2 = xray_units.detectMeasurements("He walked and ten meters today.", "to_imperial")
            assert.are.equal(1, #res2)
            assert.are.equal("ten meters", res2[1].original)
            assert.are.equal("32.81 feet", res2[1].converted)

            -- Test for "one fifty kph"
            local res3 = xray_units.detectMeasurements("The speed limit is one fifty kph.", "to_imperial")
            assert.are.equal(1, #res3)
            assert.are.equal("one fifty kph", res3[1].original)
            assert.are.equal("93.21 mph", res3[1].converted)

            -- Test for "two thousand one fifty"
            local res4 = xray_units.detectMeasurements("The altitude is two thousand one fifty meters.", "to_imperial")
            assert.are.equal(1, #res4)
            assert.are.equal("two thousand one fifty meters", res4[1].original)
            assert.are.equal("7,053.81 feet", res4[1].converted)

            -- Test for "quarter mile"
            local res5 = xray_units.detectMeasurements("He ran a quarter mile.", "to_metric")
            assert.are.equal(1, #res5)
            assert.are.equal("a quarter mile", res5[1].original)
            assert.are.equal("0.4 km", res5[1].converted)

            -- Test for "one and a quarter miles"
            local res6 = xray_units.detectMeasurements("It was one and a quarter miles away.", "to_metric")
            assert.are.equal(1, #res6)
            assert.are.equal("one and a quarter miles", res6[1].original)
            assert.are.equal("2.01 km", res6[1].converted)
        end)

        it("ignores non-measurement uses of unit words", function()
            local res1 = xray_units.detectMeasurements("He has cold feet.")
            local res2 = xray_units.detectMeasurements("I paid ten pounds sterling.")
            assert.are.equal(0, #res1)
        end)

        it("handles multiple measurements on the same line", function()
            local res = xray_units.detectMeasurements("The run was 5 miles long, and I drank 2 gallons of water.")
            assert.are.equal(2, #res)
            assert.are.equal("5 miles", res[1].original)
            assert.are.equal("2 gallons", res[2].original)
        end)

        it("respects enabled categories settings", function()
            local enabled_cats = { length = true, weight = false, temp = false, volume = false, speed = false, area = false }
            local res = xray_units.detectMeasurements("It weighs 10 lbs and is 5 feet long.", "to_metric", enabled_cats)
            assert.are.equal(1, #res)
            assert.are.equal("5 feet", res[1].original)
        end)
        it("detects spelling variants: 'kilogrammes', 'millimetres'", function()
            local res1 = xray_units.detectMeasurements("It weighs 5 kilogrammes.", "to_imperial")
            assert.are.equal(1, #res1)
            assert.are.equal("5 kilogrammes", res1[1].original)
            assert.are.equal("11.02 lb", res1[1].converted)

            local res2 = xray_units.detectMeasurements("The thickness is 450 mm.", "to_imperial")
            assert.are.equal(1, #res2)
            assert.are.equal("450 mm", res2[1].original)
            assert.are.equal("17.72 inches", res2[1].converted)
        end)

        it("handles unit pluralization correctly", function()
            local res1 = xray_units.detectMeasurements("1 meter", "to_imperial")
            assert.are.equal("3.28 feet", res1[1].converted)

            local res2 = xray_units.detectMeasurements("0.3048 m", "to_imperial")
            -- 0.3048 m = 1 foot. Since it is exactly 1, it should remain singular "foot"
            assert.are.equal("1 foot", res2[1].converted)

            local res3 = xray_units.detectMeasurements("0.5 m", "to_imperial")
            assert.are.equal("1.64 feet", res3[1].converted)
        end)

        it("detects vague quantifiers: 'a few hundred yards'", function()
            local res = xray_units.detectMeasurements("a few hundred yards away.", "to_metric")
            assert.are.equal(1, #res)
            assert.are.equal("a few hundred yards", res[1].original)
            assert.are.equal("≈182.88–457.2 m", res[1].converted)
            assert.is_true(res[1].vague)
        end)

        it("handles thousand-separator commas: '400,000 kilometers'", function()
            local res = xray_units.detectMeasurements("It is 400,000 kilometers away.", "to_imperial")
            assert.are.equal(1, #res)
            assert.are.equal("400,000 kilometers", res[1].original)
            assert.are.equal("248,548.48 miles", res[1].converted)
        end)

        it("detects half expressions: 'half a kilometer'", function()
            local res = xray_units.detectMeasurements("He walked half a kilometer.", "to_imperial")
            assert.are.equal(1, #res)
            assert.are.equal("half a kilometer", res[1].original)
            assert.are.equal("0.31 miles", res[1].converted)
        end)

        it("detects hyphenated prefixed units: '384,000-kilometer'", function()
            local res = xray_units.detectMeasurements("a 384,000-kilometer distance.", "to_imperial")
            -- Note: detectMeasurements is used here, so the trailing hyphen in the original text is stripped
            -- inside scanBookForUnits, but detectMeasurements matches clean suffixes. Let's make sure it parses.
            assert.are.equal(1, #res)
            assert.are.equal("384,000-kilometer", res[1].original)
        end)

        it("ignores non-English ASCII false positives like 'ons'", function()
            local res1 = xray_units.detectMeasurements("fifty corporations")
            local res2 = xray_units.detectMeasurements("forty thousand tons")
            assert.are.equal(0, #res1)
            assert.are.equal(0, #res2)
        end)
    end)

    describe("getDefaultDirection", function()
        it("returns to_imperial when device setting is imperial (imperial)", function()
            _G.G_reader_settings = {
                readSetting = function(_, key)
                    if key == "dimension_units" then return "imperial" end
                end
            }
            assert.are.equal("to_imperial", xray_units.getDefaultDirection())
        end)

        it("returns to_imperial when device setting is imperial (in)", function()
            _G.G_reader_settings = {
                readSetting = function(_, key)
                    if key == "dimension_units" then return "in" end
                end
            }
            assert.are.equal("to_imperial", xray_units.getDefaultDirection())
        end)

        it("returns to_metric when device setting is metric (metric)", function()
            _G.G_reader_settings = {
                readSetting = function(_, key)
                    if key == "dimension_units" then return "metric" end
                end
            }
            assert.are.equal("to_metric", xray_units.getDefaultDirection())
        end)

        it("returns to_metric when device setting is metric (mm)", function()
            _G.G_reader_settings = {
                readSetting = function(_, key)
                    if key == "dimension_units" then return "mm" end
                end
            }
            assert.are.equal("to_metric", xray_units.getDefaultDirection())
        end)

        it("returns to_metric when device setting is nil", function()
            _G.G_reader_settings = {
                readSetting = function() return nil end
            }
            assert.are.equal("to_metric", xray_units.getDefaultDirection())
        end)
    end)

    describe("auto direction resolution", function()
        it("resolves auto to to_metric and only returns imperial aliases when device setting is metric", function()
            _G.G_reader_settings = {
                readSetting = function(_, key)
                    if key == "dimension_units" then return "metric" end
                end
            }
            local aliases = xray_units.getScanAliases("auto")
            local has_km = false
            for _, a in ipairs(aliases) do
                if a == "km" then has_km = true end
            end
            assert.is_false(has_km)

            local has_mile = false
            for _, a in ipairs(aliases) do
                if a == "mile" or a == "miles" then has_mile = true end
            end
            assert.is_true(has_mile)

            local res = xray_units.detectMeasurements("The run was 5 miles and 10 km.", "auto")
            assert.are.equal(1, #res)
            assert.are.equal("5 miles", res[1].original)
        end)

        it("resolves auto to to_imperial and only returns metric aliases when device setting is imperial", function()
            _G.G_reader_settings = {
                readSetting = function(_, key)
                    if key == "dimension_units" then return "imperial" end
                end
            }
            local aliases = xray_units.getScanAliases("auto")
            local has_mile = false
            for _, a in ipairs(aliases) do
                if a == "mile" or a == "miles" then has_mile = true end
            end
            assert.is_false(has_mile)

            local has_km = false
            for _, a in ipairs(aliases) do
                if a == "km" then has_km = true end
            end
            assert.is_true(has_km)

            local res = xray_units.detectMeasurements("The run was 5 miles and 10 km.", "auto")
            assert.are.equal(1, #res)
            assert.are.equal("10 km", res[1].original)
        end)
    end)
end)
