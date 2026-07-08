-- xray_units.lua - Core logic for unit detection, conversion and formatting
local M = {}

local WRITTEN_NUMBERS = {
    quarter = 0.25, half = 0.5, zero = 0, one = 1, two = 2, three = 3, four = 4, five = 5,
    six = 6, seven = 7, eight = 8, nine = 9, ten = 10,
    eleven = 11, twelve = 12, thirteen = 13, fourteen = 14, fifteen = 15,
    sixteen = 16, seventeen = 17, eighteen = 18, nineteen = 19, twenty = 20,
    thirty = 30, forty = 40, fifty = 50, sixty = 60, seventy = 70, eighty = 80, ninety = 90,
    hundred = 100, thousand = 1000, million = 1000000
}

local NON_ENGLISH_ASCII = {
    zoll=true, pulgada=true, pulgadas=true, pouce=true, pouces=true,
    pollice=true, pollici=true, polegada=true, polegadas=true, cal=true,
    cale=true, cali=true, fuss=true, pie=true, pies=true,
    pied=true, pieds=true, piede=true, piedi=true, ["pé"]=true,
    ["pés"]=true, voet=true, stopa=true, stopy=true, stop=true,
    ayak=true, kaki=true, yarda=true, yardas=true, iarda=true,
    iarde=true, jarda=true, jardas=true, jard=true, hardy=true,
    jardy=true, meile=true, meilen=true, milla=true, millas=true,
    mille=true, milles=true, miglio=true, miglia=true, milha=true,
    milhas=true, mijl=true, mijlen=true, mila=true, mil=true,
    unze=true, unzen=true, onza=true, onzas=true, once=true,
    onces=true, oncia=true, uncja=true, uncje=true, uncji=true,
    uncia=true, ons=true, pfund=true, libra=true, libras=true,
    livre=true, livres=true, libbra=true, libbre=true, funt=true,
    funty=true, font=true, libre=true, pon=true, hektar=true,
    ettaro=true, ettari=true, hektary=true
}

M.NON_ENGLISH_ASCII = NON_ENGLISH_ASCII

-- Returns standard conversion direction based on reader settings
function M.getDefaultDirection()
    if G_reader_settings then
        local setting = G_reader_settings:readSetting("dimension_units")
        if setting == "in" or setting == "imperial" then
            return "to_imperial"  -- Accustomed to imperial -> convert FROM metric TO imperial
        end
    end
    return "to_metric"            -- Accustomed to metric -> convert FROM imperial TO metric
end

local COMMA_LOCALES = {
    de = true, fr = true, es = true, ru = true, uk = true,
    hu = true, pl = true, nl = true, pt_br = true, sr = true,
    it = true
}

-- Format number according to locale and smart formatting
function M.formatNumber(val, lang)
    if not val then return "0" end
    -- Round to at most 2 decimal places
    local formatted = string.format("%.2f", val)
    -- Remove trailing zeros and dot
    formatted = formatted:gsub("0+$", ""):gsub("%.$", "")
    
    local integer_part, decimal_part = formatted:match("^([^%.]*)(%.?.*)$")
    local decimal_sep = "."
    local thousand_sep = ","
    
    if lang and COMMA_LOCALES[lang] then
        decimal_sep = ","
        thousand_sep = "."
    end
    
    -- Format thousands in the integer part
    local left, num = integer_part:match("^([^%d]*)(%d+)$")
    if num then
        local rev = num:reverse():gsub("(%d%d%d)", "%1" .. thousand_sep):reverse()
        -- Escape thousand_sep for the pattern match in gsub
        local escaped_sep = thousand_sep:gsub("([^%w])", "%%%1")
        rev = rev:gsub("^" .. escaped_sep, "")
        integer_part = left .. rev
    end
    
    if decimal_part and decimal_part ~= "" then
        decimal_part = decimal_sep .. decimal_part:sub(2)
    end
    
    return integer_part .. decimal_part
end

local function parseNumberText(str)
    if not str then return nil end
    str = str:lower():gsub("\194\160", " "):gsub("^%s+", ""):gsub("%s+$", "")
    -- Normalize Unicode minus/dashes to standard hyphen
    str = str:gsub("−", "-"):gsub("–", "-"):gsub("—", "-")
    -- Strip spaces after leading minus sign
    str = str:gsub("^%-%s+", "-")
    if str == "half" or str == "half a" or str == "half an" then return 0.5 end
    
    -- Try direct numeric
    -- Strip English thousand separator commas (comma followed by exactly 3 digits)
    local clean_str = str:gsub(",(%d%d%d%f[%D])", "%1")
    -- Replace European comma with dot for conversion if present
    clean_str = clean_str:gsub(",", ".")
    local num = tonumber(clean_str)
    if num then return num end
    
    -- Try compound written numbers like "twenty three" or "twenty-three"
    local wvals = {}
    local found = false
    for word in str:gmatch("[a-z]+") do
        if word ~= "and" and word ~= "a" and word ~= "an" then
            local wval = WRITTEN_NUMBERS[word]
            if not wval then return nil end
            table.insert(wvals, wval)
            found = true
        end
    end
    if not found then return nil end

    -- Preprocess to insert 100 between unit (1-9) and tens/teens (10-99)
    -- E.g. "one fifty" -> {1, 50} -> {1, 100, 50}
    local i = 1
    while i < #wvals do
        local v1 = wvals[i]
        local v2 = wvals[i+1]
        if v1 >= 1 and v1 <= 9 and v2 >= 10 and v2 <= 99 then
            table.insert(wvals, i + 1, 100)
            i = i + 1 -- Skip the inserted 100
        end
        i = i + 1
    end

    -- Standard written numbers parsing algorithm
    local total_val = 0
    local temp_val = 0
    for _, wval in ipairs(wvals) do
        if wval == 100 or wval == 1000 or wval == 1000000 then
            if temp_val == 0 then temp_val = 1 end
            if wval == 100 then
                temp_val = temp_val * 100
            else
                temp_val = temp_val * wval
                total_val = total_val + temp_val
                temp_val = 0
            end
        else
            temp_val = temp_val + wval
        end
    end
    return total_val + temp_val
