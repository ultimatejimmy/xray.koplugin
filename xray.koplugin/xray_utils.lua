-- X-Ray Utility Functions
local Device = require("device")
local util = require("util")

local M = {}

function M:isLowPowerDevice()
    -- PW1 (Kindle 5), Touch (Kindle 4), and older are considered low power.
    -- Most of these report as Kindle 5 or lower in the model string.
    -- PW2/3 are significantly faster but still benefit from some optimizations.
    local get_model = Device.getModel
    local model = get_model and Device:getModel() or Device.model or ""
    if Device:isKindle() then
        -- PW1 (K5), Touch (K4), etc.
        if model:find("K5") or model:find("K4") or model:find("K3") then
            return true
        end
    end
    -- PocketBook and older Kobo devices can also be slow
    if Device:isPocketBook() or (Device:isKobo() and not Device:isKoboV2()) then
        return true
    end
    -- Android e-ink devices are also low-powered/low-memory
    if Device:isAndroid() then
        local model_lower = model:lower()
        if model_lower:find("supernote") or model_lower:find("nomad") or model_lower:find("boox") or model_lower:find("likebook") then
            return true
        end
    end
    return false
end

function M:isLowPowerForScan()
    if Device:isKindle() or Device:isKobo() or Device:isPocketBook() then
        return true
    end
    -- Android e-ink devices are also low-powered/low-memory
    if Device:isAndroid() then
        local get_model = Device.getModel
        local model = get_model and Device:getModel() or Device.model or ""
        local model_lower = model:lower()
        if model_lower:find("supernote") or model_lower:find("nomad") or model_lower:find("boox") or model_lower:find("likebook") then
            return true
        end
    end
    return false
end

function M:isTouchDevice()
    local ok, Dev = pcall(require, "device")
    if ok and Dev then
        if type(Dev.isTouchDevice) == "function" then
            local ok2, res = pcall(Dev.isTouchDevice, Dev)
            if ok2 and res ~= nil then return res == true end
        end
        if Dev.isTouchDevice ~= nil then
            return Dev.isTouchDevice == true
        end
        if type(Dev.hasTouchScreen) == "function" then
            local ok2, res = pcall(Dev.hasTouchScreen, Dev)
            if ok2 and res ~= nil then return res == true end
        end
    end
    return true
end

function M:getFriendlyError(error_code, error_msg, loc)
    local title_key = "error_unknown_title"
    local desc_key = "error_unknown_desc"
    local desc_arg = error_msg or "Unknown"

    if error_code == "error_busy" then
        title_key = "error_busy_title"
        desc_key = "error_busy_desc"
        desc_arg = nil
    elseif error_code == "error_quota" then
        title_key = "error_quota_title"
        desc_key = "error_quota_desc"
        desc_arg = nil
    elseif error_code == "error_timeout" then
        title_key = "error_timeout_title"
        desc_key = "error_timeout_desc"
        desc_arg = nil
    elseif error_code == "error_parse" then
        title_key = "error_parse_title"
        desc_key = "error_parse_desc"
        desc_arg = nil
    elseif error_code == "error_api" then
        local msg = tostring(error_msg or ""):lower()
        if msg:find("401") or msg:find("unauthorized") or msg:find("invalid api key") then
            title_key = "error_api_key_title"
            desc_key = "error_api_key_desc"
            desc_arg = nil
        elseif msg:find("403") or msg:find("forbidden") then
            title_key = "error_model_access_title"
            desc_key = "error_model_access_desc"
            desc_arg = nil
        elseif msg:find("404") or msg:find("not found") then
            title_key = "error_model_not_found_title"
            desc_key = "error_model_not_found_desc"
            desc_arg = nil
        elseif msg:find("429") or msg:find("quota") or msg:find("rate limit") then
            title_key = "error_quota_title"
            desc_key = "error_quota_desc"
            desc_arg = nil
        elseif msg:find("500") or msg:find("503") or msg:find("504") or msg:find("unavailable") or msg:find("overloaded") then
            title_key = "error_service_down_title"
            desc_key = "error_service_down_desc"
            desc_arg = nil
        end
    end

    return loc:t(title_key), loc:t(desc_key, desc_arg)
end

