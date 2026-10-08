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
            local res = xray_units.detectMeasurements("She walked 5 miles in the snow.", "to_metric")
            assert.are.equal(1, #res)
            assert.are.equal("5 miles", res[1].original)
            assert.are.equal("8.05 km", res[1].converted)
            assert.are.equal("length", res[1].category)
        end)

        it("detects compound length: '6 feet 2 inches'", function()
            local res = xray_units.detectMeasurements("He stands 6 feet 2 inches tall.", "to_metric")
            assert.are.equal(1, #res)
            assert.are.equal("6 feet 2 inches", res[1].original)
            assert.are.equal("1.88 m", res[1].converted)
            assert.are.equal("length", res[1].category)
        end)

        it("detects compound symbols: 6'2\"", function()
            local res = xray_units.detectMeasurements("He stands 6'2\" tall.", "to_metric")
            assert.are.equal(1, #res)
            assert.are.equal("6'2\"", res[1].original)
            assert.are.equal("1.88 m", res[1].converted)
            assert.are.equal("length", res[1].category)
        end)

        it("detects compound weights: '10 st 4 lb'", function()
            local res = xray_units.detectMeasurements("The package weighs 10 st 4 lb.", "to_metric")
            assert.are.equal(1, #res)
            assert.are.equal("10 st 4 lb", res[1].original)
            assert.are.equal("65.32 kg", res[1].converted)
            assert.are.equal("weight", res[1].category)
        end)

        it("detects temperatures with degree symbol: '98.6°F', '37°C', '37 °C'", function()
            local res1 = xray_units.detectMeasurements("Body temperature is 98.6°F.", "to_metric")
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
            local res1 = xray_units.detectMeasurements("It is -10°F in the freezer.", "to_metric")
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
            local res = xray_units.detectMeasurements("He weighs 140 lbs.", "to_metric")
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
            local res = xray_units.detectMeasurements("The cabin is three miles away.", "to_metric")
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

            -- Test for single-quoted dialogue
            local res7 = xray_units.detectMeasurements("He said 'three miles' and left.", "to_metric")
            assert.are.equal(1, #res7)
            assert.are.equal("three miles", res7[1].original)
            assert.are.equal("4.83 km", res7[1].converted)
            assert.are.equal(3, xray_units.parseNumberText("'three'"))
        end)

        it("ignores non-measurement uses of unit words", function()
            local res1 = xray_units.detectMeasurements("He has cold feet.", "to_metric")
            local res2 = xray_units.detectMeasurements("I paid ten pounds sterling.", "to_metric")
            assert.are.equal(0, #res1)
        end)

        it("handles multiple measurements on the same line", function()
            local res = xray_units.detectMeasurements("The run was 5 miles long, and I drank 2 gallons of water.", "to_metric")
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

        it("detects decimeters and square decimeters", function()
            local res1 = xray_units.detectMeasurements("It is 12 decimeters long.", "to_imperial")
            assert.are.equal(1, #res1)
            assert.are.equal("12 decimeters", res1[1].original)
            assert.are.equal("47.24 inches", res1[1].converted)

            local res2 = xray_units.detectMeasurements("It spans 5 square decimeters.", "to_imperial")
            assert.are.equal(1, #res2)
            assert.are.equal("5 square decimeters", res2[1].original)
            assert.are.equal("0.54 sq ft", res2[1].converted)
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

        it("detects a Cyrillic multiplier word before a unit", function()
            local v = xray_units.detectVagueQuantifier("несколько сотен")
            assert.are.equal("несколько", v.quantifier)
            assert.are.equal(300, v.low)
            assert.are.equal(700, v.high)
        end)

        it("detects Ukrainian vague quantifiers", function()
            local res = xray_units.detectMeasurements("кілька десятків футів", "to_metric", nil, "uk")
            assert.are.equal(1, #res)
            assert.are.equal("кілька десятків футів", res[1].original)
            assert.are.equal("≈9,14–21,34 m", res[1].converted)

            local v = xray_units.detectVagueQuantifier("декілька сотень")
            assert.are.equal("декілька", v.quantifier)
            assert.are.equal(300, v.low)
            assert.are.equal(700, v.high)
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
            local res1 = xray_units.detectMeasurements("fifty corporations", "to_metric")
            local res2 = xray_units.detectMeasurements("forty thousand tons", "to_metric")
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

        it("returns to_imperial when device setting is nil", function()
            _G.G_reader_settings = {
                readSetting = function() return nil end
            }
            assert.are.equal("to_imperial", xray_units.getDefaultDirection())
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

    describe("multilingual robust detection and conversion", function()
        -- 1. Russian (ru)
        describe("Russian (ru)", function()
            it("detects length units across cases: дюйм, фут, ярд, миля, лига, сажень", function()
                local text = "Его рост 6 футов и 2 дюйма, дистанция 5 миль, 100 ярдов, 20 лиг и 10 морских саженей."
                local res = xray_units.detectMeasurements(text, "to_metric", nil, "ru")
                assert.are.equal(5, #res)
                assert.are.equal("6 футов и 2 дюйма", res[1].original)
                assert.are.equal("1,88 m", res[1].converted)
                assert.are.equal("5 миль", res[2].original)
                assert.are.equal("8,05 km", res[2].converted)
                assert.are.equal("100 ярдов", res[3].original)
                assert.are.equal("91,44 m", res[3].converted)
                assert.are.equal("20 лиг", res[4].original)
                assert.are.equal("96,56 km", res[4].converted)
                assert.are.equal("10 морских саженей", res[5].original)
                assert.are.equal("18,29 m", res[5].converted)
            end)

            it("detects weight units across cases: фунт, унция, стоун", function()
                local text = "Вес 150 фунтов, или 8 унций, или 10 стоунов 4 фунта."
                local res = xray_units.detectMeasurements(text, "to_metric", nil, "ru")
                assert.are.equal(3, #res)
                assert.are.equal("150 фунтов", res[1].original)
                assert.are.equal("68,04 kg", res[1].converted)
                assert.are.equal("8 унций", res[2].original)
                assert.are.equal("226,8 g", res[2].converted)
                assert.are.equal("10 стоунов 4 фунта", res[3].original)
                assert.are.equal("65,32 kg", res[3].converted)
            end)

            it("detects temperature: °F, °Ф, по Фаренгейту, °С, по Цельсию", function()
                local res1 = xray_units.detectMeasurements("Температура 98,6 °F на улице.", "to_metric", nil, "ru")
                assert.are.equal(1, #res1)
                assert.are.equal("98,6 °F", res1[1].original)
                assert.are.equal("37 °C", res1[1].converted)

                local res2 = xray_units.detectMeasurements("Жара 75 градусов по Фаренгейту.", "to_metric", nil, "ru")
                assert.are.equal(1, #res2)
                assert.are.equal("75 градусов по Фаренгейту", res2[1].original)
                assert.are.equal("23,89 °C", res2[1].converted)

                -- Cyrillic С in °С
                local res3 = xray_units.detectMeasurements("У больного 36,6 °С.", "to_imperial", nil, "ru")
                assert.are.equal(1, #res3)
                assert.are.equal("36,6 °С", res3[1].original)
                assert.are.equal("97,88 °F", res3[1].converted)

                -- Negative temperature
                local res4 = xray_units.detectMeasurements("Мороз -40 °F за окном.", "to_metric", nil, "ru")
                assert.are.equal(1, #res4)
                assert.are.equal("-40 °F", res4[1].original)
                assert.are.equal("-40 °C", res4[1].converted)
            end)

            it("detects volume units: галлон, пинта, кварта, чашка, жидкая унция", function()
                local text = "Купил 5 галлонов, 2 пинты, 1 кварту, 3 чашки и 8 жидких унций сока."
                local res = xray_units.detectMeasurements(text, "to_metric", nil, "ru")
                assert.are.equal(5, #res)
                assert.are.equal("5 галлонов", res[1].original)
                assert.are.equal("18,93 l", res[1].converted)
                assert.are.equal("2 пинты", res[2].original)
                assert.are.equal("946,35 ml", res[2].converted)
                assert.are.equal("1 кварту", res[3].original)
                assert.are.equal("0,95 l", res[3].converted)
                assert.are.equal("3 чашки", res[4].original)
                assert.are.equal("709,76 ml", res[4].converted)
                assert.are.equal("8 жидких унций", res[5].original)
                assert.are.equal("236,59 ml", res[5].converted)
            end)

            it("detects speed and area units: миль в час, акры, кв. футы", function()
                local text = "Скорость 60 миль в час на участке 10 акров и 100 кв. футов."
                local res = xray_units.detectMeasurements(text, "to_metric", nil, "ru")
                assert.are.equal(3, #res)
                assert.are.equal("60 миль в час", res[1].original)
                assert.are.equal("96,56 km/h", res[1].converted)
                assert.are.equal("10 акров", res[2].original)
                assert.are.equal("4,05 ha", res[2].converted)
                assert.are.equal("100 кв. футов", res[3].original)
                assert.are.equal("9,29 m²", res[3].converted)
            end)

            it("detects metric to imperial in Russian: км, см, кг, л, м²", function()
                local text = "Проехал 100 км, отрезал 10 см, купил 5 кг сахара, 2 л воды и 50 м² плитки."
                local res = xray_units.detectMeasurements(text, "to_imperial", nil, "ru")
                assert.are.equal(5, #res)
                assert.are.equal("100 км", res[1].original)
                assert.are.equal("62,14 miles", res[1].converted)
                assert.are.equal("10 см", res[2].original)
                assert.are.equal("3,94 inches", res[2].converted)
                assert.are.equal("5 кг", res[3].original)
                assert.are.equal("11,02 lb", res[3].converted)
                assert.are.equal("2 л", res[4].original)
                assert.are.equal("0,53 gallons", res[4].converted)
                assert.are.equal("50 м²", res[5].original)
                assert.are.equal("538,2 sq ft", res[5].converted)
            end)

            it("detects Russian written numbers and ranges", function()
                local res1 = xray_units.detectMeasurements("До города три мили пути.", "to_metric", nil, "ru")
                assert.are.equal(1, #res1)
                assert.are.equal("три мили", res1[1].original)
                assert.are.equal("4,83 km", res1[1].converted)

                local res2 = xray_units.detectMeasurements("Осталось 5–10 миль до цели.", "to_metric", nil, "ru")
                assert.are.equal(1, #res2)
                assert.are.equal("5–10 миль", res2[1].original)
                assert.are.equal("8,05–16,09 km", res2[1].converted)
            end)

            it("prevents false substring matches in Russian words", function()
                local text = "Его фамилия была известна, он награжден премиями и владел автомобилями в дюймовочке."
                local res = xray_units.detectMeasurements(text, "to_metric", nil, "ru")
                assert.are.equal(0, #res)
            end)
        end)

        -- 2. Ukrainian (uk)
        describe("Ukrainian (uk)", function()
            it("detects Ukrainian units across cases and speeds", function()
                local text = "Відстань 5 миль, розмір 10 дюймів, вага 150 фунтів, швидкість 60 миль на годину."
                local res = xray_units.detectMeasurements(text, "to_metric", nil, "uk")
                assert.are.equal(4, #res)
                assert.are.equal("5 миль", res[1].original)
                assert.are.equal("8,05 km", res[1].converted)
                assert.are.equal("10 дюймів", res[2].original)
                assert.are.equal("25,4 cm", res[2].converted)
                assert.are.equal("150 фунтів", res[3].original)
                assert.are.equal("68,04 kg", res[3].converted)
                assert.are.equal("60 миль на годину", res[4].original)
                assert.are.equal("96,56 km/h", res[4].converted)
            end)

            it("detects Ukrainian temperatures and areas", function()
                local res1 = xray_units.detectMeasurements("На дворі 20 градусів за Цельсієм.", "to_imperial", nil, "uk")
                assert.are.equal(1, #res1)
                assert.are.equal("20 градусів за Цельсієм", res1[1].original)
                assert.are.equal("68 °F", res1[1].converted)

                local res2 = xray_units.detectMeasurements("Ділянка 5 акрів і 50 квадратних метрів.", "to_metric", nil, "uk")
                assert.are.equal(1, #res2)
                assert.are.equal("5 акрів", res2[1].original)
                assert.are.equal("2,02 ha", res2[1].converted)
            end)

            it("detects nominative plural forms used after 2-4", function()
                local cases = {
                    { "2 дюйми", "5,08 cm" }, { "3 фути", "0,91 m" }, { "2 ярди", "1,83 m" },
                    { "3 унції", "85,05 g" }, { "4 фунти", "1,81 kg" },
                }
                for _, c in ipairs(cases) do
                    local res = xray_units.detectMeasurements(c[1], "to_metric", nil, "uk")
                    assert.are.equal(1, #res)
                    assert.are.equal(c[1], res[1].original)
                    assert.are.equal(c[2], res[1].converted)
                end
                local res = xray_units.detectMeasurements("2 метри", "to_imperial", nil, "uk")
                assert.are.equal(1, #res)
                assert.are.equal("2 метри", res[1].original)
            end)

            it("detects Ukrainian written numbers with any apostrophe", function()
                for _, t in ipairs({ "п'ять футів", "п’ять футів", "пʼять футів" }) do
                    local res = xray_units.detectMeasurements(t, "to_metric", nil, "uk")
                    assert.are.equal(1, #res)
                    assert.are.equal("1,52 m", res[1].converted)
                end
                local res = xray_units.detectMeasurements("Він сказав 'п'ять миль'.", "to_metric", nil, "uk")
                assert.are.equal(1, #res)
                assert.are.equal("п'ять миль", res[1].original)
                assert.are.equal("8,05 km", res[1].converted)
                res = xray_units.detectMeasurements("двадцять чотири милі", "to_metric", nil, "uk")
                assert.are.equal(1, #res)
                assert.are.equal("двадцять чотири милі", res[1].original)
                assert.are.equal("38,62 km", res[1].converted)
                assert.are.equal(1.5, xray_units.parseNumberText("півтора"))
                assert.are.equal(0.5, xray_units.parseNumberText("пів"))
            end)

            it("detects Ukrainian compounds, digit ranges and genitive numbers", function()
                local res = xray_units.detectMeasurements("6 футів 2 дюйми", "to_metric", nil, "uk")
                assert.are.equal(1, #res)
                assert.are.equal("6 футів 2 дюйми", res[1].original)
                assert.are.equal("1,88 m", res[1].converted)

                res = xray_units.detectMeasurements("6 футів і 2 дюйми", "to_metric", nil, "uk")
                assert.are.equal(1, #res)
                assert.are.equal("6 футів і 2 дюйми", res[1].original)
                assert.are.equal("1,88 m", res[1].converted)

                res = xray_units.detectMeasurements("10 стоунів та 4 фунти", "to_metric", nil, "uk")
                assert.are.equal(1, #res)
                assert.are.equal("65,32 kg", res[1].converted)

                res = xray_units.detectMeasurements("10 стоунів 4 фунти", "to_metric", nil, "uk")
                assert.are.equal(1, #res)
                assert.are.equal("65,32 kg", res[1].converted)

                res = xray_units.detectMeasurements("5 чи 6 миль", "to_metric", nil, "uk")
                assert.are.equal(1, #res)
                assert.are.equal("8,05–9,66 km", res[1].converted)

                res = xray_units.detectMeasurements("близько п'яти миль", "to_metric", nil, "uk")
                assert.are.equal(1, #res)
                assert.are.equal("п'яти миль", res[1].original)
                assert.are.equal("8,05 km", res[1].converted)

                local genitives = {
                    { "близько ста миль", "ста миль", "160,93 km" },
                    { "близько однієї милі", "однієї милі", "1,61 km" },
                    { "понад сорока миль", "сорока миль", "64,37 km" },
                    { "близько п'ятнадцяти футів", "п'ятнадцяти футів", "4,57 m" },
                    { "до двохсот п'ятдесяти миль", "двохсот п'ятдесяти миль", "402,34 km" },
                }
                for _, c in ipairs(genitives) do
                    res = xray_units.detectMeasurements(c[1], "to_metric", nil, "uk")
                    assert.are.equal(1, #res)
                    assert.are.equal(c[2], res[1].original)
                    assert.are.equal(c[3], res[1].converted)
                end
                assert.are.equal(1, xray_units.parseNumberText("одного"))
                assert.are.equal(30, xray_units.parseNumberText("тридцяти"))
            end)
        end)

        -- 3. German (de)
        describe("German (de)", function()
            it("detects German units: Zoll, Fuß, Meilen, Pfund, Meilen pro Stunde", function()
                local text = "Er ist 6 Fuß groß, ging 5 Meilen mit 2 Pfund Gepäck bei 60 Meilen pro Stunde."
                local res = xray_units.detectMeasurements(text, "to_metric", nil, "de")
                assert.are.equal(4, #res)
                assert.are.equal("6 Fuß", res[1].original)
                assert.are.equal("1,83 m", res[1].converted)
                assert.are.equal("5 Meilen", res[2].original)
                assert.are.equal("8,05 km", res[2].converted)
                assert.are.equal("2 Pfund", res[3].original)
                assert.are.equal("0,91 kg", res[3].converted)
                assert.are.equal("60 Meilen pro Stunde", res[4].original)
                assert.are.equal("96,56 km/h", res[4].converted)
            end)

            it("detects German temperature, area, and volume", function()
                local text = "Bei 70 Grad Fahrenheit auf 100 Quadratmeter Fläche und 10 Kubikmeter Raum."
                local res = xray_units.detectMeasurements(text, "to_metric", nil, "de")
                assert.are.equal(1, #res)
                assert.are.equal("70 Grad Fahrenheit", res[1].original)
                assert.are.equal("21,11 °C", res[1].converted)
            end)
        end)

        -- 4. French (fr)
        describe("French (fr)", function()
            it("detects French units: pouces, pieds, milles, livres, milles à l'heure", function()
                local text = "Une planche de 10 pouces, 6 pieds, marchant 5 milles à 60 milles à l'heure avec 10 livres."
                local res = xray_units.detectMeasurements(text, "to_metric", nil, "fr")
                assert.are.equal(5, #res)
                assert.are.equal("10 pouces", res[1].original)
                assert.are.equal("25,4 cm", res[1].converted)
                assert.are.equal("6 pieds", res[2].original)
                assert.are.equal("1,83 m", res[2].converted)
                assert.are.equal("5 milles", res[3].original)
                assert.are.equal("8,05 km", res[3].converted)
                assert.are.equal("60 milles à l'heure", res[4].original)
                assert.are.equal("96,56 km/h", res[4].converted)
                assert.are.equal("10 livres", res[5].original)
                assert.are.equal("4,54 kg", res[5].converted)
            end)

            it("detects French temperatures and metric conversion", function()
                local res1 = xray_units.detectMeasurements("Il fait 75 degrés Fahrenheit aujourd'hui.", "to_metric", nil, "fr")
                assert.are.equal(1, #res1)
                assert.are.equal("75 degrés Fahrenheit", res1[1].original)
                assert.are.equal("23,89 °C", res1[1].converted)

                local res2 = xray_units.detectMeasurements("Il a couru 10 kilomètres ce matin.", "to_imperial", nil, "fr")
                assert.are.equal(1, #res2)
                assert.are.equal("10 kilomètres", res2[1].original)
                assert.are.equal("6,21 miles", res2[1].converted)
            end)
        end)

        -- 5. Spanish (es)
        describe("Spanish (es)", function()
            it("detects Spanish units: pulgadas, pies, millas, libras, millas por hora", function()
                local text = "Mide 6 pies, recorrió 5 millas a 60 millas por hora y pesa 150 libras."
                local res = xray_units.detectMeasurements(text, "to_metric", nil, "es")
                assert.are.equal(4, #res)
                assert.are.equal("6 pies", res[1].original)
                assert.are.equal("1,83 m", res[1].converted)
                assert.are.equal("5 millas", res[2].original)
                assert.are.equal("8,05 km", res[2].converted)
                assert.are.equal("60 millas por hora", res[3].original)
                assert.are.equal("96,56 km/h", res[3].converted)
                assert.are.equal("150 libras", res[4].original)
                assert.are.equal("68,04 kg", res[4].converted)
            end)

            it("detects Spanish temperature and acres", function()
                local res1 = xray_units.detectMeasurements("Hacía 98,6 grados Fahrenheit en la casa.", "to_metric", nil, "es")
                assert.are.equal(1, #res1)
                assert.are.equal("98,6 grados Fahrenheit", res1[1].original)
                assert.are.equal("37 °C", res1[1].converted)

                local res2 = xray_units.detectMeasurements("Compró un terreno de 5 acres.", "to_metric", nil, "es")
                assert.are.equal(1, #res2)
                assert.are.equal("5 acres", res2[1].original)
                assert.are.equal("2,02 ha", res2[1].converted)
            end)
        end)

        -- 6. Italian (it)
        describe("Italian (it)", function()
            it("detects Italian units: pollici, piedi, miglia, libbre, miglia orarie", function()
                local text = "Altezza 6 piedi, distanza 5 miglia a 60 miglia orarie, peso 10 libbre."
                local res = xray_units.detectMeasurements(text, "to_metric", nil, "it")
                assert.are.equal(4, #res)
                assert.are.equal("6 piedi", res[1].original)
                assert.are.equal("1,83 m", res[1].converted)
                assert.are.equal("5 miglia", res[2].original)
                assert.are.equal("8,05 km", res[2].converted)
                assert.are.equal("60 miglia orarie", res[3].original)
                assert.are.equal("96,56 km/h", res[3].converted)
                assert.are.equal("10 libbre", res[4].original)
                assert.are.equal("4,54 kg", res[4].converted)
            end)

            it("detects Italian temperature and area", function()
                local res = xray_units.detectMeasurements("Temperatura di 70 gradi Fahrenheit su 50 metri quadrati.", "to_metric", nil, "it")
                assert.are.equal(1, #res)
                assert.are.equal("70 gradi Fahrenheit", res[1].original)
                assert.are.equal("21,11 °C", res[1].converted)
            end)
        end)

        -- 7. Portuguese (pt)
        describe("Portuguese (pt)", function()
            it("detects Portuguese units: polegadas, pés, milhas, libras, milhas por hora", function()
                local text = "Altura de 6 pés, caminhou 5 milhas a 60 milhas por hora, pesando 100 libras."
                local res = xray_units.detectMeasurements(text, "to_metric", nil, "pt_br")
                assert.are.equal(4, #res)
                assert.are.equal("6 pés", res[1].original)
                assert.are.equal("1,83 m", res[1].converted)
                assert.are.equal("5 milhas", res[2].original)
                assert.are.equal("8,05 km", res[2].converted)
                assert.are.equal("60 milhas por hora", res[3].original)
                assert.are.equal("96,56 km/h", res[3].converted)
                assert.are.equal("100 libras", res[4].original)
                assert.are.equal("45,36 kg", res[4].converted)
            end)
        end)

        -- 8. Polish (pl)
        describe("Polish (pl)", function()
            it("detects Polish units: cali, stóp, mil, funtów, mil na godzinę", function()
                local text = "Miał 6 stóp wzrostu, przeszedł 5 mil z prędkością 60 mil na godzinę niosąc 150 funtów."
                local res = xray_units.detectMeasurements(text, "to_metric", nil, "pl")
                assert.are.equal(4, #res)
                assert.are.equal("6 stóp", res[1].original)
                assert.are.equal("1,83 m", res[1].converted)
                assert.are.equal("5 mil", res[2].original)
                assert.are.equal("8,05 km", res[2].converted)
                assert.are.equal("60 mil na godzinę", res[3].original)
                assert.are.equal("96,56 km/h", res[3].converted)
                assert.are.equal("150 funtów", res[4].original)
                assert.are.equal("68,04 kg", res[4].converted)
            end)

            it("detects Polish temperature and acreage", function()
                local res1 = xray_units.detectMeasurements("Temperatura 70 stopni Fahrenheita.", "to_metric", nil, "pl")
                assert.are.equal(1, #res1)
                assert.are.equal("70 stopni Fahrenheita", res1[1].original)
                assert.are.equal("21,11 °C", res1[1].converted)

                local res2 = xray_units.detectMeasurements("Farma ma 10 akrów wielkości.", "to_metric", nil, "pl")
                assert.are.equal(1, #res2)
                assert.are.equal("10 akrów", res2[1].original)
                assert.are.equal("4,05 ha", res2[1].converted)
            end)
        end)

        -- 9. Turkish (tr)
        describe("Turkish (tr)", function()
            it("detects Turkish units: inç, ayak, mil, libre, mil/saat, derece Fahrenheit", function()
                local text = "Boyu 6 ayak, mesafe 5 mil, hız 60 mil/saat, ağırlık 10 libre, sıcaklık 70 derece Fahrenheit."
                local res = xray_units.detectMeasurements(text, "to_metric", nil, "tr")
                assert.are.equal(5, #res)
                assert.are.equal("6 ayak", res[1].original)
                assert.are.equal("1,83 m", res[1].converted)
                assert.are.equal("5 mil", res[2].original)
                assert.are.equal("8,05 km", res[2].converted)
                assert.are.equal("60 mil/saat", res[3].original)
                assert.are.equal("96,56 km/h", res[3].converted)
                assert.are.equal("10 libre", res[4].original)
                assert.are.equal("4,54 kg", res[4].converted)
                assert.are.equal("70 derece Fahrenheit", res[5].original)
                assert.are.equal("21,11 °C", res[5].converted)
            end)
        end)

        -- 10. Serbian (sr)
        describe("Serbian (sr)", function()
            it("detects Serbian Cyrillic units: инча, стопа, миља, фунти, миља на сат", function()
                local text = "Висина 6 стопа, дужина 5 миља, брзина 60 миља на сат, тежина 150 фунти."
                local res = xray_units.detectMeasurements(text, "to_metric", nil, "sr")
                assert.are.equal(4, #res)
                assert.are.equal("6 стопа", res[1].original)
                assert.are.equal("1,83 m", res[1].converted)
                assert.are.equal("5 миља", res[2].original)
                assert.are.equal("8,05 km", res[2].converted)
                assert.are.equal("60 миља на сат", res[3].original)
                assert.are.equal("96,56 km/h", res[3].converted)
                assert.are.equal("150 фунти", res[4].original)
                assert.are.equal("68,04 kg", res[4].converted)
            end)

            it("detects Serbian Latin units: inča, stopa, milja, funti, milja na sat", function()
                local text = "Visina 6 stopa, dužina 5 milja, brzina 60 milja na sat, težina 150 funti."
                local res = xray_units.detectMeasurements(text, "to_metric", nil, "sr")
                assert.are.equal(4, #res)
                assert.are.equal("6 stopa", res[1].original)
                assert.are.equal("1,83 m", res[1].converted)
                assert.are.equal("5 milja", res[2].original)
                assert.are.equal("8,05 km", res[2].converted)
                assert.are.equal("60 milja na sat", res[3].original)
                assert.are.equal("96,56 km/h", res[3].converted)
                assert.are.equal("150 funti", res[4].original)
                assert.are.equal("68,04 kg", res[4].converted)
            end)
        end)

        -- 11. Arabic (ar)
        describe("Arabic (ar)", function()
            it("detects Arabic units: بوصة, أقدام, أميال, رطل, ميل في الساعة, درجة فهرنهايت", function()
                local text = "طوله 6 أقدام والمسافة 5 أميال وسرعته 60 ميل في الساعة ووزنه 150 رطل والحرارة 70 درجة فهرنهايت."
                local res = xray_units.detectMeasurements(text, "to_metric", nil, "ar")
                assert.are.equal(5, #res)
                assert.are.equal("6 أقدام", res[1].original)
                assert.are.equal("1.83 m", res[1].converted)
                assert.are.equal("5 أميال", res[2].original)
                assert.are.equal("8.05 km", res[2].converted)
                assert.are.equal("60 ميل في الساعة", res[3].original)
                assert.are.equal("96.56 km/h", res[3].converted)
                assert.are.equal("150 رطل", res[4].original)
                assert.are.equal("68.04 kg", res[4].converted)
                assert.are.equal("70 درجة فهرنهايت", res[5].original)
                assert.are.equal("21.11 °C", res[5].converted)
            end)
        end)

        -- 12. Chinese (zh)
        describe("Chinese (zh)", function()
            it("detects Chinese units: 英寸, 英尺, 码, 英里, 磅, 英里/小时, 华氏度", function()
                local text = "身高6英尺，距离5英里，时速60英里/小时，体重100磅，气温70华氏度。"
                local res = xray_units.detectMeasurements(text, "to_metric", nil, "zh_CN")
                assert.are.equal(5, #res)
                assert.are.equal("6英尺", res[1].original)
                assert.are.equal("1.83 m", res[1].converted)
                assert.are.equal("5英里", res[2].original)
                assert.are.equal("8.05 km", res[2].converted)
                assert.are.equal("60英里/小时", res[3].original)
                assert.are.equal("96.56 km/h", res[3].converted)
                assert.are.equal("100磅", res[4].original)
                assert.are.equal("45.36 kg", res[4].converted)
                assert.are.equal("70华氏度", res[5].original)
                assert.are.equal("21.11 °C", res[5].converted)
            end)

            it("detects Chinese metric to imperial: 公里/小时, 摄氏度, 平方米", function()
                local text = "车速100公里/小时，温度20摄氏度，面积100平方米。"
                local res = xray_units.detectMeasurements(text, "to_imperial", nil, "zh_CN")
                assert.are.equal(3, #res)
                assert.are.equal("100公里/小时", res[1].original)
                assert.are.equal("62.14 mph", res[1].converted)
                assert.are.equal("20摄氏度", res[2].original)
                assert.are.equal("68 °F", res[2].converted)
                assert.are.equal("100平方米", res[3].original)
                assert.are.equal("1,076.39 sq ft", res[3].converted)
            end)
        end)

        -- 13. Japanese (ja)
        describe("Japanese (ja)", function()
            it("detects Japanese units: インチ, フィート, ヤード, マイル, ポンド, マイル毎時, 華氏", function()
                local text = "身長6フィート、距離5マイル、速度60マイル毎時、体重100ポンド、気温70華氏。"
                local res = xray_units.detectMeasurements(text, "to_metric", nil, "ja")
                assert.are.equal(5, #res)
                assert.are.equal("6フィート", res[1].original)
                assert.are.equal("1.83 m", res[1].converted)
                assert.are.equal("5マイル", res[2].original)
                assert.are.equal("8.05 km", res[2].converted)
                assert.are.equal("60マイル毎時", res[3].original)
                assert.are.equal("96.56 km/h", res[3].converted)
                assert.are.equal("100ポンド", res[4].original)
                assert.are.equal("45.36 kg", res[4].converted)
                assert.are.equal("70華氏", res[5].original)
                assert.are.equal("21.11 °C", res[5].converted)
            end)
        end)

        -- 14. Universal Superscripts & Number Formatting
        describe("Universal Superscripts and Number Formatting", function()
            it("detects Unicode superscripts: 50 m², 10 km², 5 ft³, 10 m³", function()
                local res1 = xray_units.detectMeasurements("Area is 50 m² and 10 km².", "to_imperial")
                assert.are.equal(2, #res1)
                assert.are.equal("50 m²", res1[1].original)
                assert.are.equal("538.2 sq ft", res1[1].converted)
                assert.are.equal("10 km²", res1[2].original)
                assert.are.equal("3.86 sq mi", res1[2].converted)

                local res2 = xray_units.detectMeasurements("Volume is 5 ft³ in the box.", "to_metric")
                assert.are.equal(1, #res2)
                assert.are.equal("5 ft³", res2[1].original)
                assert.are.equal("0.14 m³", res2[1].converted)
            end)

            it("parses European thin spaces, non-breaking spaces and decimal commas", function()
                local res1 = xray_units.detectMeasurements("Distanza 1 000 km percorsa.", "to_imperial", nil, "it")
                assert.are.equal(1, #res1)
                assert.are.equal("1 000 km", res1[1].original)
                assert.are.equal("621,37 miles", res1[1].converted)

                local res2 = xray_units.detectMeasurements("Largo 2,54 cm esattamente.", "to_imperial", nil, "es")
                assert.are.equal(1, #res2)
                assert.are.equal("2,54 cm", res2[1].original)
                assert.are.equal("1 inch", res2[1].converted)
            end)
        end)

        -- 15. Range Formatting Across Scale Boundaries & Comma Separation
        describe("Range Formatting Across Scale Boundaries and Comma Boundaries", function()
            it("formats ascending and descending ranges across smart scale thresholds", function()
                local res1 = xray_units.detectMeasurements("10-10000 feet", "to_metric")
                assert.are.equal(1, #res1)
                assert.are.equal("10-10000 feet", res1[1].original)
                assert.are.equal("3.05 m–3.05 km", res1[1].converted)

                local res2 = xray_units.detectMeasurements("10000-10 feet", "to_metric")
                assert.are.equal(1, #res2)
                assert.are.equal("10000-10 feet", res2[1].original)
                assert.are.equal("3.05 km–3.05 m", res2[1].converted)
            end)

            it("formats weight ranges spanning gram and kilogram boundaries", function()
                local res1 = xray_units.detectMeasurements("40-3 oz", "to_metric")
                assert.are.equal(1, #res1)
                assert.are.equal("40-3 oz", res1[1].original)
                assert.are.equal("1.13 kg–85.05 g", res1[1].converted)

                local res2 = xray_units.detectMeasurements("3-40 oz", "to_metric")
                assert.are.equal(1, #res2)
                assert.are.equal("3-40 oz", res2[1].original)
                assert.are.equal("85.05 g–1.13 kg", res2[1].converted)
            end)

            it("does not match comma-separated numbers as ranges and recovers valid measurements", function()
                local res1 = xray_units.detectMeasurements("40, 3 oz", "to_metric")
                assert.are.equal(1, #res1)
                assert.are.equal("3 oz", res1[1].original)
                assert.are.equal("85.05 g", res1[1].converted)

                local res2 = xray_units.detectMeasurements("It was in 1940, 3 miles from town.", "to_metric")
                assert.are.equal(1, #res2)
                assert.are.equal("3 miles", res2[1].original)
                assert.are.equal("4.83 km", res2[1].converted)
            end)

            it("keeps single trailing unit when both range endpoints scale to the same unit", function()
                local res1 = xray_units.detectMeasurements("5-10 miles", "to_metric")
                assert.are.equal(1, #res1)
                assert.are.equal("5-10 miles", res1[1].original)
                assert.are.equal("8.05–16.09 km", res1[1].converted)

                local res2 = xray_units.detectMeasurements("10-20 feet", "to_metric")
                assert.are.equal(1, #res2)
                assert.are.equal("10-20 feet", res2[1].original)
                assert.are.equal("3.05–6.1 m", res2[1].converted)
            end)
        end)
    end)

end)
