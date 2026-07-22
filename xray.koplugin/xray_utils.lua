-- X-Ray Utility Functions
local Device = require("device")

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

function M:getFriendlyError(error_code, error_msg, loc)
    local title_key = "error_unknown_title"
    local desc_key = "error_unknown_desc"
    local desc_arg = error_msg or "Unknown"

    if error_code == "error_quota" then
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

return M