end

-- Converts one unit to another
function M.convert(val, category, from_unit, to_unit)
    if category == "temp" then
        if from_unit == "f" and to_unit == "c" then
            return (val - 32) * 5 / 9
        elseif from_unit == "c" and to_unit == "f" then
            return val * 9 / 5 + 32
        end
        return val
    end

    -- Base unit mapping (Length -> meters, Weight -> kg, Volume -> L, Speed -> km/h, Area -> m2)
    local factors = {
        length = {
            -- Imperial to meters
            ["in"] = 0.0254, ["inch"] = 0.0254, ["inches"] = 0.0254,
            ["ft"] = 0.3048, ["foot"] = 0.3048, ["feet"] = 0.3048,
            ["yd"] = 0.9144, ["yard"] = 0.9144, ["yards"] = 0.9144,
            ["mi"] = 1609.344, ["mile"] = 1609.344, ["miles"] = 1609.344,
            ["league"] = 4828.032, ["leagues"] = 4828.032,
            ["fathom"] = 1.8288, ["fathoms"] = 1.8288,
            -- Metric to meters
            ["mm"] = 0.001, ["millimeter"] = 0.001, ["millimeters"] = 0.001, ["millimetre"] = 0.001, ["millimetres"] = 0.001,
            ["cm"] = 0.01, ["centimeter"] = 0.01, ["centimeters"] = 0.01, ["centimetre"] = 0.01, ["centimetres"] = 0.01,
            ["m"] = 1.0, ["meter"] = 1.0, ["meters"] = 1.0, ["metre"] = 1.0, ["metres"] = 1.0,
            ["km"] = 1000.0, ["kilometer"] = 1000.0, ["kilometers"] = 1000.0, ["kilometre"] = 1000.0, ["kilometres"] = 1000.0,
        },
        weight = {
            -- Imperial to kg
            ["oz"] = 0.028349523125, ["ounce"] = 0.028349523125, ["ounces"] = 0.028349523125,
            ["lb"] = 0.45359237, ["lbs"] = 0.45359237, ["pound"] = 0.45359237, ["pounds"] = 0.45359237,
            ["st"] = 6.35029318, ["stone"] = 6.35029318, ["stones"] = 6.35029318,
            -- Metric to kg
            ["g"] = 0.001, ["gram"] = 0.001, ["grams"] = 0.001, ["gramme"] = 0.001, ["grammes"] = 0.001,
            ["kg"] = 1.0, ["kilogram"] = 1.0, ["kilograms"] = 1.0, ["kilogramme"] = 1.0, ["kilogrammes"] = 1.0,
        },
        volume = {
            -- Imperial to L
            ["fl oz"] = 0.0295735295625, ["fl. oz."] = 0.0295735295625, ["fluid ounce"] = 0.0295735295625, ["fluid ounces"] = 0.0295735295625,
            ["cup"] = 0.2365882365, ["cups"] = 0.2365882365,
            ["pt"] = 0.473176473, ["pint"] = 0.473176473, ["pints"] = 0.473176473,
            ["qt"] = 0.946352946, ["quart"] = 0.946352946, ["quarts"] = 0.946352946,
            ["gal"] = 3.785411784, ["gallon"] = 3.785411784, ["gallons"] = 3.785411784,
            -- Metric to L
            ["ml"] = 0.001, ["mL"] = 0.001, ["milliliter"] = 0.001, ["milliliters"] = 0.001, ["millilitre"] = 0.001, ["millilitres"] = 0.001,
            ["l"] = 1.0, ["L"] = 1.0, ["liter"] = 1.0, ["liters"] = 1.0, ["litre"] = 1.0, ["litres"] = 1.0,
        },
        speed = {
            -- Convert everything to km/h base
            ["mph"] = 1.609344, ["miles per hour"] = 1.609344,
            ["km/h"] = 1.0, ["kmh"] = 1.0, ["kph"] = 1.0, ["kilometers per hour"] = 1.0, ["kilometres per hour"] = 1.0,
        },
        area = {
            -- Convert to m2 base
            ["sq ft"] = 0.09290304, ["ft2"] = 0.09290304, ["ft²"] = 0.09290304, ["square feet"] = 0.09290304,
            ["sq mi"] = 2589988.11, ["mi2"] = 2589988.11, ["mi²"] = 2589988.11, ["square miles"] = 2589988.11,
            ["acre"] = 4046.8564224, ["acres"] = 4046.8564224,
            ["sq m"] = 1.0, ["m2"] = 1.0, ["m²"] = 1.0, ["square meters"] = 1.0, ["square metres"] = 1.0,
            ["sq km"] = 1000000.0, ["km2"] = 1000000.0, ["km²"] = 1000000.0, ["square kilometers"] = 1000000.0, ["square kilometres"] = 1000000.0,
            ["ha"] = 10000.0, ["hectare"] = 10000.0, ["hectares"] = 10000.0,
        }
    }

    local cat_factors = factors[category]
    if not cat_factors then return val end

    local from_factor = cat_factors[from_unit]
    local to_factor = cat_factors[to_unit]
    if not from_factor or not to_factor then return val end

    local val_in_base = val * from_factor
    return val_in_base / to_factor
