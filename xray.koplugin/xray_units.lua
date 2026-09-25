-- xray_units.lua - Core logic for unit detection, conversion and formatting
local plugin_path = ((...) or ""):match("(.-)[^%.]+$") or ""
local utils = require(plugin_path .. "xray_utils")

local M = {}

local function utf8Lower(str)
    return utils:utf8Lower(str)
end

M.utf8Lower = utf8Lower

-- Checks whether character byte at pos in text is a word character (letter/digit/underscore)
-- Accurately treats Unicode punctuation, fullwidth punctuation, and superscripts as non-word boundaries
local function is_word_char_at(text, pos)
    if not text or pos < 1 or pos > #text then return false end
    local b = string.byte(text, pos)
    if (b >= 48 and b <= 57) or (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or b == 95 then
        return true
    end
    if b == 194 then
        local next_b = string.byte(text, pos + 1)
        if next_b == 176 or next_b == 186 or next_b == 178 or next_b == 179 or next_b == 160 then
            return false
        end
        return true
    elseif b == 226 then
        -- U+2000..U+206F general punctuation, quotes, dashes, thin spaces
        return false
    elseif b == 227 then
        local next_b = string.byte(text, pos + 1)
        if next_b == 128 then return false end -- U+3000..U+303F CJK punctuation (、, 。, etc.)
        return true
    elseif b == 239 then
        local next_b = string.byte(text, pos + 1)
        if next_b >= 188 and next_b <= 191 then return false end -- U+FF00..U+FFEF Fullwidth punctuation (，, etc.)
        return true
    elseif b >= 195 and b <= 244 then
        return true
    end
    return false
end

M.is_word_char_at = is_word_char_at

local function find_phrase_start(word_str, phrase)
    local esc_phrase = phrase:gsub("([%-%+%.%?%*%^%$%(%)%[%]%%])", "%%%1")
    local init = 1
    while true do
        local s, e = word_str:find(esc_phrase, init, false)
        if not s then return word_str:find(phrase, 1, true) end
        local ok_start = (s == 1) or not is_word_char_at(word_str, s - 1)
        local ok_end = (e == #word_str) or not is_word_char_at(word_str, e + 1)
        if ok_start and ok_end then
            return s
        end
        init = s + 1
    end
end

local WRITTEN_NUMBERS = {
    -- English
    quarter = 0.25, half = 0.5, zero = 0, one = 1, two = 2, three = 3, four = 4, five = 5,
    six = 6, seven = 7, eight = 8, nine = 9, ten = 10,
    eleven = 11, twelve = 12, thirteen = 13, fourteen = 14, fifteen = 15,
    sixteen = 16, seventeen = 17, eighteen = 18, nineteen = 19, twenty = 20,
    thirty = 30, forty = 40, fifty = 50, sixty = 60, seventy = 70, eighty = 80, ninety = 90,
    hundred = 100, thousand = 1000, million = 1000000,

    -- Russian (lowercase UTF-8)
    ["четверть"] = 0.25, ["пол"] = 0.5, ["полтора"] = 1.5, ["полторы"] = 1.5,
    ["ноль"] = 0, ["нуль"] = 0, ["один"] = 1, ["одна"] = 1, ["одно"] = 1,
    ["два"] = 2, ["две"] = 2, ["три"] = 3, ["четыре"] = 4, ["пять"] = 5,
    ["шесть"] = 6, ["семь"] = 7, ["восемь"] = 8, ["девять"] = 9, ["десять"] = 10,
    ["одиннадцать"] = 11, ["двенадцать"] = 12, ["тринадцать"] = 13, ["четырнадцать"] = 14,
    ["пятнадцать"] = 15, ["шестнадцать"] = 16, ["семнадцать"] = 17, ["восемнадцать"] = 18,
    ["девятнадцать"] = 19, ["двадцать"] = 20, ["тридцать"] = 30, ["сорок"] = 40,
    ["пятьдесят"] = 50, ["шестьдесят"] = 60, ["семьдесят"] = 70, ["восемьдесят"] = 80,
    ["девяносто"] = 90, ["сто"] = 100, ["двести"] = 200, ["триста"] = 300, ["четыреста"] = 400,
    ["пятьсот"] = 500, ["шестьсот"] = 600, ["семьсот"] = 700, ["восемьсот"] = 800,
    ["девятьсот"] = 900, ["тысяча"] = 1000, ["тысячи"] = 1000, ["тысяч"] = 1000,
    ["миллион"] = 1000000, ["миллиона"] = 1000000, ["миллионов"] = 1000000,

    -- German
    ["ein"] = 1, ["eine"] = 1, ["eins"] = 1, ["zwei"] = 2, ["drei"] = 3, ["vier"] = 4,
    ["fünf"] = 5, ["fuenf"] = 5, ["sechs"] = 6, ["sieben"] = 7, ["acht"] = 8, ["neun"] = 9,
    ["zehn"] = 10, ["elf"] = 11, ["zwölf"] = 12, ["zwoelf"] = 12, ["zwanzig"] = 20,
    ["dreißig"] = 30, ["dreissig"] = 30, ["vierzig"] = 40, ["fünfzig"] = 50, ["fuenfzig"] = 50,
    ["sechzig"] = 60, ["siebzig"] = 70, ["achtzig"] = 80, ["neunzig"] = 90,
    ["hundert"] = 100, ["tausend"] = 1000,

    -- French
    ["un"] = 1, ["une"] = 1, ["deux"] = 2, ["trois"] = 3, ["quatre"] = 4, ["cinq"] = 5,
    ["six"] = 6, ["sept"] = 7, ["huit"] = 8, ["neuf"] = 9, ["dix"] = 10,
    ["onze"] = 11, ["douze"] = 12, ["treize"] = 13, ["quatorze"] = 14, ["quinze"] = 15,
    ["seize"] = 16, ["vingt"] = 20, ["trente"] = 30, ["quarante"] = 40, ["cinquante"] = 50,
    ["soixante"] = 60, ["cent"] = 100, ["mille"] = 1000,

    -- Spanish
    ["uno"] = 1, ["una"] = 1, ["dos"] = 2, ["tres"] = 3, ["cuatro"] = 4,
    ["cinco"] = 5, ["seis"] = 6, ["siete"] = 7, ["ocho"] = 8, ["nueve"] = 9, ["diez"] = 10,
    ["once"] = 11, ["doce"] = 12, ["trece"] = 13, ["catorce"] = 14, ["quince"] = 15,
    ["veinte"] = 20, ["treinta"] = 30, ["cuarenta"] = 40, ["cincuenta"] = 50,
    ["sesenta"] = 60, ["setenta"] = 70, ["ochenta"] = 80, ["noventa"] = 90,
    ["cien"] = 100, ["ciento"] = 100, ["mil"] = 1000,
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
    ettaro=true, ettari=true, hektary=true,
    metro=true, metros=true, metri=true, metry=true, chilometro=true, chilometri=true, kilometry=true,
    grammo=true, grammi=true, kilogramo=true, kilogramos=true, kilogrames=true, chilogrammo=true, chilogrammi=true,
    chilo=true, chili=true, quilograma=true, quilogramas=true, quilo=true, quilos=true, kilogramy=true,
    litro=true, litros=true, litri=true, litry=true, quadratmeter=true, ["metros cuadrados"]=true, ["metri quadrati"]=true,
    ["metry kwadratowe"]=true, metrekare=true, ["meter persegi"]=true, quadratkilometer=true, ["chilometri quadrati"]=true,
    ["kilometry kwadratowe"]=true, kilometrekare=true, ["kilometer persegi"]=true, quadratdezimeter=true
}

M.NON_ENGLISH_ASCII = NON_ENGLISH_ASCII

-- Returns standard conversion direction based on reader settings
function M.getDefaultDirection(lang)
    if G_reader_settings then
        local setting = G_reader_settings:readSetting("dimension_units")
        if setting == "in" or setting == "imperial" then
            return "to_imperial"
        elseif setting == "mm" or setting == "metric" then
            return "to_metric"
        end
    end
    lang = lang or "en"
    if lang == "en-US" or lang == "en-UK" or lang == "en-GB" or lang == "en" then
        return "to_imperial"
    end
    return "to_metric"
end

local COMMA_LOCALES = {
    de = true, fr = true, es = true, ru = true, uk = true,
    hu = true, pl = true, nl = true, pt_br = true, pt = true, sr = true,
    it = true, tr = true, sk = true, cs = true
}

-- Format number according to locale and smart formatting
function M.formatNumber(val, lang)
    if not val then return "0" end
    local formatted
    if math.abs(val) > 0 and math.abs(val) < 0.01 then
        formatted = string.format("%.4g", val)
    else
        formatted = string.format("%.2f", val)
        formatted = formatted:gsub("0+$", ""):gsub("%.$", "")
    end
    
    local integer_part, decimal_part = formatted:match("^([^%.]*)(%.?.*)$")
    local decimal_sep = "."
    local thousand_sep = ","
    
    if lang and COMMA_LOCALES[lang] then
        decimal_sep = ","
        thousand_sep = "."
    end
    
    local left, num = integer_part:match("^([^%d]*)(%d+)$")
    if num then
        local rev = num:reverse():gsub("(%d%d%d)", "%1" .. thousand_sep):reverse()
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
    str = utf8Lower(str):gsub("\194\160", " "):gsub("\226\128\175", " "):gsub("^%s+", ""):gsub("%s+$", "")
    -- Normalize Unicode minus/dashes to standard hyphen
    str = str:gsub("−", "-"):gsub("–", "-"):gsub("—", "-")
    str = str:gsub("^%-%s+", "-")
    if str == "half" or str == "half a" or str == "half an" or str == "пол" or str == "полтора" or str == "полторы" then
        if str == "полтора" or str == "полторы" then return 1.5 end
        return 0.5
    end
    
    -- Strip thousand separators:
    -- 1) English thousand separator commas (digit followed by comma followed by exactly 3 digits)
    local clean_str = str:gsub("(%d),(%d%d%d%f[%D])", "%1%2")
    -- 2) European thousand separator dots (digit followed by dot followed by exactly 3 digits)
    clean_str = clean_str:gsub("(%d)%.(%d%d%d%f[%D])", "%1%2")
    -- 3) Spaces between digits (e.g. "1 000" or "400 000")
    clean_str = clean_str:gsub("(%d)%s+(%d)", "%1%2")
    -- Replace European comma with dot for conversion if present
    clean_str = clean_str:gsub(",", ".")
    local num = tonumber(clean_str)
    if num then return num end
    
    -- Try compound written numbers
    local wvals = {}
    local found = false
    for word in str:gmatch("[%S]+") do
        local clean_w = utf8Lower(word):gsub("[%-,]$", "")
        if clean_w ~= "and" and clean_w ~= "a" and clean_w ~= "an" and clean_w ~= "и" and clean_w ~= "und" and clean_w ~= "et" and clean_w ~= "y" then
            local wval = WRITTEN_NUMBERS[clean_w]
            if not wval then return nil end
            table.insert(wvals, wval)
            found = true
        end
    end
    if not found then return nil end

    -- Preprocess to insert 100 between unit (1-9) and tens/teens (10-99)
    local i = 1
    while i < #wvals do
        local v1 = wvals[i]
        local v2 = wvals[i+1]
        if v1 >= 1 and v1 <= 9 and v2 >= 10 and v2 <= 99 then
            table.insert(wvals, i + 1, 100)
            i = i + 1
        end
        i = i + 1
    end

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

    local factors = {
        length = {
            ["in"] = 0.0254, ["inch"] = 0.0254, ["inches"] = 0.0254,
            ["ft"] = 0.3048, ["foot"] = 0.3048, ["feet"] = 0.3048,
            ["yd"] = 0.9144, ["yard"] = 0.9144, ["yards"] = 0.9144,
            ["mi"] = 1609.344, ["mile"] = 1609.344, ["miles"] = 1609.344,
            ["league"] = 4828.032, ["leagues"] = 4828.032,
            ["fathom"] = 1.8288, ["fathoms"] = 1.8288,
            ["mm"] = 0.001, ["millimeter"] = 0.001, ["millimeters"] = 0.001, ["millimetre"] = 0.001, ["millimetres"] = 0.001,
            ["cm"] = 0.01, ["centimeter"] = 0.01, ["centimeters"] = 0.01, ["centimetre"] = 0.01, ["centimetres"] = 0.01,
            ["dm"] = 0.1, ["decimeter"] = 0.1, ["decimeters"] = 0.1, ["decimetre"] = 0.1, ["decimetres"] = 0.1,
            ["m"] = 1.0, ["meter"] = 1.0, ["meters"] = 1.0, ["metre"] = 1.0, ["metres"] = 1.0,
            ["km"] = 1000.0, ["kilometer"] = 1000.0, ["kilometers"] = 1000.0, ["kilometre"] = 1000.0, ["kilometres"] = 1000.0,
        },
        weight = {
            ["oz"] = 0.028349523125, ["ounce"] = 0.028349523125, ["ounces"] = 0.028349523125,
            ["lb"] = 0.45359237, ["lbs"] = 0.45359237, ["pound"] = 0.45359237, ["pounds"] = 0.45359237,
            ["st"] = 6.35029318, ["stone"] = 6.35029318, ["stones"] = 6.35029318,
            ["g"] = 0.001, ["gram"] = 0.001, ["grams"] = 0.001, ["gramme"] = 0.001, ["grammes"] = 0.001,
            ["kg"] = 1.0, ["kilogram"] = 1.0, ["kilograms"] = 1.0, ["kilogramme"] = 1.0, ["kilogrammes"] = 1.0,
        },
        volume = {
            ["fl oz"] = 0.0295735295625, ["fl. oz."] = 0.0295735295625, ["fluid ounce"] = 0.0295735295625, ["fluid ounces"] = 0.0295735295625,
            ["cup"] = 0.2365882365, ["cups"] = 0.2365882365,
            ["pt"] = 0.473176473, ["pint"] = 0.473176473, ["pints"] = 0.473176473,
            ["qt"] = 0.946352946, ["quart"] = 0.946352946, ["quarts"] = 0.946352946,
            ["gal"] = 3.785411784, ["gallon"] = 3.785411784, ["gallons"] = 3.785411784,
            ["ml"] = 0.001, ["mL"] = 0.001, ["milliliter"] = 0.001, ["milliliters"] = 0.001, ["millilitre"] = 0.001, ["millilitres"] = 0.001,
            ["l"] = 1.0, ["L"] = 1.0, ["liter"] = 1.0, ["liters"] = 1.0, ["litre"] = 1.0, ["litres"] = 1.0,
            ["m3"] = 1000.0, ["m³"] = 1000.0, ["cubic meter"] = 1000.0, ["cubic meters"] = 1000.0, ["cubic metre"] = 1000.0, ["cubic metres"] = 1000.0,
            ["ft3"] = 28.316846592, ["ft³"] = 28.316846592, ["cubic foot"] = 28.316846592, ["cubic feet"] = 28.316846592,
            ["in3"] = 0.016387064, ["in³"] = 0.016387064, ["cubic inch"] = 0.016387064, ["cubic inches"] = 0.016387064,
            ["cm3"] = 0.001, ["cm³"] = 0.001, ["cubic centimeter"] = 0.001, ["cubic centimeters"] = 0.001, ["cc"] = 0.001,
        },
        speed = {
            ["mph"] = 1.609344, ["miles per hour"] = 1.609344,
            ["km/h"] = 1.0, ["kmh"] = 1.0, ["kph"] = 1.0, ["kilometers per hour"] = 1.0, ["kilometres per hour"] = 1.0,
        },
        area = {
            ["sq ft"] = 0.09290304, ["ft2"] = 0.09290304, ["ft²"] = 0.09290304, ["square feet"] = 0.09290304,
            ["sq mi"] = 2589988.11, ["mi2"] = 2589988.11, ["mi²"] = 2589988.11, ["square miles"] = 2589988.11,
            ["acre"] = 4046.8564224, ["acres"] = 4046.8564224,
            ["sq m"] = 1.0, ["m2"] = 1.0, ["m²"] = 1.0, ["square meters"] = 1.0, ["square metres"] = 1.0,
            ["sq km"] = 1000000.0, ["km2"] = 1000000.0, ["km²"] = 1000000.0, ["square kilometers"] = 1000000.0, ["square kilometres"] = 1000000.0,
            ["ha"] = 10000.0, ["hectare"] = 10000.0, ["hectares"] = 10000.0,
            ["sq dm"] = 0.01, ["dm2"] = 0.01, ["dm²"] = 0.01, ["square decimeters"] = 0.01, ["square decimeter"] = 0.01, ["square decimetres"] = 0.01, ["square decimetre"] = 0.01,
            ["sq in"] = 0.00064516, ["in2"] = 0.00064516, ["in²"] = 0.00064516, ["square inches"] = 0.00064516, ["square inch"] = 0.00064516,
            ["sq cm"] = 0.0001, ["cm2"] = 0.0001, ["cm²"] = 0.0001, ["square centimeters"] = 0.0001, ["square centimeter"] = 0.0001, ["square centimetres"] = 0.0001, ["square centimetre"] = 0.0001,
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

-- Comprehensive Unit Definitions with standard targets, categories, and multilingual aliases
local UNITS = {
    -- LENGTH
    { category = "length", system = "imperial", name = "inch", std_target = "cm", aliases = {
        "inches", "inch", "in",
        "zoll", "pulgada", "pulgadas", "pulg", "pouce", "pouces", "po", "pollice", "pollici",
        "polegada", "polegadas", "pol", "cal", "cale", "cali", "cala", "calach", "calami", "calom",
        "дюймов", "дюйма", "дюйм", "дюймы", "дюйме", "дюйму", "дюймом", "дюймах", "дюймам", "дюймами",
        "дюймів", "дюймі",
        "инча", "инчи", "инч", "inča", "inči", "inč",
        "hüvelyk", "coll", "inç", "inci", "بوصة", "بوصات", "بوصتين", "英寸", "吋", "インチ"
    } },
    { category = "length", system = "imperial", name = "foot", std_target = "m", aliases = {
        "feet", "foot", "ft",
        "füße", "fuesse", "fuß", "fuss", "pie", "pies", "pied", "pieds", "pi", "piede", "piedi",
        "pé", "pés", "voet", "voeten", "stopa", "stopy", "stóp", "stopie", "stopę", "stopą", "stopami", "stopach", "stop",
        "футов", "фута", "фут", "футы", "футе", "футу", "футом", "футах", "футам", "футами",
        "футів", "футі",
        "стопа", "стопе", "стопи", "стопу", "стопом", "stopa", "stope", "stopi",
        "láb", "ayak", "kaki", "قدم", "أقدام", "اقدام", "قدمين", "英尺", "呎", "フィート", "フート"
    } },
    { category = "length", system = "imperial", name = "yard", std_target = "m", aliases = {
        "yards", "yard", "yd",
        "yarda", "yardas", "verge", "verges", "iarda", "iarde", "jarda", "jardas",
        "jard", "jardy", "jardów", "jarda", "jardem", "jardzie", "jardach", "jardami",
        "ярдов", "ярда", "ярд", "ярды", "ярде", "ярду", "ярдом", "ярдах", "ярдам", "ярдами",
        "ярдів", "ярді",
        "јарда", "јарди", "јард", "jarda", "jardi", "jard",
        "yard", "yarda", "ياردا", "ياردة", "يارده", "ياردات", "ياردتين", "码", "ヤード"
    } },
    { category = "length", system = "imperial", name = "mile", std_target = "km", aliases = {
        "miles", "mile", "mi",
        "meile", "meilen", "milla", "millas", "mille", "milles", "miglio", "miglia",
        "milha", "milhas", "mijl", "mijlen", "mila", "mile", "mil", "mili", "milę", "milą", "milami", "milach",
        "миль", "мили", "миля", "милю", "миле", "милей", "милею", "милям", "милями", "милях",
        "милі",
        "миља", "миље", "миљи", "миљом", "миљу", "milja", "milje", "milji",
        "mérföld", "أميال", "اميال", "ميل", "ميلين", "英里", "哩", "マイル"
    } },
    { category = "length", system = "imperial", name = "league", std_target = "km", aliases = {
        "leagues", "league", "leugen", "leuge", "wegstunden", "wegstunde", "leguas", "legua", "lieues", "lieue",
        "leghe", "lega", "léguas", "légua", "ligi", "lig", "liga",
        "лиг", "лиги", "лига", "лиге", "лигу", "лигой", "лигою", "лигам", "лигами", "лигах",
        "ліг", "ліги", "ліга", "лігу", "лігою", "лігами", "лігах",
        "лиге", "lige", "里格", "リーグ"
    } },
    { category = "length", system = "imperial", name = "fathom", std_target = "m", aliases = {
        "fathoms", "fathom", "faden", "klafter", "brazas", "braza", "brasses", "brasse", "braccia", "braccio",
        "braças", "braça", "sążnie", "sążni", "sążeń",
        "морских саженей", "морской сажени", "морская сажень", "саженей", "сажени", "сажень", "саженям", "саженями", "саженях",
        "фатомов", "фатома", "фатом", "фатомы", "фатому", "фатомом", "фатоме", "фатомах",
        "сажнів", "сажні", "фатомів",
        "öl", "kulaç", "depa", "英寻", "㖊", "ファゾム", "尋"
    } },
    
    { category = "length", system = "metric", name = "mm", std_target = "inch", aliases = {
        "millimeters", "millimeter", "mm", "millimetres", "millimetre",
        "миллиметров", "миллиметра", "миллиметр", "миллиметры", "миллиметрах", "миллиметрам", "миллиметрами", "мм",
        "міліметрів", "міліметра", "міліметр", "міліметри",
        "milímetros", "milímetro", "millimètres", "millimètre", "millimetri", "millimetro",
        "milimetrów", "milimetry", "milimetr", "miliméter", "milimetre", "milimeter",
        "مليمتر", "مليمترات", "مم", "毫米", "ミリメートル"
    } },
    { category = "length", system = "metric", name = "cm", std_target = "inch", aliases = {
        "centimeters", "centimeter", "cm", "centimetres", "centimetre",
        "сантиметров", "сантиметра", "сантиметр", "сантиметры", "сантиметрах", "сантиметрам", "сантиметрами", "см",
        "сантиметрів", "сантиметрі",
        "centímetros", "centímetro", "centimètres", "centimètre", "centimetri", "centimetro",
        "centymetrów", "centymetry", "centymetr", "centiméter", "santimetre", "sentimeter",
        "سنتيمتر", "سنتيمترات", "سم", "厘米", "公分", "センチメートル", "センチ"
    } },
    { category = "length", system = "metric", name = "dm", std_target = "inch", aliases = {
        "decimeters", "decimeter", "dm", "decimetres", "decimetre",
        "дециметров", "дециметра", "дециметр", "дециметры", "дм", "дециметрів",
        "decímetros", "decímetro", "décimètres", "décimètre", "decimetri", "decimetro",
        "decymetrów", "decymetry", "decymetr", "deciméter", "desimetre", "desimeter",
        "ديسيمتر", "分米", "デシメートル"
    } },
    { category = "length", system = "metric", name = "m", std_target = "foot", aliases = {
        "meters", "meter", "m", "metres", "metre", "metro", "metros", "mètre", "mètres", "metri", "metr", "metry", "metrów",
        "метров", "метра", "метр", "метры", "метре", "метру", "метром", "метрах", "метрам", "метрами", "м",
        "метрів", "метрі",
        "méter", "متر", "أمتار", "امار", "米", "公尺", "メートル"
    } },
    { category = "length", system = "metric", name = "km", std_target = "mile", aliases = {
        "kilometers", "kilometer", "km", "kilometres", "kilometre", "kilómetro", "kilómetros", "kilomètre", "kilomètres",
        "chilometro", "chilometri", "quilômetro", "quilômetros", "kilometry", "kilometrów", "kilometr",
        "километров", "километра", "километр", "километры", "километре", "километру", "километром", "километрах", "километрам", "километрами", "км",
        "кілометрів", "кілометра", "кілометр", "кілометри", "кілометрі",
        "kilométer", "كيلومتر", "كيلومترات", "كم", "公里", "千米", "キロメートル", "キロ"
    } },

    -- WEIGHT
    { category = "weight", system = "imperial", name = "oz", std_target = "g", aliases = {
        "ounces", "ounce", "oz",
        "unze", "unzen", "onza", "onzas", "once", "onces", "oncia",
        "uncja", "uncje", "uncji", "uncję", "uncją", "uncjami", "uncjach",
        "унций", "унции", "унция", "унцию", "унцией", "унциею", "унциям", "унциями", "унциях", "унц.",
        "унцій", "унцією",
        "унце", "унци", "унца", "unce", "unci", "unca",
        "uncia", "ons", "أوقية", "أوقيات", "اوقية", "اوقيات", "أونصة", "اونصة", "盎司", "オンス"
    } },
    { category = "weight", system = "imperial", name = "lb", std_target = "kg", aliases = {
        "pounds", "pound", "lbs", "lb",
        "pfund", "libra", "libras", "livre", "livres", "libbra", "libbre",
        "funt", "funty", "funtów", "funta", "funtem", "funcie", "funtach", "funtami",
        "фунтов", "фунта", "фунт", "фунты", "фунте", "фунту", "фунтом", "фунтах", "фунтам", "фунтами",
        "фунтів", "фунті",
        "фунти", "фунте", "фунта", "funti", "funte", "funta",
        "font", "libreler", "libre", "pon", "رطل", "أرطال", "ارطال", "رطلين", "باوندات", "باوند", "磅", "ポンド"
    } },
    { category = "weight", system = "imperial", name = "st", std_target = "kg", aliases = {
        "stones", "stone", "st",
        "стоунов", "стоуна", "стоун", "стоуны", "стоуне", "стоуну", "стоуном", "стоунах",
        "стоунів", "kamienie", "kamieni", "kamień", "英石"
    } },

    { category = "weight", system = "metric", name = "g", std_target = "oz", aliases = {
        "grams", "gram", "g", "grammes", "gramme", "gramm", "gramo", "gramos", "grammo", "grammi", "grama", "gramas", "gramy", "gramów",
        "граммов", "грамма", "грамм", "граммы", "граммах", "граммам", "граммами", "г", "гр",
        "грамів", "грама", "грам",
        "جرام", "جرامات", "غرام", "غرامات", "غم", "克", "公克", "グラム"
    } },
    { category = "weight", system = "metric", name = "kg", std_target = "lb", aliases = {
        "kilograms", "kilogram", "kg", "kilogrammes", "kilogramme", "kilogramm", "kilogramo", "kilogramos", "kilogrames", "kilo", "kilos",
        "chilogrammo", "chilogrammi", "chilo", "chili", "quilograma", "quilogramas", "quilo", "quilos", "kilogramy", "kilogramów",
        "килограммов", "килограмма", "килограмм", "килограммы", "килограммах", "килограммам", "килограммами", "кило", "кг",
        "кілограмів", "кілограма", "кілограм", "кілограми",
        "كيلوجرام", "كيلوجرامات", "كيلو", "كغم", "公斤", "千克", "キログラム", "キロ"
    } },

    -- TEMPERATURE
    { category = "temp", system = "imperial", name = "f", std_target = "c", aliases = {
        "degrees fahrenheit", "degree fahrenheit", "deg f", "deg. f", "degrees f", "degree f",
        "fahrenheit", "°fahrenheit", "ºfahrenheit", "°f", "ºf", "°F", "°Fahrenheit", "ºF", "ºFahrenheit", "of", "oF", "0f", "0F", "f",
        "градусов по фаренгейту", "градуса по фаренгейту", "градус по фаренгейту", "по фаренгейту",
        "градусов фаренгейта", "градуса фаренгейта", "градус фаренгейта", "град. фаренгейта", "град. по фаренгейту", "°ф", "°f",
        "градусів за фаренгейтом", "градуси за фаренгейтом", "градус за фаренгейтом", "за фаренгейтом", "градусів фаренгейта", "градус фаренгейта",
        "степени фаренхајта", "степен фаренхајта", "stepeni farenhajta", "stepen farenhajta",
        "grad fahrenheit", "degrés fahrenheit", "degré fahrenheit", "grados fahrenheit", "grado fahrenheit",
        "gradi fahrenheit", "grado fahrenheit", "graus fahrenheit", "grau fahrenheit",
        "stopni fahrenheita", "stopnie fahrenheita", "stopień fahrenheita", "stopni fahrenheit",
        "fok fahrenheit", "derece fahrenheit", "derajat fahrenheit",
        "درجات فهرنهايت", "درجة فهرنهايت", "فهرنهايت", "°ف",
        "华氏度", "华氏", "度华氏", "華氏", "度華氏"
    } },
    { category = "temp", system = "metric", name = "c", std_target = "f", aliases = {
        "degrees celsius", "degree celsius", "degrees celcius", "degree celcius", "deg c", "deg. c", "degrees c", "degree c",
        "celsius", "celcius", "°celsius", "°celcius", "ºcelsius", "ºcelcius", "°c", "ºc", "°C", "°Celsius", "°Celcius", "ºC", "ºCelsius", "ºCelcius", "oc", "oC", "0c", "0C", "c",
        "градусов по цельсию", "градуса по цельсию", "градус по цельсию", "по цельсию",
        "градусов цельсия", "градуса цельсия", "градус цельсия", "град. цельсия", "град. по цельсию", "°с",
        "градусів за цельсієм", "градуси за цельсієм", "градус за цельсієм", "за цельсієм", "градусів цельсія", "градус цельсія",
        "степени целзијуса", "степен целзијуса", "stepeni celzijusa", "stepen celzijusa",
        "grad celsius", "degrés celsius", "degré celsius", "grados celsius", "grado celsius",
        "gradi celsius", "grado celsius", "graus celsius", "grau celsius",
        "stopni celsjusza", "stopnie celsjusza", "stopień celsjusza", "stopni celsius",
        "fok celsius", "derece celsius", "derajat celsius",
        "درجات مئوية", "درجة مئوية", "درجات سيلزيوس", "درجة سيلزيوس", "سيلزيوس", "°م",
        "摄氏度", "摄氏", "度摄氏", "摂氏", "度摂氏"
    } },

    -- VOLUME
    { category = "volume", system = "imperial", name = "fl oz", std_target = "ml", aliases = {
        "fluid ounces", "fluid ounce", "fl oz", "fl. oz.",
        "жидких унций", "жидкой унции", "жидкая унция", "жидкие унции", "жидкую унцию", "жидкими унциями", "жидких унциях", "ж. унц.",
        "рідких унцій", "рідка унція",
        "flüssigunzen", "flüssigunze", "onces liquides", "once liquide", "onzas líquidas", "onza líquida",
        "once fluide", "oncia fluida", "onças fluidas", "onça fluida",
        "uncji płynu", "uncje płynu", "uncja płynu", "液体盎司", "液量盎司"
    } },
    { category = "volume", system = "imperial", name = "cup", std_target = "ml", aliases = {
        "cups", "cup",
        "чашек", "чашки", "чашка", "чашку", "чашке", "чашкой", "чашкам", "чашками", "чашках",
        "чашок", "чашці",
        "tassen", "tasse", "tasses", "tazas", "taza", "tazze", "tazza", "xícaras", "xícara", "copos", "copo",
        "szklanek", "szklanki", "szklanka", "kubków", "kubki", "kubek", "杯"
    } },
    { category = "volume", system = "imperial", name = "pint", std_target = "ml", aliases = {
        "pints", "pint", "pt",
        "пинт", "пинты", "пинта", "пинту", "пинте", "пинтой", "пинтами", "пинтах",
        "пінт", "пінти", "пінта", "пінту",
        "pinten", "pinte", "pintes", "pintas", "pinta", "pinte", "pinta", "pinty", "pint",
        "品脱"
    } },
    { category = "volume", system = "imperial", name = "quart", std_target = "l", aliases = {
        "quarts", "quart", "qt",
        "кварт", "кварты", "кварта", "кварту", "кварте", "квартой", "квартами", "квартах",
        "кварт", "кварти", "кварта",
        "chopines", "chopine", "cuartos", "cuarto", "quarti", "quarto", "quartos", "quarto", "kwarty", "kwart", "kwarta", "夸脱"
    } },
    { category = "volume", system = "imperial", name = "gallon", std_target = "l", aliases = {
        "gallons", "gallon", "gal",
        "галлонов", "галлона", "галлон", "галлоны", "галлону", "галлоном", "галлоне", "галлонах",
        "галонів", "галона", "галон", "галони", "галонах",
        "галона", "галони", "галон", "galona", "galoni", "galon",
        "gallone", "gallonen", "galón", "galones", "galloni", "galão", "galões", "galonów", "galony", "galonlar",
        "جالونات", "جالون", "غالونات", "غالون", "加仑", "ガロン"
    } },

    { category = "volume", system = "metric", name = "ml", std_target = "fl oz", aliases = {
        "milliliters", "milliliter", "ml", "mL", "millilitres", "millilitre",
        "миллилитров", "миллилитра", "миллилитр", "миллилитры", "мл",
        "мілілітрів", "мілілітра", "мілілітр", "мілілітри",
        "mililitros", "mililitro", "millilitres", "millilitre", "millilitri", "millilitro",
        "mililitrów", "mililitry", "mililitr", "mililiter", "mililitre",
        "مليلتر", "مليلترات", "مل", "毫升", "ミリリットル"
    } },
    { category = "volume", system = "metric", name = "l", std_target = "gallon", aliases = {
        "liters", "liter", "l", "L", "litres", "litre", "litro", "litros", "litri", "litr", "litry", "litrów",
        "литров", "литра", "литр", "литры", "литрах", "литрам", "литрами", "л",
        "літрів", "літра", "літр", "літри", "літрах",
        "литара", "литре", "литар", "litara", "litre", "litar",
        "liter", "litre", "لتر", "لترات", "升", "公升", "リットル"
    } },

    { category = "volume", system = "metric", name = "m³", std_target = "ft3", aliases = {
        "cubic meters", "cubic meter", "cubic metres", "cubic metre", "m3", "m³",
        "кубических метров", "кубического метра", "кубический метр", "кубические метры", "куб. м", "куб. метров", "м³", "м3",
        "кубічних метрів", "кубічного метра", "кубічний метр", "куб. м",
        "kubikmeter", "mètres cubes", "mètre cube", "metros cúbicos", "metro cúbico", "metri cubi", "metro cubo",
        "metry sześcienne", "metrów sześciennych", "köbméter", "metreküp", "meter kubik",
        "متر مكعب", "أمتار مكعبة", "م³", "م3", "立方米", "立方メートル"
    } },
    { category = "volume", system = "imperial", name = "ft3", std_target = "m³", aliases = {
        "cubic feet", "cubic foot", "ft3", "ft³",
        "кубических футов", "кубического фута", "кубический фут", "кубические футы", "куб. фут", "куб. футов", "фут³", "фут3",
        "кубічних футів", "кубічний фут",
        "kubikfuß", "pieds cubes", "pied cube", "pies cúbicos", "pie cúbico", "piedi cubi", "piede cubo",
        "pés cúbicos", "pé cúbico", "stóp sześciennych", "قدم مكعب", "أقدام مكعبة", "立方英尺", "立方呎", "立方フィート"
    } },
    { category = "volume", system = "imperial", name = "in3", std_target = "cm³", aliases = {
        "cubic inches", "cubic inch", "in3", "in³",
        "кубических дюймов", "кубического дюйма", "кубический дюйм", "кубические дюймы", "куб. дюйм", "дюйм³", "дюйм3",
        "кубічних дюймів", "кубічний дюйм",
        "kubikzoll", "pouces cubes", "pulgadas cúbicas", "pollici cubi", "polegadas cúbicas", "cali sześciennych",
        "بوصة مكعبة", "立方英寸", "立方吋", "立方インチ"
    } },
    { category = "volume", system = "metric", name = "cm³", std_target = "in3", aliases = {
        "cubic centimeters", "cubic centimeter", "cubic centimetres", "cubic centimetre", "cm3", "cm³", "cc",
        "кубических сантиметров", "кубического сантиметра", "кубический сантиметр", "кубические сантиметры", "куб. см", "см³", "см3",
        "кубічних сантиметрів", "кубічний сантиметр",
        "kubikzentimeter", "ccm", "centimètres cubes", "centímetro cúbico", "centímetros cúbicos", "centimetri cubi", "centímetro cúbico",
        "centymetrów sześciennych", "köbcentiméter", "santimetreküp", "sentimeter kubik",
        "سنتيمتر مكعب", "سم³", "سم3", "立方厘米", "立方公分", "立方センチメートル"
    } },

    -- SPEED
    { category = "speed", system = "imperial", name = "mph", std_target = "km/h", aliases = {
        "miles per hour", "mph",
        "миль в час", "мили в час", "миля в час", "милю в час", "миль/ч", "миль/час",
        "миль на годину", "милі на годину", "миля на годину", "милю на годину", "миль/год",
        "миља на сат", "миља на час", "milja na sat", "milja na čas",
        "meilen pro stunde", "milles à l'heure", "milles par heure",
        "millas por hora", "miglia orarie", "miglia all'ora", "miglia per ora", "milhas por hora",
        "mil na godzinę", "mile na godzinę", "mila na godzinę", "mijl per uur", "mérföld per óra",
        "mil/saat", "mil bölü saat", "mil per jam",
        "ميل في الساعة", "ميل/ساعة", "أميال في الساعة", "اميال في الساعة",
        "英里/小时", "英里每小时", "迈", "マイル毎時"
    } },
    { category = "speed", system = "metric", name = "km/h", std_target = "mph", aliases = {
        "kilometers per hour", "kilometres per hour", "km/h", "kmh", "kph",
        "километров в час", "километра в час", "километр в час", "км/ч", "км/час",
        "кілометрів на годину", "кілометри на годину", "кілометр на годину", "км/год",
        "километара на сат", "километара на час", "км/ч", "км/х", "km/h", "km/č", "kilometara na sat",
        "kilometer pro stunde", "stundenkilometer",
        "kilomètres à l'heure", "kilomètres par heure", "kilómetros por hora",
        "chilometri orari", "chilometri all'ora", "chilometri per ora", "quilômetros por hora",
        "kilometrów na godzinę", "kilometry na godzinę", "kilometr na godzinę",
        "km/u", "kilometer per uur", "kilométer per óra", "km/ó", "km/s", "km/saat", "kilometre/saat", "km/jam", "kilometer per jam",
        "كيلومتر في الساعة", "كيلومتر/ساعة", "كم/س", "كم/ساعة",
        "公里/小时", "公里/小時", "千米/小时", "キロメートル毎時"
    } },

    -- AREA
    { category = "area", system = "imperial", name = "sq ft", std_target = "m²", aliases = {
        "square feet", "square foot", "sq ft", "ft2", "ft²",
        "квадратных футов", "квадратного фута", "квадратный фут", "квадратные футы", "кв. футов", "кв. фута", "кв. фут", "кв. футы", "кв. футах", "фут²", "фут2",
        "квадратних футів", "квадратного фута", "квадратний фут", "кв. фут", "кв. футів",
        "квадратних стопа", "квадратне стопе", "kvadratnih stopa", "kvadratne stope",
        "quadratfuß", "pieds carrés", "pied carré", "pies cuadrados", "pie cuadrado", "piedi quadrati", "piede quadrato", "pés quadrados", "pé quadrado",
        "stóp kwadratowych", "stopa kwadratowa", "vierkante voet", "négyzetláb", "fitkare", "kaki persegi",
        "أقدام مربعة", "اقدام مربعة", "قدم مربع", "قدمين مربعين", "平方英尺", "平方呎", "平方フィート"
    } },
    { category = "area", system = "imperial", name = "sq mi", std_target = "km²", aliases = {
        "square miles", "square mile", "sq mi", "mi2", "mi²",
        "квадратных миль", "квадратной мили", "квадратная миля", "квадратные мили", "кв. миль", "кв. мили", "кв. миля", "кв. милях", "миля²", "миля2",
        "квадратних миль", "квадратна миля", "кв. миль",
        "квадратних миља", "kvadratnih milja",
        "quadratmeilen", "milles carrés", "mille carré", "millas cuadradas", "milla cuadrada", "miglia quadrate", "miglio quadrato", "milhas quadradas", "milha quadrada",
        "mil kwadratowych", "mila kwadratowa", "vierkante mijl", "négyzetmérföld", "milkare", "mil persegi",
        "أميال مربعة", "اميال مربعة", "ميل مربع", "平方英里", "平方哩", "平方マイル"
    } },
    { category = "area", system = "imperial", name = "acre", std_target = "ha", aliases = {
        "acres", "acre",
        "акров", "акра", "акр", "акры", "акру", "акром", "акре", "акрах", "акрам", "акрами",
        "акрів", "акри",
        "акера", "акра", "aker", "akra",
        "acren", "morgen", "acri", "acro", "akrów", "akry", "akr", "bunder", "hold", "akre", "dönüm", "ekar",
        "فدادين", "فدان", "أكر", "اكر", "英亩", "エーカー"
    } },
    { category = "area", system = "imperial", name = "sq in", std_target = "cm²", aliases = {
        "square inches", "square inch", "sq in", "in2", "in²",
        "квадратных дюймов", "квадратного дюйма", "квадратный дюйм", "квадратные дюймы", "кв. дюймов", "кв. дюйма", "кв. дюйм", "дюйм²", "дюйм2",
        "квадратних дюймів", "квадратний дюйм",
        "quadratzoll", "pouces carrés", "pouce carré", "pulgadas cuadradas", "pulgada cuadrada", "pollici quadrati", "pollici quadrato", "polegadas quadradas", "polegada quadrada",
        "cali kwadratowych", "cal kwadratowy", "vierkante duim", "hüvelyk²", "inçkare", "inci persegi",
        "بوصات مربعة", "بوصة مربعة", "平方英寸", "平方吋", "平方インチ"
    } },

    { category = "area", system = "metric", name = "m²", std_target = "sq ft", aliases = {
        "square meters", "square metres", "sq m", "m2", "m²", "qm", "quadratmeter", "metros cuadrados", "mètres carrés", "metri quadrati", "médos quadrados", "metry kwadratowe",
        "квадратных метров", "квадратного метра", "квадратный метр", "квадратные метры", "кв. метров", "кв. метра", "кв. метр", "кв. м", "кв. метрах", "м²", "м2",
        "квадратних метрів", "квадратного метра", "квадратний метр", "кв. м",
        "квадратних метара", "квадратни метар", "kvadratnih metara", "kvadratni metar",
        "négyzetméter", "metrekare", "متر مربع", "أمتار مربعة", "امار مربعة", "м²", "м2", "meter persegi", "平方米", "平方公尺", "平方メートル"
    } },
    { category = "area", system = "metric", name = "km²", std_target = "sq mi", aliases = {
        "square kilometers", "square kilometres", "sq km", "km2", "km²", "qkm", "quadratkilometer", "kilómetros cuadrados", "kilomètres carrés", "chilometri quadrati", "quilômetros quadrados", "kilometry kwadratowe",
        "квадратных километров", "квадратного километра", "квадратный километр", "квадратные километры", "кв. километров", "кв. километра", "кв. километр", "кв. км", "кв. километрах", "км²", "км2",
        "квадратних кілометрів", "квадратного кілометра", "квадратний кілометр", "кв. км",
        "квадратних километара", "kvadratnih kilometara",
        "négyzetkilométer", "kilometrekare", "كيلومتر مربع", "كيلومترات مربعة", "كم²", "كم2", "kilometer persegi", "平方公里", "平方千米", "平方キロメートル"
    } },
    { category = "area", system = "metric", name = "ha", std_target = "acre", aliases = {
        "hectares", "hectare", "ha", "hektar", "hectárea", "hectáreas", "ettaro", "ettari", "hektary", "hektarów",
        "гектаров", "гектара", "гектар", "гектары", "гектарах", "гектарам", "гектарами", "га",
        "гектарів", "гектарі",
        "хектара", "хектар", "hektara",
        "hektár", "هكتار", "هكتارات", "公顷", "ヘクタール"
    } },
    { category = "area", system = "metric", name = "sq dm", std_target = "sq ft", aliases = {
        "square decimeters", "square decimeter", "sq dm", "dm2", "dm²", "square decimetres", "square decimetre", "quadratdezimeter", "décimètres carrés", "décimètre carré",
        "квадратных дециметров", "квадратный дециметр", "кв. дм", "дм²", "дм2", "квадратних дециметрів"
    } },
    { category = "area", system = "metric", name = "cm²", std_target = "sq in", aliases = {
        "square centimeters", "square centimeter", "square centimetres", "square centimetre", "sq cm", "cm2", "cm²",
        "квадратных сантиметров", "квадратного сантиметра", "квадратный сантиметр", "кв. см", "см²", "см2", "квадратних сантиметрів",
        "centimètres carrés", "centímetros cuadrados", "centimetri quadrati", "centímetros quadrados", "centymetrów kwadratowych",
        "négyzetcentiméter", "santimetrekare", "سنتيمتر مربع", "سم²", "سم2", "平方厘米", "平方センチメートル"
    } },
}

-- Prepopulate UNIT_LOOKUP hash table with lowercase aliases
local UNIT_LOOKUP = {}
for _, u in ipairs(UNITS) do
    for _, alias in ipairs(u.aliases) do
        UNIT_LOOKUP[utf8Lower(alias)] = u
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
    -- Russian
    ["несколько"] = {3, 7},
    ["пару"] = {2, 2},
    ["пара"] = {2, 2},
    ["пары"] = {2, 2},
}
local VAGUE_ORDER = {
    "a couple of", "a couple", "couple of", "several", "a few", "couple", "some", "few",
    "несколько", "пару", "пара", "пары"
}
local VAGUE_MULTIPLIERS = {
    dozen = 12,
    hundred = 100,
    thousand = 1000,
    million = 1000000,
    -- Russian
    ["десятков"] = 10,
    ["десятка"] = 10,
    ["десяток"] = 10,
    ["дюжина"] = 12,
    ["дюжины"] = 12,
    ["дюжин"] = 12,
    ["сотен"] = 100,
    ["сотни"] = 100,
    ["сотня"] = 100,
    ["тысяч"] = 1000,
    ["тысячи"] = 1000,
    ["тысяча"] = 1000,
    ["миллионов"] = 1000000,
    ["миллиона"] = 1000000,
    ["миллион"] = 1000000,
}

local function detectVagueQuantifier(prev_text)
    if not prev_text then return nil end
    local p = utf8Lower(prev_text):gsub("%s+$", "")
    local mword = p:match("([%a\194-\244][\128-\191%a%d]*)$")
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
    if start_pos > 3 then
        local three_bytes = text:sub(start_pos - 3, start_pos - 1)
        if three_bytes == "−" or three_bytes == "–" or three_bytes == "—" then
            return three_bytes
        end
    end
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
        direction = M.getDefaultDirection(current_lang)
    end
    enabled_categories = enabled_categories or {
        length = true, weight = true, temp = true, volume = true, speed = true, area = true
    }
    
    local results = {}
    local text_lower = utf8Lower(text):gsub("\194\160", " "):gsub("\226\128\175", " ")

    -- 1. Compound length units (e.g. 6 feet 2 inches, 6'2", 6 футов 2 дюйма, 6 футов и 2 дюйма)
    if enabled_categories.length and (direction == "to_metric" or direction == "auto") then
        if text_lower:find("'", 1, true) and text_lower:find("\"", 1, true) then
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
        end
        
        local ft_aliases = {
            "feet", "foot", "ft",
            "футов", "фута", "фут", "футы", "футів", "футі",
            "füße", "fuß", "pieds", "pied", "pies", "pie", "piedi", "piede", "pés", "pé"
        }
        local in_aliases = {
            "inches", "inch", "in",
            "дюймов", "дюйма", "дюйм", "дюймы", "дюймів", "дюймі",
            "zoll", "pouces", "pouce", "pulgadas", "pulgada", "pollici", "pollice", "polegadas", "polegada"
        }
        
        -- Fast pre-check: only test foot/inch pairs that actually occur in text_lower
        local present_ft = {}
        for _, ft_a in ipairs(ft_aliases) do
            if text_lower:find(ft_a, 1, true) then
                table.insert(present_ft, ft_a)
            end
        end
        
        local present_in = {}
        for _, in_a in ipairs(in_aliases) do
            if text_lower:find(in_a, 1, true) then
                table.insert(present_in, in_a)
            end
        end
        
        if #present_ft > 0 and #present_in > 0 then
            local length_connectors = { "", "and", "и", "und", "et", "y", "e", "," }
            for _, ft_a in ipairs(present_ft) do
                for _, in_a in ipairs(present_in) do
                    for _, conn in ipairs(length_connectors) do
                        if conn == "" or conn == "," or text_lower:find(conn, 1, true) then
                            local init = 1
                            local pattern
                            if conn == "" then
                                pattern = "(%d+)%s*" .. ft_a .. "%s*(%d+)%s*" .. in_a
                            elseif conn == "," then
                                pattern = "(%d+)%s*" .. ft_a .. "%s*,%s*(%d+)%s*" .. in_a
                            else
                                pattern = "(%d+)%s*" .. ft_a .. "%s+" .. conn .. "%s+(%d+)%s*" .. in_a
                            end
                            while true do
                                local s, e, f, i = text_lower:find(pattern, init)
                                if not s then break end
                                if not is_word_char_at(text_lower, e + 1) then
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
                                end
                                init = e + 1
                            end
                        end
                    end
                end
            end
        end
    end

    -- Compound weight units (e.g. 10 st 4 lb, 10 стоунов 4 фунта)
    if enabled_categories.weight and (direction == "to_metric" or direction == "auto") then
        local st_aliases = { "st", "stone", "stones", "стоунов", "стоуна", "стоун", "стоуны", "стоунів" }
        local lb_aliases = { "lb", "lbs", "pound", "pounds", "фунтов", "фунта", "фунт", "фунты", "фунтів", "фунті", "pfund", "livres", "livre", "libras", "libra", "libbre", "libbra" }
        
        local present_st = {}
        for _, st_a in ipairs(st_aliases) do
            if text_lower:find(st_a, 1, true) then
                table.insert(present_st, st_a)
            end
        end
        
        local present_lb = {}
        for _, lb_a in ipairs(lb_aliases) do
            if text_lower:find(lb_a, 1, true) then
                table.insert(present_lb, lb_a)
            end
        end

        if #present_st > 0 and #present_lb > 0 then
            local weight_connectors = { "", "and", "и", "und", "et", "y", "e", "," }
            for _, st_a in ipairs(present_st) do
                for _, lb_a in ipairs(present_lb) do
                    for _, conn in ipairs(weight_connectors) do
                        if conn == "" or conn == "," or text_lower:find(conn, 1, true) then
                            local init = 1
                            local pattern
                            if conn == "" then
                                pattern = "(%d+)%s*" .. st_a .. "%s*(%d+)%s*" .. lb_a
                            elseif conn == "," then
                                pattern = "(%d+)%s*" .. st_a .. "%s*,%s*(%d+)%s*" .. lb_a
                            else
                                pattern = "(%d+)%s*" .. st_a .. "%s+" .. conn .. "%s+(%d+)%s*" .. lb_a
                            end
                            while true do
                                local s, e, st, lb = text_lower:find(pattern, init)
                                if not s then break end
                                if not is_word_char_at(text_lower, e + 1) then
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
                                end
                                init = e + 1
                            end
                        end
                    end
                end
            end
        end
    end

    -- Pre-calculate present connectors in text_lower for fast range matching
    local active_connectors = {}
    local all_connectors = { "to", "or", "and", "-", "–", "—", "до", "или", "и", "або", "bis", "oder", "und", "à", "ou", "et", "a", "o", "y", "e" }
    for _, conn in ipairs(all_connectors) do
        if text_lower:find(conn, 1, true) then
            table.insert(active_connectors, conn)
        end
    end

    -- Pre-calculate if text contains vague quantifiers
    local has_vague = false
    for _, q in ipairs(VAGUE_ORDER) do
        if text_lower:find(q, 1, true) then
            has_vague = true
            break
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
                for _, raw_alias in ipairs(u.aliases) do
                    local alias = utf8Lower(raw_alias)
                    local is_en = (current_lang:lower() == "en")
                    if not (is_en and NON_ENGLISH_ASCII[alias]) then
                        -- FAST SUBSTRING FILTER: Only execute patterns if alias is present in text_lower
                        if text_lower:find(alias, 1, true) then
                            local escaped_alias = alias:gsub("[%-%+%.%?%*%^%$%(%)%[%]%%]", "%%%1")
                            
                            -- A: Digit pattern: matches numbers like "12.5", "12", "12,5", "50км", "36,6 °С", "1 000 km"
                            local pattern = "([%d][0-9%s%.,\194\160\226\128\175]*)%-?%s*(" .. escaped_alias .. ")"
                            local init = 1
                            while true do
                                local s, e, num_str, unit_match = text_lower:find(pattern, init)
                                if not s then break end
                                
                                local before_char = s > 1 and text_lower:sub(s - 1, s - 1) or ""
                                local ok_before = not before_char:match("[%d]")
                                local ok_after = not is_word_char_at(text_lower, e + 1)
                                
                                if ok_before and ok_after then
                                    local val = parseNumberText(num_str)
                                    if val then
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
                                        init = e + 1
                                    else
                                        init = s + 1
                                    end
                                else
                                    init = s + 1
                                end
                            end
                            
                            -- Range patterns (only run on connectors actually present in text_lower)
                            if #active_connectors > 0 then
                                local is_tens = { twenty=true, thirty=true, forty=true, fifty=true, sixty=true, seventy=true, eighty=true, ninety=true }
                                local is_units = { one=true, two=true, three=true, four=true, five=true, six=true, seven=true, eight=true, nine=true }
                                local function process_range_pattern(pat, is_word)
                                    local r_init = 1
                                    while true do
                                        local s, e, r1, r2 = text_lower:find(pat, r_init)
                                        if not s then break end
                                        local before_char = s > 1 and text_lower:sub(s - 1, s - 1) or ""
                                        local ok_boundary = true
                                        if is_word and before_char:match("[%a\194-\244]") then
                                            ok_boundary = false
                                        elseif not is_word and before_char:match("[%d%.%,]") then
                                            ok_boundary = false
                                        end
                                        if ok_boundary and not is_word_char_at(text_lower, e + 1) then
                                            local is_range = true
                                            if is_word and is_tens[r1] and is_units[r2] and not text_lower:sub(s, e):find("%s+to%s") and not text_lower:sub(s, e):find("%s+or%s") and not text_lower:sub(s, e):find("%s+and%s") then
                                                is_range = false
                                            end
                                            if is_range then
                                                local val1 = parseNumberText(r1)
                                                local val2 = parseNumberText(r2)
                                                if val1 and val2 then
                                                    local conv_raw1 = M.convert(val1, u.category, u.name, u.std_target)
                                                    local conv_val1, conv_unit1 = applySmartScaling(conv_raw1, u.category, u.std_target)
                                                    local conv_raw2 = M.convert(val2, u.category, u.name, u.std_target)
                                                    local conv_val2, conv_unit2 = applySmartScaling(conv_raw2, u.category, u.std_target)
                                                    if conv_unit1 == "c" then conv_unit1 = "°C"
                                                    elseif conv_unit1 == "f" then conv_unit1 = "°F" end
                                                    if conv_unit2 == "c" then conv_unit2 = "°C"
                                                    elseif conv_unit2 == "f" then conv_unit2 = "°F" end
                                                    local conv_str
                                                    if conv_unit1 == conv_unit2 then
                                                        conv_str = M.formatNumber(conv_val1, current_lang) .. "–" .. M.formatNumber(conv_val2, current_lang) .. " " .. M.pluralizeUnit(conv_val2, conv_unit2)
                                                    else
                                                        conv_str = M.formatNumber(conv_val1, current_lang) .. " " .. M.pluralizeUnit(conv_val1, conv_unit1) .. "–" .. M.formatNumber(conv_val2, current_lang) .. " " .. M.pluralizeUnit(conv_val2, conv_unit2)
                                                    end
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
                                
                                for _, conn in ipairs(active_connectors) do
                                    local d_pat
                                    if conn == "-" then
                                        d_pat = "([%d%.%,]+)%s*-%s*([%d%.%,]+)%s*(" .. escaped_alias .. ")"
                                    elseif conn == "–" or conn == "—" then
                                        d_pat = "([%d%.%,]+)%s*" .. conn .. "%s*([%d%.%,]+)%s*(" .. escaped_alias .. ")"
                                    else
                                        d_pat = "([%d%.%,]+)%s+" .. conn .. "%s+([%d%.%,]+)%s*(" .. escaped_alias .. ")"
                                    end
                                    process_range_pattern(d_pat, false)
                                end

                                if not (alias == "in" or alias == "st" or alias == "m" or alias == "l" or alias == "g") then
                                    for _, conn in ipairs(active_connectors) do
                                        local w_pat = "([%a\194-\244%d%-]+)%s+" .. conn .. "%s+([%a\194-\244%d%-]+)%s*(" .. escaped_alias .. ")"
                                        process_range_pattern(w_pat, true)
                                    end
                                end
                            end

                            -- B: Written numbers: e.g. "three miles", "шесть футов", "три мили"
                            if not (alias == "in" or alias == "st" or alias == "m" or alias == "l" or alias == "g") then
                                local written_pattern = "([^%d%.,:;!?'\"()/\r\n\t]+)%s+(" .. escaped_alias .. ")"
                                init = 1
                                while true do
                                    local s, e, word_str = text_lower:find(written_pattern, init)
                                    if not s then break end
                                    
                                    if not is_word_char_at(text_lower, e + 1) then
                                        local phrase_words = {}
                                        for w in word_str:gmatch("[%S]+") do
                                            table.insert(phrase_words, w)
                                        end
                                        
                                        local valid_words = {}
                                        local i_w = #phrase_words
                                        while i_w >= 1 do
                                            local w = phrase_words[i_w]
                                            local clean_w = utf8Lower(w):gsub("[%-,]$", "")
                                            if clean_w == "and" or clean_w == "a" or clean_w == "an" or clean_w == "и" or clean_w == "und" or clean_w == "et" or clean_w == "y" or parseNumberText(clean_w) then
                                                table.insert(valid_words, 1, clean_w)
                                                i_w = i_w - 1
                                            else
                                                break
                                            end
                                        end

                                        while #valid_words > 0 and (valid_words[1] == "and" or valid_words[1] == "и" or valid_words[1] == "und" or valid_words[1] == "et" or valid_words[1] == "y") do
                                            table.remove(valid_words, 1)
                                        end

                                        if #valid_words > 0 then
                                            local phrase = table.concat(valid_words, " ")
                                            local val = parseNumberText(phrase)
                                            if val then
                                                local phrase_start_idx = find_phrase_start(word_str, phrase)
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

                            -- C: Vague quantifiers (e.g. "a few hundred yards", "несколько сотен ярдов")
                            if has_vague and not (alias == "in" or alias == "st" or alias == "m" or alias == "l" or alias == "g") then
                                for mult_word, mult_val in pairs(VAGUE_MULTIPLIERS) do
                                    if text_lower:find(mult_word, 1, true) then
                                        local vague_pattern = "([^%d%.,:;!?'\"()/\r\n\t]+)%s+" .. mult_word .. "%s*(" .. escaped_alias .. ")"
                                        init = 1
                                        while true do
                                            local s, e, prefix = text_lower:find(vague_pattern, init)
                                            if not s then break end
                                            
                                            if not is_word_char_at(text_lower, e + 1) then
                                                local clean_pref = prefix:gsub("^%s+", ""):gsub("%s+$", "")
                                                for _, q in ipairs(VAGUE_ORDER) do
                                                    if clean_pref == q or clean_pref:sub(-#q) == q then
                                                        local band = VAGUE_BANDS[q]
                                                        if band and mult_val then
                                                            local val1 = band[1] * mult_val
                                                            local val2 = band[2] * mult_val
                                                            local conv_raw1 = M.convert(val1, u.category, u.name, u.std_target)
                                                            local conv_val1, conv_unit1 = applySmartScaling(conv_raw1, u.category, u.std_target)
                                                            local conv_raw2 = M.convert(val2, u.category, u.name, u.std_target)
                                                            local conv_val2, conv_unit2 = applySmartScaling(conv_raw2, u.category, u.std_target)
                                                            
                                                            if conv_unit1 == "c" then conv_unit1 = "°C"
                                                            elseif conv_unit1 == "f" then conv_unit1 = "°F" end
                                                            if conv_unit2 == "c" then conv_unit2 = "°C"
                                                            elseif conv_unit2 == "f" then conv_unit2 = "°F" end
                                                            
                                                            local conv_str
                                                            if val1 == val2 then
                                                                conv_str = "≈" .. M.formatNumber(conv_val1, current_lang) .. " " .. M.pluralizeUnit(conv_val1, conv_unit1)
                                                            elseif conv_unit1 == conv_unit2 then
                                                                conv_str = "≈" .. M.formatNumber(conv_val1, current_lang) .. "–" .. M.formatNumber(conv_val2, current_lang) .. " " .. M.pluralizeUnit(conv_val2, conv_unit2)
                                                            else
                                                                conv_str = "≈" .. M.formatNumber(conv_val1, current_lang) .. " " .. M.pluralizeUnit(conv_val1, conv_unit1) .. "–" .. M.formatNumber(conv_val2, current_lang) .. " " .. M.pluralizeUnit(conv_val2, conv_unit2)
                                                            end
                                                            
                                                            local phrase_start_idx = find_phrase_start(prefix, q)
                                                            local match_start = s
                                                            if phrase_start_idx then
                                                                match_start = s + phrase_start_idx - 1
                                                            end
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
        end
    end

    -- Deduplicate matches (longest matches prioritized)
    local final_results = {}
    local seen_starts = {}
    
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
    
    table.sort(final_results, function(a, b)
        return a.start_pos < b.start_pos
    end)

    return final_results
end

function M.getScanAliases(direction, enabled_categories, lang)
    if not direction or direction == "auto" then
        direction = M.getDefaultDirection(lang)
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
        -- Always keep universal degree symbols and superscripts
        if alias:find("°") or alias:find("º") or alias:find("²") or alias:find("³") then
            return true
        end
        -- Always keep universal metric/imperial ASCII abbreviations
        if alias == "km" or alias == "m" or alias == "cm" or alias == "mm" or alias == "dm" or
           alias == "kg" or alias == "g" or alias == "l" or alias == "ml" or alias == "ft" or
           alias == "yd" or alias == "mi" or alias == "lb" or alias == "lbs" or alias == "oz" or
           alias == "mph" or alias == "km/h" or alias == "kmh" or alias == "kph" or
           alias == "m2" or alias == "km2" or alias == "ft2" or alias == "mi2" or alias == "in2" or
           alias == "m3" or alias == "ft3" or alias == "in3" or alias == "cm3" or alias == "ha" then
            return true
        end

        local l_lower = l:lower():gsub("%-.*$", "")
        -- Script matches:
        if l_lower == "ru" or l_lower == "uk" or l_lower == "sr" or l_lower == "bg" or l_lower == "be" then
            if alias:match("[\208\209\210]") then return true end
        elseif l_lower == "ar" or l_lower == "fa" or l_lower == "ur" then
            if alias:match("[\216-\219]") then return true end
        elseif l_lower == "zh" or l_lower:find("^zh") then
            if alias:match("[\228-\233]") then return true end
        elseif l_lower == "ja" then
            if alias:match("[\227-\233]") then return true end
        end

        -- Latin-script languages:
        if l_lower == "en" then
            if alias:match("^[%z\1-\127]+$") and not NON_ENGLISH_ASCII[alias] then
                return true
            end
        else
            -- For other Latin-script languages, keep ASCII words and Latin extended characters
            if not (alias:match("[\208-\233]")) then
                return true
            end
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
                for _, raw_alias in ipairs(u.aliases) do
                    local alias_lower = utf8Lower(raw_alias)
                    if not EXCLUDED[alias_lower] and #alias_lower >= 1 and not seen[alias_lower] then
                        if should_keep_alias(alias_lower, lang) then
                            seen[alias_lower] = true
                            table.insert(aliases, alias_lower)
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
        is_one = (math.abs(val - 1) < 1e-5)
    else
        local num = tonumber(tostring(val):gsub(",", "."))
        is_one = num and (math.abs(num - 1) < 1e-5)
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
M.EXCLUDED = {
    ["in"] = true,
    ["st"] = true,
}

return M