-- Fast UTF-8 lowercasing in pure Lua covering ASCII, Cyrillic (ru, uk, sr, bg, mk, be),
-- Latin-1 Supplement & Extended (de, fr, es, it, pt, pl, tr, hu, nl, etc.), and Greek.
function M:utf8Lower(str)
    if not str then return "" end
    local res = str:lower()
    
    -- Cyrillic UTF-8:
    -- А-П: \xD0\x90-\xD0\x9F -> \xD0\xB0-\xD0\xBF
    -- Р-Я: \xD0\xA0-\xD0\xAF -> \xD1\x80-\xD1\x8F
    res = res:gsub("\208([\144-\159])", function(b)
        return "\208" .. string.char(string.byte(b) + 32)
    end)
    res = res:gsub("\208([\160-\175])", function(b)
        return "\209" .. string.char(string.byte(b) - 32)
    end)
    res = res:gsub("\208\129", "\209\145") -- Ё -> ё
    res = res:gsub("\208\130", "\209\146") -- Ђ -> ђ (sr)
    res = res:gsub("\208\131", "\209\147") -- Ѓ -> ѓ (mk)
    res = res:gsub("\208\132", "\209\148") -- Є -> є (uk)
    res = res:gsub("\208\133", "\209\149") -- Ѕ -> ѕ (mk)
    res = res:gsub("\208\134", "\209\150") -- І -> і (uk/be)
    res = res:gsub("\208\135", "\209\151") -- Ї -> ї (uk)
    res = res:gsub("\208\136", "\209\152") -- Ј -> ј (sr/mk)
    res = res:gsub("\208\137", "\209\153") -- Љ -> љ (sr/mk)
    res = res:gsub("\208\138", "\209\154") -- Њ -> њ (sr/mk)
    res = res:gsub("\208\139", "\209\155") -- Ћ -> ћ (sr)
    res = res:gsub("\208\140", "\209\156") -- Ќ -> ќ (mk)
    res = res:gsub("\208\142", "\209\158") -- Ў -> ў (be)
    res = res:gsub("\208\143", "\209\159") -- Џ -> џ (sr/mk)
    res = res:gsub("\210\144", "\210\145") -- Ґ -> ґ (uk)

    -- Latin-1 Supplement accented characters (À-Ö, Ø-Þ -> à-ö, ø-þ)
    -- \xC3\x80-\x96 -> \xC3\xA0-\xB6
    -- \xC3\x98-\x9E -> \xC3\xB8-\xBE
    res = res:gsub("\195([\128-\150])", function(b)
        return "\195" .. string.char(string.byte(b) + 32)
    end)
    res = res:gsub("\195([\152-\158])", function(b)
        return "\195" .. string.char(string.byte(b) + 32)
    end)
    
    -- Latin Extended:
    res = res:gsub("\196\176", "i")          -- İ -> i (Turkish dotted capital I)
    res = res:gsub("\197\129", "\197\130")   -- Ł -> ł (Polish)
    res = res:gsub("\196\132", "\196\133")   -- Ą -> ą (Polish)
    res = res:gsub("\196\134", "\196\135")   -- Ć -> ć (Polish)
    res = res:gsub("\196\152", "\196\153")   -- Ę -> ę (Polish)
    res = res:gsub("\197\131", "\197\132")   -- Ń -> ń (Polish)
    res = res:gsub("\197\154", "\197\155")   -- Ś -> ś (Polish)
    res = res:gsub("\197\185", "\197\186")   -- Ź -> ź (Polish)
    res = res:gsub("\197\187", "\197\188")   -- Ż -> ż (Polish)
    res = res:gsub("\197\144", "\197\145")   -- Ő -> ő (Hungarian)
    res = res:gsub("\197\176", "\197\177")   -- Ű -> ű (Hungarian)
    res = res:gsub("\196\140", "\196\141")   -- Č -> č (Serbian/Czech)
    res = res:gsub("\197\160", "\197\161")   -- Š -> š (Serbian/Czech)
    res = res:gsub("\197\189", "\197\190")   -- Ž -> ž (Serbian/Czech)
    res = res:gsub("\196\144", "\196\145")   -- Đ -> đ (Serbian)
    res = res:gsub("\196\142", "\196\143")   -- Ď -> ď (Czech/Slovak)
    res = res:gsub("\197\164", "\197\165")   -- Ť -> ť (Czech/Slovak)
    res = res:gsub("\197\135", "\197\136")   -- Ň -> ň (Czech/Slovak)
    res = res:gsub("\197\152", "\197\153")   -- Ř -> ř (Czech)
    res = res:gsub("\197\174", "\197\175")   -- Ů -> ů (Czech)
    res = res:gsub("\196\130", "\196\131")   -- Ă -> ă (Romanian)
    res = res:gsub("\197\158", "\197\159")   -- Ş -> ş (Romanian/Turkish)
    res = res:gsub("\197\162", "\197\163")   -- Ţ -> ţ (Romanian)
    res = res:gsub("\200\152", "\200\153")   -- Ș -> ș (Romanian)
    res = res:gsub("\200\154", "\200\155")   -- Ț -> ț (Romanian)
    
    -- Greek:
    -- Α-Ο: \xCE\x91-\xCE\x9F -> \xCE\xB1-\xCE\xBF
    -- Π-Ω: \xCE\xA0-\xCE\xA9 -> \xCF\x80-\xCF\x89
    res = res:gsub("\206([\145-\159])", function(b)
        return "\206" .. string.char(string.byte(b) + 32)
    end)
    res = res:gsub("\206([\160-\169])", function(b)
        return "\207" .. string.char(string.byte(b) - 32)
    end)
    res = res:gsub("\206\134", "\206\172") -- Ά -> ά
    res = res:gsub("\206\136", "\206\173") -- Έ -> έ
    res = res:gsub("\206\137", "\206\174") -- Ή -> ή
    res = res:gsub("\206\138", "\206\175") -- Ί -> ί
    res = res:gsub("\206\140", "\207\140") -- Ό -> ό
    res = res:gsub("\206\142", "\207\141") -- Ύ -> ύ
    res = res:gsub("\206\143", "\207\142") -- Ώ -> ώ
    
    return res