end

-- Unit definitions with standard conversion targets, categories, and aliases
local UNITS = {
    -- LENGTH
    { category = "length", system = "imperial", name = "inch", std_target = "cm", aliases = { "inches", "inch", "in", "zoll", "pulgada", "pulgadas", "pouce", "pouces", "pollice", "pollici", "polegada", "polegadas", "cal", "cale", "cali", "дюйм", "дюйма", "дюймов", "дюймів", "hüvelyk", "inç", "بوصة", "بوصات", "inci", "英寸" } },
    { category = "length", system = "imperial", name = "foot", std_target = "m", aliases = { "feet", "foot", "ft", "fuß", "fuss", "pie", "pies", "pied", "pieds", "piede", "piedi", "pé", "pés", "voet", "stopa", "stopy", "stop", "фут", "фута", "футов", "футів", "láb", "ayak", "قدم", "أقدام", "kaki", "英尺" } },
    { category = "length", system = "imperial", name = "yard", std_target = "m", aliases = { "yards", "yard", "yd", "yarda", "yardas", "iarda", "iarde", "jarda", "jardas", "jard", "jardy", "jardów", "ярд", "ярда", "ярдов", "ярдів", "yarda", "ياردا", "ياردة", "ياردات", "码" } },
    { category = "length", system = "imperial", name = "mile", std_target = "km", aliases = { "miles", "mile", "mi", "meile", "meilen", "milla", "millas", "mille", "milles", "miglio", "miglia", "milha", "milhas", "mijl", "mijlen", "mila", "mile", "mil", "миля", "мили", "миль", "милі", "mérföld", "أميال", "ميل", "英里" } },
    { category = "length", system = "imperial", name = "league", std_target = "km", aliases = { "leagues", "league" } },
    { category = "length", system = "imperial", name = "fathom", std_target = "m", aliases = { "fathoms", "fathom" } },
    
    { category = "length", system = "metric", name = "mm", std_target = "inch", aliases = { "millimeters", "millimeter", "mm", "millimetres", "millimetre" } },
    { category = "length", system = "metric", name = "cm", std_target = "inch", aliases = { "centimeters", "centimeter", "cm", "centimetres", "centimetre" } },
    { category = "length", system = "metric", name = "m", std_target = "foot", aliases = { "meters", "meter", "m", "metres", "metre", "metro", "metros", "mètre", "mètres", "metri", "metr", "metry", "metrów", "метр", "метра", "метров", "метрів", "méter", "متر", "أمتار", "米", "公尺" } },
    { category = "length", system = "metric", name = "km", std_target = "mile", aliases = { "kilometers", "kilometer", "km", "kilometres", "kilometre", "kilómetro", "kilómetros", "kilomètre", "kilomètres", "chilometro", "chilometri", "quilômetro", "quilômetros", "kilometry", "километр", "километра", "километров", "кілометр", "кілометра", "кілометрів", "kilométer", "كيلومتر", "كيلومترات", "公里", "千米" } },

    -- WEIGHT
    { category = "weight", system = "imperial", name = "oz", std_target = "g", aliases = { "ounces", "ounce", "oz", "unze", "unzen", "onza", "onzas", "once", "onces", "oncia", "uncja", "uncje", "uncji", "унция", "унции", "унций", "унція", "унції", "uncia", "ons", "أوقية", "أوقيات", "盎司" } },
    { category = "weight", system = "imperial", name = "lb", std_target = "kg", aliases = { "pounds", "pound", "lbs", "lb", "pfund", "libra", "libras", "livre", "livres", "libbra", "libbre", "funt", "funty", "funtów", "фунт", "фунта", "фунтов", "футів", "font", "libre", "رطل", "أرطال", "pon", "磅" } },
    { category = "weight", system = "imperial", name = "st", std_target = "kg", aliases = { "stones", "stone", "st" } },

    { category = "weight", system = "metric", name = "g", std_target = "oz", aliases = { "grams", "gram", "g", "grammes", "gramme", "gramm", "gramo", "gramos", "grammo", "grammi", "grama", "gramas", "gramy", "грамм", "грамма", "граммов", "грам", "грама", "грамів", "جرام", "جرامات", "克" } },
    { category = "weight", system = "metric", name = "kg", std_target = "lb", aliases = { "kilograms", "kilogram", "kg", "kilogrammes", "kilogramme", "kilogramm", "kilogramo", "kilogramos", "kilogrames", "kilo", "kilos", "chilogrammo", "chilogrammi", "chilo", "chili", "quilograma", "quilogramas", "quilo", "quilos", "kilogramy", "килограмм", "килограмма", "килограммов", "кілограм", "кілограма", "кілограмів", "كيلوجرام", "كيلوجرامات", "公斤", "千克" } },

    { category = "temp", system = "imperial", name = "f", std_target = "c", aliases = { "fahrenheit", "f", "degrees fahrenheit", "degree fahrenheit", "deg f", "°f", "°fahrenheit", "deg. f", "degrees f", "degree f" } },
    { category = "temp", system = "metric", name = "c", std_target = "f", aliases = { "celsius", "celcius", "c", "degrees celsius", "degree celsius", "degrees celcius", "degree celcius", "deg c", "°c", "°celsius", "°celcius", "deg. c", "degrees c", "degree c" } },

    -- VOLUME
    { category = "volume", system = "imperial", name = "fl oz", std_target = "ml", aliases = { "fluid ounces", "fluid ounce", "fl oz", "fl%. oz%." } },
    { category = "volume", system = "imperial", name = "cup", std_target = "ml", aliases = { "cups", "cup" } },
    { category = "volume", system = "imperial", name = "pint", std_target = "ml", aliases = { "pints", "pint", "pt" } },
    { category = "volume", system = "imperial", name = "quart", std_target = "l", aliases = { "quarts", "quart", "qt" } },
    { category = "volume", system = "imperial", name = "gallon", std_target = "l", aliases = { "gallons", "gallon", "gal", "gallone", "gallonen", "galón", "galones", "galloni", "galão", "galões", "galon", "galony", "galonów", "галлон", "галлона", "галлонов", "галон", "галона", "галонів", "جالون", "جالونات", "加仑" } },

    { category = "volume", system = "metric", name = "ml", std_target = "fl oz", aliases = { "milliliters", "milliliter", "ml", "mL", "millilitres", "millilitre" } },
    { category = "volume", system = "metric", name = "l", std_target = "gallon", aliases = { "liters", "liter", "l", "L", "litres", "litre", "litro", "litros", "litri", "litr", "litry", "litrów", "литр", "литра", "литров", "літр", "літра", "літрів", "لتر", "لترات", "升", "公升" } },

    -- SPEED
    { category = "speed", system = "imperial", name = "mph", std_target = "km/h", aliases = { "mph", "miles per hour" } },
    { category = "speed", system = "metric", name = "km/h", std_target = "mph", aliases = { "km/h", "kmh", "kph", "kilometers per hour", "kilometres per hour", "км/ч", "км/год", "公里/小时", "公里/小時" } },

    -- AREA
    { category = "area", system = "imperial", name = "sq ft", std_target = "m²", aliases = { "square feet", "sq ft", "ft2", "ft²" } },
    { category = "area", system = "imperial", name = "sq mi", std_target = "km²", aliases = { "square miles", "sq mi", "mi2", "mi²" } },
    { category = "area", system = "imperial", name = "acre", std_target = "ha", aliases = { "acres", "acre" } },

    { category = "area", system = "metric", name = "m²", std_target = "sq ft", aliases = { "square meters", "square metres", "sq m", "m2", "m²", "qm", "quadratmeter", "metros cuadrados", "mètres carrés", "metri quadrati", "médos quadrados", "metry kwadratowe", "кв. м", "квадратных метров", "квадратних метрів", "négyzetméter", "metrekare", "متر مربع", "أمتار مربعة", "meter persegi", "平方米" } },
    { category = "area", system = "metric", name = "km²", std_target = "sq mi", aliases = { "square kilometers", "square kilometres", "sq km", "km2", "km²", "quadratkilometer", "kilómetros cuadrados", "kilomètres carrés", "chilometri quadrati", "quilômetros quadrados", "kilometry kwadratowe", "кв. км", "квадратных километров", "квадратних кілометрів", "négyzetkilométer", "kilometrekare", "كيلومتر مربع", "kilometer persegi", "平方公里" } },
    { category = "area", system = "metric", name = "ha", std_target = "acre", aliases = { "hectares", "hectare", "ha", "hektar", "hectárea", "hectáreas", "ettaro", "ettari", "hektary", "гектар", "гектара", "гектаров", "гектарів", "hektár", "هكتار", "هكتارات", "公顷" } },
}