end

-- Safely trims leading and trailing punctuation, quotes (ASCII and Unicode),
-- brackets, dashes, and whitespace without stripping multibyte word characters.
function M:trimPunctuation(text)
    if type(text) ~= "string" or text == "" then return "" end
    local s = text
    
    -- Normalize Unicode whitespace, non-breaking spaces, and BOM
    s = s:gsub("\194\160", " "):gsub("\226\128\175", " "):gsub("\226\128\139", ""):gsub("\239\187\191", "")
    
    local changed = true
    while changed do
        local prev = s
        -- Strip ASCII whitespace and ASCII punctuation from start and end
        s = s:gsub("^[%s%p]+", ""):gsub("[%s%p]+$", "")
        
        -- Strip common Unicode punctuation / quotes / dashes from start
        s = s:gsub("^\194\171", "") -- «
        s = s:gsub("^\194\187", "") -- »
        s = s:gsub("^\194\191", "") -- ¿
        s = s:gsub("^\194\161", "") -- ¡
        s = s:gsub("^\194\183", "") -- ·
        s = s:gsub("^\226\128[\144-\191]", "") -- General Punctuation U+2000-U+206F (quotes “ ” ‘ ’ „ ‚ dashes — – … etc.)
        s = s:gsub("^\226\136\146", "") -- − (minus)
        s = s:gsub("^\227\128[\128-\191]", "") -- CJK symbols and punctuation (、 。 「 」 『 』 【 】 《 》 etc.)
        s = s:gsub("^\239\188[\128-\191]", "") -- Fullwidth ASCII variants (！（），： etc.)
        
        -- Strip common Unicode punctuation / quotes / dashes from end
        s = s:gsub("\194\171$", "") -- «
        s = s:gsub("\194\187$", "") -- »
        s = s:gsub("\194\191$", "") -- ¿
        s = s:gsub("\194\161$", "") -- ¡
        s = s:gsub("\194\183$", "") -- ·
        s = s:gsub("\226\128[\144-\191]$", "") -- General Punctuation
        s = s:gsub("\226\136\146$", "") -- − (minus)
        s = s:gsub("\227\128[\128-\191]$", "") -- CJK symbols and punctuation
        s = s:gsub("\239\188[\128-\191]$", "") -- Fullwidth ASCII variants
        
        changed = (s ~= prev)
    end
    return s
end

-- Returns true if the text contains CJK characters (U+3000–U+9FFF, etc.)
function M:textHasCJK(text)
    if type(text) ~= "string" then return false end
    return text:find("[\227-\234][\128-\191][\128-\191]") ~= nil
end