-- Helpers to check if a word is one of our units
local UNIT_LOOKUP = {}
for _, u in ipairs(UNITS) do
    for _, alias in ipairs(u.aliases) do
        UNIT_LOOKUP[alias:lower()] = u
    end
end

-- Perform smart scaling on formatted output
local function applySmartScaling(val, category, to_unit)
    if category == "length" then
        if to_unit == "m" and val >= 1000 then
            return val / 1000, "km"
        elseif to_unit == "m" and val < 0.1 then
            return val * 100, "cm"
        elseif to_unit == "cm" and val >= 100 then
            return val / 100, "m"
        end
    elseif category == "weight" then
        if to_unit == "g" and val >= 1000 then
            return val / 1000, "kg"
        end
    end
    return val, to_unit
end

local VAGUE_BANDS = {
    ["a few"] = {2, 5},
    ["few"] = {2, 5},
    ["several"] = {3, 7},
    ["a couple of"] = {2, 2},
    ["a couple"] = {2, 2},
    ["couple of"] = {2, 2},
    ["couple"] = {2, 2},
    ["some"] = {1, 1},
}
local VAGUE_ORDER = {
    "a couple of", "a couple", "couple of", "several", "a few", "couple", "some", "few"
}
local VAGUE_MULTIPLIERS = {
    dozen = 12,
    hundred = 100,
    thousand = 1000,
    million = 1000000,
}