-- Truncates a string to limit_en characters (scaled down to limit_en/3 if CJK)
-- only if the total length exceeds threshold_en (scaled down to threshold_en/3 if CJK).
-- Returns: truncated_text, is_truncated
function M:getTruncatedText(text, limit_en, threshold_en)
    if type(text) ~= "string" or text == "" then
        return "", false
    end
    local is_cjk = self:textHasCJK(text)
    
    local limit = is_cjk and math.floor(limit_en / 2) or limit_en
    local threshold = is_cjk and math.floor((threshold_en or limit_en) / 2) or (threshold_en or limit_en)
    
    local chars = util.splitToChars(text)
    if #chars > threshold then
        return table.concat(chars, "", 1, limit), true
    else
        return text, false
    end
end

-- Recursively flattens KOReader's nested TOC tree structure into a flat array
function M:flattenTOC(nodes, flat_list)
    flat_list = flat_list or {}
    if not nodes then return flat_list end
    
    for _, node in ipairs(nodes) do
        table.insert(flat_list, node)
        if type(node) == "table" then
            if #node > 0 then
                M:flattenTOC(node, flat_list)
            elseif node.sub_item_table then
                M:flattenTOC(node.sub_item_table, flat_list)
            elseif node.children then
                M:flattenTOC(node.children, flat_list)
            end
        end
    end
    return flat_list
end

-- Detect AI provider from key format (supports modern AQ.*, AIza*, sk-ant-*, sk-or-*, sk-proj-*, sk-*)
function M:detectProviderFromKey(raw_key)
    if type(raw_key) ~= "string" then return nil, nil end
    local key = raw_key:match("^%s*(.-)%s*$")
    if not key or #key < 8 then return nil, nil end
    -- Strip optional surrounding quotes
    key = key:match('^["\']?(.-)["\']?$')
    if key:match("^AQ%.") or key:match("^AIza") or key:match("^gm%-") then
        return "gemini", key
    elseif key:match("^sk%-ant") then
        return "claude", key
    elseif key:match("^sk%-or") then
        return "custom1", key
    elseif key:match("^sk%-proj") or key:match("^sk%-[%w%-_]+") then
        return "chatgpt", key
    end
    return nil, key
end

-- Get current clipboard text and detect if it looks like an API key
function M:getClipboardKey()
    if not Device.hasClipboard or not Device:hasClipboard() then return nil, nil end
    local ok, text = pcall(function() return Device:getClipboardText() end)
    if not ok or type(text) ~= "string" or #text == 0 then return nil, nil end
    local provider, key = self:detectProviderFromKey(text)
    return provider, key or text:match("^%s*(.-)%s*$")
end

-- Get local network IP address of the e-reader
function M:getLocalIP()
    local sock_ip = nil

    -- 1. Try UDP socket trick (native Linux, Android, Kindle, Kobo, PocketBook)
    local ok_sock, socket = pcall(require, "socket")
    if ok_sock and socket and socket.udp then
        local s = socket.udp()
        if s then
            s:settimeout(0.5)
            pcall(function() s:setpeername("8.8.8.8", 80) end)
            local ip = s:getsockname()
            s:close()
            if ip and ip ~= "0.0.0.0" and ip ~= "127.0.0.1" then
                if not ip:match("^172%.") then
                    return ip
                end
                sock_ip = ip
            end
        end
    end

    -- 2. Try KOReader NetworkMgr
    local ok_net, NetworkMgr = pcall(require, "ui/network/manager")
    if ok_net and NetworkMgr and NetworkMgr.getIP then
        local ok, ip = pcall(function() return NetworkMgr:getIP() end)
        if ok and ip and ip ~= "" and ip ~= "127.0.0.1" then
            if not ip:match("^172%.") then
                return ip
            end
            if not sock_ip then sock_ip = ip end
        end
    end

    -- 3. If running inside WSL / VM (detected virtual 172.x IP), check host Windows Wi-Fi IP
    if sock_ip and sock_ip:match("^172%.") then
        local f = io.popen("/mnt/c/Windows/System32/ipconfig.exe 2>/dev/null")
        if f then
            local content = f:read("*a")
            f:close()
            if content then
                for ip in content:gmatch("IPv4 Address[%. ]*:%s*([%d%.]+)") do
                    if ip and not ip:match("^127%.") and not ip:match("^172%.") and not ip:match("^169%.254") then
                        return ip
                    end
                end
            end
        end
    end

    return sock_ip or "127.0.0.1"
end

return M