local function detectVagueQuantifier(prev_text)
    if not prev_text then return nil end
    local p = prev_text:lower():gsub("%s+$", "")
    local mword = p:match("([%a]+)$")
    local mult = mword and VAGUE_MULTIPLIERS[mword]
    if not mult then return nil end
    
    p = p:sub(1, #p - #mword):gsub("%s+$", "")
    for _, q in ipairs(VAGUE_ORDER) do
        if #p >= #q and p:sub(-#q) == q then
            local bch = p:sub(-#q - 1, -#q - 1)
            if bch == "" or bch:match("%s") or bch:match("[.,;!?]") then
                local band = VAGUE_BANDS[q]
                return {
                    low = band[1] * mult,
                    high = band[2] * mult,
                    quantifier = q,
                    multiplier = mword,
                    full_len = #q + 1 + #mword
                }
            end
        end
    end
    return nil
end

-- Helper to extract optional negative sign before start_pos
local function getPrecedingSign(text, start_pos)
    if start_pos <= 1 then return "" end
    -- Check 3-byte signs first (UTF-8 symbols like − / – / —)
    if start_pos > 3 then
        local three_bytes = text:sub(start_pos - 3, start_pos - 1)
        if three_bytes == "−" or three_bytes == "–" or three_bytes == "—" then
            return three_bytes
        end
    end
    -- Check 1-byte sign
    local one_byte = text:sub(start_pos - 1, start_pos - 1)
    if one_byte == "-" then
        return one_byte
    end
    return ""
end

M.detectVagueQuantifier = detectVagueQuantifier

-- Detects all measurements in text and returns conversion results
function M.detectMeasurements(text, direction, enabled_categories, current_lang)
    if not text or text == "" then return {} end
    current_lang = current_lang or "en"
    
    if not direction or direction == "auto" then
        direction = M.getDefaultDirection()
    end
    enabled_categories = enabled_categories or {
        length = true, weight = true, temp = true, volume = true, speed = true, area = true
    }
    
    local results = {}
    local text_lower = text:lower():gsub("\194\160", " ")

    -- 1. Try compound units first (e.g. 6 feet 2 inches or 6'2")
    -- Pattern: (%d+)%s*'%s*(%d+)%s*"
    if enabled_categories.length and (direction == "to_metric" or direction == "auto") then
        local init = 1
        while true do
            local s, e, f, i = text_lower:find("(%d+)%s*'%s*(%d+)%s*\"", init)
            if not s then break end
            local ft_val = tonumber(f)
            local in_val = tonumber(i)
            if ft_val and in_val then
                local total_in = ft_val * 12 + in_val
                local total_m = M.convert(total_in, "length", "in", "m")
                local orig_str = text:sub(s, e)
                local conv_val, conv_unit = applySmartScaling(total_m, "length", "m")
                local conv_str = M.formatNumber(conv_val, current_lang) .. " " .. conv_unit
                
                table.insert(results, {
                    start_pos = s,
                    end_pos = e,
                    original = orig_str,
                    converted = conv_str,
                    category = "length"
                })
            end
            init = e + 1
        end
        
        
        -- Pattern: (%d+)%s+feet%s+(%d+)%s+inches
        local compound_units = {
            { f_pat = "feet", i_pat = "inches" },
            { f_pat = "foot", i_pat = "inch" },
            { f_pat = "ft", i_pat = "in" }
        }
        for _, pat in ipairs(compound_units) do
            local init = 1
            local pattern = "(%d+)%s+" .. pat.f_pat .. "%s+(%d+)%s+" .. pat.i_pat .. "%f[%W]"
            while true do
                local s, e, f, i = text_lower:find(pattern, init)
                if not s then break end
                local ft_val = tonumber(f)
                local in_val = tonumber(i)
                if ft_val and in_val then
                    local total_in = ft_val * 12 + in_val
                    local total_m = M.convert(total_in, "length", "in", "m")
                    local orig_str = text:sub(s, e)
                    local conv_val, conv_unit = applySmartScaling(total_m, "length", "m")
                    local conv_str = M.formatNumber(conv_val, current_lang) .. " " .. conv_unit
                    
                    table.insert(results, {
                        start_pos = s,
                        end_pos = e,
                        original = orig_str,
                        converted = conv_str,
                        category = "length"
                    })
                end
                init = e + 1
            end
        end
    end

    if enabled_categories.weight and (direction == "to_metric" or direction == "auto") then
        local init = 1
        -- Pattern: (%d+)%s*st%s*(%d+)%s*lb
        while true do
            local s, e, st, lb = text_lower:find("(%d+)%s*st%s*(%d+)%s*lb%f[%W]", init)
            if not s then break end
            local st_val = tonumber(st)
            local lb_val = tonumber(lb)
            if st_val and lb_val then
                local total_lb = st_val * 14 + lb_val
                local total_kg = M.convert(total_lb, "weight", "lb", "kg")
                local conv_str = M.formatNumber(total_kg, current_lang) .. " kg"
                
                table.insert(results, {
                    start_pos = s,
                    end_pos = e,
                    original = text:sub(s, e),
                    converted = conv_str,
                    category = "weight"
                })
            end
            init = e + 1
        end
    end

    -- 2. General single unit matching
    for _, u in ipairs(UNITS) do
        if enabled_categories[u.category] then
            local matches_direction = false
            if direction == "to_metric" and u.system == "imperial" then
                matches_direction = true
            elseif direction == "to_imperial" and u.system == "metric" then
                matches_direction = true
            elseif direction == "auto" then
                matches_direction = true
            end
            
            if matches_direction then
                for _, alias in ipairs(u.aliases) do
                    local alias_lower = alias:lower()
                    local is_en = (current_lang:lower() == "en")
                    if not (is_en and NON_ENGLISH_ASCII[alias_lower]) then
                        local escaped_alias = alias:gsub("[%-%+%.%?%*%^%$%(%)%[%]%%]", "%%%1")
                    
                    -- A: Digit pattern: matches numbers like "12.5", "12", "12,5"
                    local pattern = "([%d%.%,]+)%s*%-?%s*(" .. escaped_alias .. ")%f[%W]"
                    local init = 1
                    while true do
                        local s, e, num_str, unit_match = text_lower:find(pattern, init)
                        if not s then break end
                        
                        -- Guard against middle-of-number match (e.g. matching '40' inside '140')
                        local before_char = s > 1 and text_lower:sub(s - 1, s - 1) or ""
                        if not before_char:match("[%d%.%,]") then
                            local val = parseNumberText(num_str)
                            if val then
                                -- Check for preceding sign (negative) for temperature
                                local sign = ""
                                local match_start = s
                                if u.category == "temp" then
                                    sign = getPrecedingSign(text, s)
                                    if sign ~= "" then
                                        val = -val
                                        match_start = s - #sign
                                    end
                                end
                                
                                local conv_raw = M.convert(val, u.category, u.name, u.std_target)
                                local conv_val, conv_unit = applySmartScaling(conv_raw, u.category, u.std_target)
                                
                                -- Temperature symbol format
                                if conv_unit == "c" then conv_unit = "°C"
                                elseif conv_unit == "f" then conv_unit = "°F" end

                                local conv_str = M.formatNumber(conv_val, current_lang) .. " " .. M.pluralizeUnit(conv_val, conv_unit)
                                
                                table.insert(results, {
                                    start_pos = match_start,
                                    end_pos = e,
                                    original = text:sub(match_start, e),
                                    converted = conv_str,
                                    category = u.category
                                })
                            end
                        end
                        init = e + 1
                    end
                    
                    -- Range patterns
                    local is_tens = { twenty=true, thirty=true, forty=true, fifty=true, sixty=true, seventy=true, eighty=true, ninety=true }
                    local is_units = { one=true, two=true, three=true, four=true, five=true, six=true, seven=true, eight=true, nine=true }
                    local function process_range_pattern(pat, is_word)
                        local r_init = 1
                        while true do
                            local s, e, r1, r2, unit_match = text_lower:find(pat, r_init)
                            if not s then break end
                            local before_char = s > 1 and text_lower:sub(s - 1, s - 1) or ""
                            local ok_boundary = true
                            if is_word and before_char:match("%a") then
                                ok_boundary = false
                            elseif not is_word and before_char:match("[%d%.%,]") then
                                ok_boundary = false
                            end
                            if ok_boundary then
                                local is_range = true
                                if is_word and is_tens[r1] and is_units[r2] and not text_lower:sub(s, e):find("%s+to%s") and not text_lower:sub(s, e):find("%s+or%s") and not text_lower:sub(s, e):find("%s+and%s") and not text_lower:sub(s, e):find(",") then
                                    is_range = false
                                end
                                if is_range then
                                    local val1 = parseNumberText(r1)
                                    local val2 = parseNumberText(r2)
                                    if val1 and val2 then
                                        local conv_raw1 = M.convert(val1, u.category, u.name, u.std_target)
                                        local conv_val1, conv_unit = applySmartScaling(conv_raw1, u.category, u.std_target)
                                        local conv_raw2 = M.convert(val2, u.category, u.name, u.std_target)
                                        local conv_val2 = applySmartScaling(conv_raw2, u.category, u.std_target)
                                        if conv_unit == "c" then conv_unit = "°C"
                                        elseif conv_unit == "f" then conv_unit = "°F" end
                                        local conv_str = M.formatNumber(conv_val1, current_lang) .. "–" .. M.formatNumber(conv_val2, current_lang) .. " " .. M.pluralizeUnit(conv_val2, conv_unit)
                                        table.insert(results, {
                                            start_pos = s,
                                            end_pos = e,
                                            original = text:sub(s, e),
                                            converted = conv_str,
                                            category = u.category
                                        })
                                    end
                                end
                            end
                            r_init = e + 1
                        end
                    end
                    -- Range patterns using pure Lua patterns (no | alternation supported in Lua)
                    local connectors = { "to", "or", "and", "-", "–", "," }
                    for _, conn in ipairs(connectors) do
                        local d_pat
                        if conn == "," then
                            d_pat = "([%d%.%,]+)%s*,%s+([%d%.%,]+)%s*(" .. escaped_alias .. ")%f[%W]"
                        elseif conn == "-" or conn == "–" then
                            d_pat = "([%d%.%,]+)%s*[" .. conn .. "]%s*([%d%.%,]+)%s*(" .. escaped_alias .. ")%f[%W]"
                        else
                            d_pat = "([%d%.%,]+)%s+" .. conn .. "%s+([%d%.%,]+)%s*(" .. escaped_alias .. ")%f[%W]"
                        end
                        process_range_pattern(d_pat, false)
                    end

                    if not (alias_lower == "in" or alias_lower == "st") then
                        for _, conn in ipairs(connectors) do
                            local w_pat
                            if conn == "," then
                                w_pat = "([a-z%d%-]+)%s*,%s+([a-z%d%-]+)%s*(" .. escaped_alias .. ")%f[%W]"
                            else
                                w_pat = "([a-z%d%-]+)%s+" .. conn .. "%s+([a-z%d%-]+)%s*(" .. escaped_alias .. ")%f[%W]"
                            end
                            process_range_pattern(w_pat, true)
                        end
                    end

                    -- B: Written numbers (English only fallback): matches e.g. "six feet"
                    if not (alias_lower == "in" or alias_lower == "st") then
                        local written_pattern = "([a-z%- ]+)%s+(" .. escaped_alias .. ")%f[%W]"
                        init = 1
                        while true do
                            local s, e, word_str, unit_match = text_lower:find(written_pattern, init)
                            if not s then break end
                            
                            -- Guard word boundary at the start
                            local before_char = s > 1 and text_lower:sub(s - 1, s - 1) or ""
                            if not before_char:match("%a") then
                                -- Parse multi-word phrase by trying longest suffix first
                                local phrase_words = {}
                                for w in word_str:gmatch("[a-z%-]+") do
                                    table.insert(phrase_words, w)
                                end
                                
                                -- Filter to ensure we only keep contiguous valid written number tokens from the right
                                local valid_words = {}
                                local i_w = #phrase_words
                                while i_w >= 1 do
                                    local w = phrase_words[i_w]
                                    local clean_w = w:gsub("[%-,]$", "")
                                    if clean_w == "and" or clean_w == "a" or clean_w == "an" or parseNumberText(clean_w) then
                                        table.insert(valid_words, 1, clean_w)
                                        i_w = i_w - 1
                                    else
                                        break
                                    end
                                end

                                while #valid_words > 0 and valid_words[1] == "and" do
                                    table.remove(valid_words, 1)
                                end

                                if #valid_words > 0 then
                                    local phrase = table.concat(valid_words, " ")
                                    local val = parseNumberText(phrase)
                                    if val then
                                        local phrase_start_idx = word_str:find(phrase, 1, true)
                                        local match_start = s
                                        if phrase_start_idx then
                                            match_start = s + phrase_start_idx - 1
                                        end

                                        local conv_raw = M.convert(val, u.category, u.name, u.std_target)
                                        local conv_val, conv_unit = applySmartScaling(conv_raw, u.category, u.std_target)
                                        
                                        if conv_unit == "c" then conv_unit = "°C"
                                        elseif conv_unit == "f" then conv_unit = "°F" end
                                        
                                        local conv_str = M.formatNumber(conv_val, current_lang) .. " " .. M.pluralizeUnit(conv_val, conv_unit)
                                        
                                        table.insert(results, {
                                            start_pos = match_start,
                                            end_pos = e,
                                            original = text:sub(match_start, e),
                                            converted = conv_str,
                                            category = u.category
                                        })
                                    end
                                end
                            end
                            init = e + 1
                        end
                    end

                    -- C: Vague quantifiers (e.g. "a few hundred yards") using pure Lua loop
                    if not (alias_lower == "in" or alias_lower == "st") then
                        local multipliers = { "dozen", "hundred", "thousand", "million" }
                        for _, mult in ipairs(multipliers) do
                            local vague_pattern = "([a-z%s]+)%s+" .. mult .. "%s*(" .. escaped_alias .. ")%f[%W]"
                            init = 1
                            while true do
                                local s, e, prefix, unit_match = text_lower:find(vague_pattern, init)
                                if not s then break end
                                
                                local before_char = s > 1 and text_lower:sub(s - 1, s - 1) or ""
                                if not before_char:match("%a") then
                                    local clean_pref = prefix:gsub("^%s+", ""):gsub("%s+$", "")
                                    for _, q in ipairs(VAGUE_ORDER) do
                                        if clean_pref == q or clean_pref:sub(-#q) == q then
                                            local band = VAGUE_BANDS[q]
                                            local mult_val = VAGUE_MULTIPLIERS[mult]
                                            if band and mult_val then
                                                local val1 = band[1] * mult_val
                                                local val2 = band[2] * mult_val
                                                local conv_raw1 = M.convert(val1, u.category, u.name, u.std_target)
                                                local conv_val1, conv_unit = applySmartScaling(conv_raw1, u.category, u.std_target)
                                                local conv_raw2 = M.convert(val2, u.category, u.name, u.std_target)
                                                local conv_val2 = applySmartScaling(conv_raw2, u.category, u.std_target)
                                                
                                                if conv_unit == "c" then conv_unit = "°C"
                                                elseif conv_unit == "f" then conv_unit = "°F" end
                                                
                                                local conv_str
                                                if val1 == val2 then
                                                    conv_str = "≈" .. M.formatNumber(conv_val1, current_lang) .. " " .. M.pluralizeUnit(conv_val1, conv_unit)
                                                else
                                                    conv_str = "≈" .. M.formatNumber(conv_val1, current_lang) .. "–" .. M.formatNumber(conv_val2, current_lang) .. " " .. M.pluralizeUnit(conv_val2, conv_unit)
                                                end
                                                
                                                local match_start = s + (prefix:find(q, 1, true) or 1) - 1
                                                table.insert(results, {
                                                    start_pos = match_start,
                                                    end_pos = e,
                                                    original = text:sub(match_start, e),
                                                    converted = conv_str,
                                                    category = u.category,
                                                    vague = true
                                                })
                                                break
                                            end
                                        end
                                    end
                                end
                                init = e + 1
                            end
                        end
                    end
                    end
                end
            end
        end
    end

    -- Deduplicate matches (e.g. if single unit matched a compound match, or duplicate start positions)
    local final_results = {}
    local seen_starts = {}
    
    -- Sort results by length descending so compound/larger matches are kept
    table.sort(results, function(a, b)
        return (a.end_pos - a.start_pos) > (b.end_pos - b.start_pos)
    end)
    
    for _, res in ipairs(results) do
        local overlap = false
        for start_idx, end_idx in pairs(seen_starts) do
            if (res.start_pos >= start_idx and res.start_pos <= end_idx) or
               (res.end_pos >= start_idx and res.end_pos <= end_idx) then
                overlap = true
                break
            end
        end
        if not overlap then
            seen_starts[res.start_pos] = res.end_pos
            table.insert(final_results, res)
        end
    end
    
    -- Re-sort by start position ascending for callers
    table.sort(final_results, function(a, b)
        return a.start_pos < b.start_pos
    end)

    return final_results
end

function M.getScanAliases(direction, enabled_categories, lang)
    if not direction or direction == "auto" then
        direction = M.getDefaultDirection()
    end
    enabled_categories = enabled_categories or {
        length = true, weight = true, temp = true, volume = true, speed = true, area = true
    }
    lang = lang or "en"
    local aliases = {}
    local seen = {}
    local EXCLUDED = {
        ["in"] = true,
        ["st"] = true,
    }
    
    local function should_keep_alias(alias, l)
        -- Always keep ASCII aliases (they are used as standard abbreviations like mm, kg everywhere)
        if alias:match("^[%z\1-\127]+$") then
            return true
        end
        -- Always keep universal degree symbols
        if alias:find("°") then
            return true
        end
        -- For non-ASCII: check if it matches the current language's script
        local l_lower = l:lower()
        if l_lower == "ru" or l_lower == "uk" or l_lower == "sr" then
            if alias:match("[\208\209]") then return true end
        elseif l_lower == "ar" then
            if alias:match("[\216-\219]") then return true end
        elseif l_lower:find("^zh") then
            if alias:match("[\228-\233]") then return true end
        elseif l_lower == "pt_br" or l_lower == "fr" or l_lower == "de" or l_lower == "es" or l_lower == "it" or l_lower == "nl" or l_lower == "pl" or l_lower == "hu" or l_lower == "tr" or l_lower == "id" then
            -- Latin extension characters (accented characters like mètre, kilómetro)
            if alias:match("[\194-\197]") then return true end
        end
        return false
    end

    for _, u in ipairs(UNITS) do
        if enabled_categories[u.category] then
            local matches_direction = false
            if direction == "to_metric" and u.system == "imperial" then
                matches_direction = true
            elseif direction == "to_imperial" and u.system == "metric" then
                matches_direction = true
            elseif direction == "auto" then
                matches_direction = true
            end
            
            if matches_direction then
                for _, alias in ipairs(u.aliases) do
                    local alias_lower = alias:lower()
                    if not EXCLUDED[alias_lower] and #alias_lower > 1 and not seen[alias_lower] then
                        local is_en = (lang:lower() == "en")
                        if not (is_en and NON_ENGLISH_ASCII[alias_lower]) then
                            if should_keep_alias(alias_lower, lang) then
                                seen[alias_lower] = true
                                table.insert(aliases, alias_lower)
                            end
                        end
                    end
                end
            end
        end
    end
    return aliases
end

local PLURALS = {
    inch = "inches",
    foot = "feet",
    yard = "yards",
    mile = "miles",
    league = "leagues",
    fathom = "fathoms",
    acre = "acres",
    cup = "cups",
    pint = "pints",
    quart = "quarts",
    gallon = "gallons",
}

function M.pluralizeUnit(val, unit)
    if not val or not unit then return unit end
    local is_one = false
    if type(val) == "number" then
        is_one = (val == 1)
    else
        local num = tonumber(tostring(val):gsub(",", "."))
        is_one = (num == 1)
    end
    
    if is_one then
        return unit
    end
    
    return PLURALS[unit] or unit
end

M.UNITS = UNITS
M.UNIT_LOOKUP = UNIT_LOOKUP
M.applySmartScaling = applySmartScaling
M.parseNumberText = parseNumberText

return M
