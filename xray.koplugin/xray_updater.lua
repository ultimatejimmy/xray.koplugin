-- updater.lua — X-Ray Plugin OTA Updater
-- Adapted from Simple UI OTA Updater
-- Checks GitHub Releases for a newer version, informs the user,
-- and prompts to download and install.

local UIManager   = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local logger      = require("logger")

-- ---------------------------------------------------------------------------
-- Configuration
-- ---------------------------------------------------------------------------
local GITHUB_OWNER = "ultimatejimmy"
local GITHUB_REPO  = "koreader-xray-plugin"
local ASSET_NAME   = "xray.koplugin.zip"

-- Cache validity time in seconds. 0 = disable cache.
local CACHE_TTL    = 3600  -- 1 hour

-- ---------------------------------------------------------------------------
-- Internals
-- ---------------------------------------------------------------------------

local M = {}

-- Store a reference to the localization object
M.loc = nil

-- Plugin directory (resolved from this file's path)
local _plugin_dir = (debug.getinfo(1, "S").source or ""):match("^@(.+)/[^/]+$")
    or "/mnt/us/extensions/xray.koplugin"

local function _apiUrl(use_beta)
    if use_beta then
        return string.format(
            "https://api.github.com/repos/%s/%s/releases",
            GITHUB_OWNER, GITHUB_REPO
        )
    end
    return string.format(
        "https://api.github.com/repos/%s/%s/releases/latest",
        GITHUB_OWNER, GITHUB_REPO
    )
end

-- Fallback strings for keys that might not yet exist in non-English .po files
local FALLBACKS = {
    updater_btn_view_notes = "View full release notes",
    updater_btn_back = "Back",
    updater_release_notes_title = "X-Ray %s Release Notes",
}

-- Helper to safely call localizer
local function t(key, ...)
    if M.loc and M.loc.t then
        local val = M.loc:t(key, ...)
        if val and val ~= "" and val ~= key then
            return val
        end
    end
    local str = FALLBACKS[key] or key
    if select("#", ...) > 0 then
        local ok, formatted = pcall(string.format, str, ...)
        if ok then return formatted end
    end
    return str
end

local function _cacheFile(use_beta)
    local suffix = use_beta and "_beta" or ""
    local ok, DS = pcall(require, "datastorage")
    if ok and DS then
        return DS:getSettingsDir() .. "/xray_update_cache" .. suffix .. ".json"
    end
    return "/tmp/xray_update_cache" .. suffix .. ".json"
end

-- ---------------------------------------------------------------------------
-- Cache
-- ---------------------------------------------------------------------------

local function _loadCache(use_beta)
    if CACHE_TTL <= 0 then return nil end
    local path = _cacheFile(use_beta)
    local fh = io.open(path, "r")
    if not fh then return nil end
    local raw = fh:read("*a")
    fh:close()
    local ok_j, json = pcall(require, "json")
    if not ok_j then return nil end
    local ok_d, data = pcall(json.decode, raw)
    if not ok_d or type(data) ~= "table" then return nil end
    if (os.time() - (data.timestamp or 0)) > CACHE_TTL then return nil end
    return data.payload
end

local function _saveCache(payload, use_beta)
    if CACHE_TTL <= 0 then return end
    local ok_j, json = pcall(require, "json")
    if not ok_j then return end
    local ok_e, encoded = pcall(json.encode, { timestamp = os.time(), payload = payload })
    if not ok_e then return end
    local fh = io.open(_cacheFile(use_beta), "w")
    if fh then
        fh:write(encoded)
        fh:close()
    end
end

local function _clearCache(use_beta)
    pcall(os.remove, _cacheFile(use_beta))
end

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function _currentVersion()
    local meta_path = _plugin_dir .. "/_meta.lua"
    local ok, meta = pcall(dofile, meta_path)
    if ok and type(meta) == "table" and meta.version then
        return meta.version
    end
    return "0.0.0"
end

local function _versionLessThan(a, b)
    local function isBeta(v)
        return v:lower():find("beta") ~= nil
    end

    local function parts(v)
        local t_parts = {}
        if not v then return t_parts end
        for n in v:gmatch("(%d+)") do
            t_parts[#t_parts + 1] = tonumber(n)
        end
        return t_parts
    end

    local pa, pb = parts(a), parts(b)
    for i = 1, math.max(#pa, #pb) do
        local va = pa[i] or 0
        local vb = pb[i] or 0
        if va < vb then return true end
        if va > vb then return false end
    end

    -- If numeric parts are identical, a stable release is newer than a beta release
    local betaA = isBeta(a)
    local betaB = isBeta(b)
    if betaA and not betaB then
        return true -- a is beta, b is stable -> a < b
    end

    return false
end

local function _toast(msg, timeout)
    local w = InfoMessage:new{ text = msg, timeout = timeout or 4 }
    UIManager:show(w)
    return w
end

local function _closeWidget(w)
    if w then UIManager:close(w) end
end

-- ---------------------------------------------------------------------------
-- HTTP with socketutil
-- ---------------------------------------------------------------------------

local function _httpGet(url)
    local ok_su, socketutil = pcall(require, "socketutil")
    local http   = require("socket/http")
    local ltn12  = require("ltn12")
    local socket = require("socket")

    if ok_su then
        socketutil:set_timeout(
            socketutil.LARGE_BLOCK_TIMEOUT,
            socketutil.LARGE_TOTAL_TIMEOUT
        )
    end

    local chunks = {}
    local code, headers, status = socket.skip(1, http.request({
        url      = url,
        method   = "GET",
        headers  = {
            ["User-Agent"] = "KOReader-XRay-Updater/1.0",
            ["Accept"]     = "application/vnd.github.v3+json",
        },
        sink     = ltn12.sink.table(chunks),
        redirect = true,
    }))

    if ok_su then socketutil:reset_timeout() end

    if ok_su and (
        code == socketutil.TIMEOUT_CODE or
        code == socketutil.SSL_HANDSHAKE_CODE or
        code == socketutil.SINK_TIMEOUT_CODE
    ) then
        return nil, "timeout (" .. tostring(code) .. ")"
    end

    if headers == nil then
        return nil, "network error (" .. tostring(code or status) .. ")"
    end

    if code == 200 then
        return table.concat(chunks)
    end
    return nil, string.format("HTTP %s", tostring(code))
end

local function _httpGetToFile(url, dest_path)
    local ok_su, socketutil = pcall(require, "socketutil")
    local http   = require("socket/http")
    local ltn12  = require("ltn12")
    local socket = require("socket")

    local fh, err_open = io.open(dest_path, "wb")
    if not fh then
        return nil, "Could not create file: " .. tostring(err_open)
    end

    if ok_su then
        socketutil:set_timeout(
            socketutil.FILE_BLOCK_TIMEOUT,
            socketutil.FILE_TOTAL_TIMEOUT
        )
    end

    local code, headers, status = socket.skip(1, http.request({
        url      = url,
        method   = "GET",
        headers  = { ["User-Agent"] = "KOReader-XRay-Updater/1.0" },
        sink     = ltn12.sink.file(fh),
        redirect = true,
    }))

    if ok_su then socketutil:reset_timeout() end

    if ok_su and (
        code == socketutil.TIMEOUT_CODE or
        code == socketutil.SSL_HANDSHAKE_CODE or
        code == socketutil.SINK_TIMEOUT_CODE
    ) then
        pcall(os.remove, dest_path)
        return nil, "timeout (" .. tostring(code) .. ")"
    end

    if headers == nil then
        pcall(os.remove, dest_path)
        return nil, "network error (" .. tostring(code or status) .. ")"
    end

    if code == 200 then return true end
    pcall(os.remove, dest_path)
    return nil, string.format("HTTP %s", tostring(code))
end

-- ---------------------------------------------------------------------------
-- JSON parsing
-- ---------------------------------------------------------------------------

local function _cleanReleaseNotes(raw_notes)
    if not raw_notes or raw_notes == "" then return nil end
    local notes = raw_notes
    -- Convert markdown links [text](url) -> text
    notes = notes:gsub("%[([^%]]+)%]%([^%)]+%)", "%1")
    -- Strip markdown headers, bold/italic, code blocks
    notes = notes:gsub("#+%s*", "")
    notes = notes:gsub("%*%*(.-)%*%*", "%1")
    notes = notes:gsub("%*(.-)%*", "%1")
    notes = notes:gsub("`(.-)`", "%1")
    notes = notes:gsub("\r\n", "\n"):gsub("\r", "\n")
    -- Collapse 3+ consecutive newlines into 2
    notes = notes:gsub("\n%s*\n%s*\n+", "\n\n")
    notes = notes:match("^%s*(.-)%s*$")
    if not notes or notes == "" then return nil end
    if #notes > 4000 then
        notes = notes:sub(1, 3997) .. "..."
    end
    return notes
end

local function _parseRelease(body, use_beta)
    local ok_j, json = pcall(require, "json")

    if not ok_j then
        logger.warn("xray updater: json module not available, using fallback regex")
        local function jsonStr(key)
            return body:match('"' .. key .. '"%s*:%s*"([^"]*)"')
        end
        local tag = jsonStr("tag_name")
        if not tag then return nil, "could not parse tag_name" end
        local download_url = body:match(
            '"browser_download_url"%s*:%s*"([^"]*'
            .. ASSET_NAME:gsub("%.", "%%.") .. '[^"]*)"'
        )
        local notes = body:match('"body"%s*:%s*"(.-)"[,}]')
        if notes then
            notes = notes:gsub("\\n", "\n"):gsub("\\r", ""):gsub('\\"', '"'):gsub("\\\\", "\\")
            notes = _cleanReleaseNotes(notes)
        end
        return {
            version      = tag:match("v?(.*)"),
            download_url = download_url,
            notes        = notes,
        }
    end

    local ok_d, data = pcall(json.decode, body)
    if not ok_d or type(data) ~= "table" then
        return nil, "JSON parse error: " .. tostring(data)
    end

    -- GitHub error messages usually have a 'message' field
    if data.message and not data.tag_name and not (use_beta and data[1]) then
        return nil, "GitHub API error: " .. tostring(data.message)
    end

    -- If we query /releases instead of /releases/latest, we get an array
    local release_data = data
    if use_beta then
        if type(data) == "table" and data[1] then
            release_data = data[1]
        elseif type(data) == "table" and #data == 0 then
            return nil, "No releases found in repository"
        else
            return nil, "Unexpected API response format (expected array)"
        end
    end

    local tag = release_data.tag_name
    if not tag then return nil, "tag_name missing from API response" end

    local download_url = nil
    for _, asset in ipairs(release_data.assets or {}) do
        if type(asset.name) == "string" and asset.name == ASSET_NAME then
            download_url = asset.browser_download_url
            break
        end
    end

    local notes = _cleanReleaseNotes(release_data.body)

    return {
        version      = tag:match("v?(.*)"),
        download_url = download_url,
        notes        = notes,
        html_url     = release_data.html_url,
    }
end

-- ---------------------------------------------------------------------------
-- Unzip
-- ---------------------------------------------------------------------------

local function _unzip(zip_path, dest_dir)
    local cmd = string.format("unzip -o -q %q -d %q", zip_path, dest_dir)
    local ret = os.execute(cmd)
    if ret ~= 0 and ret ~= true then
        return nil, "unzip failed (exit " .. tostring(ret) .. ")"
    end
    return true
end

-- ---------------------------------------------------------------------------
-- Download & Install
-- ---------------------------------------------------------------------------

local function _tmpZipPath()
    local ok, DS = pcall(require, "datastorage")
    if ok and DS then
        return DS:getSettingsDir() .. "/xray_update.zip"
    end
    local probe = "/tmp/.xray_probe"
    local fh = io.open(probe, "w")
    if fh then fh:close(); os.remove(probe); return "/tmp/xray_update.zip" end
    return _plugin_dir .. "/xray_update.zip"
end

local function _applyUpdate(download_url, new_version)
    local tmp_zip    = _tmpZipPath()
    local parent_dir = _plugin_dir:match("^(.+)/[^/]+$") or _plugin_dir

    local progress_msg = _toast(
        t("updater_downloading", new_version), 120
    )

    local ok_tr, Trapper = pcall(require, "ui/trapper")

    local function doDownloadAndInstall()
        local config_path = _plugin_dir .. "/xray_config.lua"
        local saved_keys = {}
        local ok, cfg = pcall(dofile, config_path)
        if ok and type(cfg) == "table" then
            saved_keys.gemini = cfg.gemini_api_key
            saved_keys.chatgpt = cfg.chatgpt_api_key
            saved_keys.deepseek = cfg.deepseek_api_key
            saved_keys.claude = cfg.claude_api_key
            saved_keys.custom1_key = cfg.custom1_api_key
            saved_keys.custom1_endpoint = cfg.custom1_endpoint
            saved_keys.custom1_model = cfg.custom1_model
            saved_keys.custom2_key = cfg.custom2_api_key
            saved_keys.custom2_endpoint = cfg.custom2_endpoint
            saved_keys.custom2_model = cfg.custom2_model
        end

        -- 2. Download the update
        local dl_ok, dl_err = _httpGetToFile(download_url, tmp_zip)
        if not dl_ok then
            return { success = false, stage = "download", err = dl_err }
        end

        -- 3. Extract (overwrites xray_config.lua with the default one)
        local uz_ok, uz_err = _unzip(tmp_zip, parent_dir)
        os.remove(tmp_zip)
        if not uz_ok then
            return { success = false, stage = "unzip", err = uz_err }
        end

        -- 4. Smart Merge: Inject keys back into the NEW config file
        if (saved_keys.gemini and saved_keys.gemini ~= "") or
           (saved_keys.chatgpt and saved_keys.chatgpt ~= "") or
           (saved_keys.deepseek and saved_keys.deepseek ~= "") or
           (saved_keys.claude and saved_keys.claude ~= "") or
           (saved_keys.custom1_key and saved_keys.custom1_key ~= "") or
           (saved_keys.custom2_key and saved_keys.custom2_key ~= "") then
            local nfh = io.open(config_path, "r")
            if nfh then
                local content = nfh:read("*a")
                nfh:close()

                -- Replace empty key placeholders with the saved user keys
                if saved_keys.gemini and saved_keys.gemini ~= "" then
                    content = content:gsub('gemini_api_key%s*=%s*""', 'gemini_api_key = "' .. saved_keys.gemini .. '"')
                end
                if saved_keys.chatgpt and saved_keys.chatgpt ~= "" then
                    content = content:gsub('chatgpt_api_key%s*=%s*""', 'chatgpt_api_key = "' .. saved_keys.chatgpt .. '"')
                end
                if saved_keys.deepseek and saved_keys.deepseek ~= "" then
                    content = content:gsub('deepseek_api_key%s*=%s*""', 'deepseek_api_key = "' .. saved_keys.deepseek .. '"')
                end
                if saved_keys.claude and saved_keys.claude ~= "" then
                    content = content:gsub('claude_api_key%s*=%s*""', 'claude_api_key = "' .. saved_keys.claude .. '"')
                end
                
                if saved_keys.custom1_key and saved_keys.custom1_key ~= "" then
                    content = content:gsub('custom1_api_key%s*=%s*""', 'custom1_api_key = "' .. saved_keys.custom1_key .. '"')
                end
                if saved_keys.custom1_endpoint and saved_keys.custom1_endpoint ~= "" then
                    content = content:gsub('custom1_endpoint%s*=%s*""', 'custom1_endpoint = "' .. saved_keys.custom1_endpoint .. '"')
                end
                if saved_keys.custom1_model and saved_keys.custom1_model ~= "" then
                    content = content:gsub('custom1_model%s*=%s*""', 'custom1_model = "' .. saved_keys.custom1_model .. '"')
                end
                
                if saved_keys.custom2_key and saved_keys.custom2_key ~= "" then
                    content = content:gsub('custom2_api_key%s*=%s*""', 'custom2_api_key = "' .. saved_keys.custom2_key .. '"')
                end
                if saved_keys.custom2_endpoint and saved_keys.custom2_endpoint ~= "" then
                    content = content:gsub('custom2_endpoint%s*=%s*""', 'custom2_endpoint = "' .. saved_keys.custom2_endpoint .. '"')
                end
                if saved_keys.custom2_model and saved_keys.custom2_model ~= "" then
                    content = content:gsub('custom2_model%s*=%s*""', 'custom2_model = "' .. saved_keys.custom2_model .. '"')
                end

                local outh = io.open(config_path, "w")
                if outh then
                    outh:write(content)
                    outh:close()
                end
            end
        end

        return { success = true }
    end

    local function handleInstallResult(result)
        _closeWidget(progress_msg)
        if not result or not result.success then
            local stage = result and result.stage or "unknown"
            local err   = result and result.err   or "unknown error"
            logger.err("xray updater: failed at", stage, "-", err)
            if stage == "download" then
                _toast(t("updater_err_download", tostring(err)))
            else
                _toast(t("updater_err_extract", tostring(err)))
            end
            return
        end
        _clearCache(true)
        _clearCache(false)
        local ButtonDialog = require("ui/widget/buttondialog")
        local success_dlg
        success_dlg = ButtonDialog:new{
            title = t("updater_success_restart", new_version),
            buttons = {{
                {
                    text = t("updater_btn_later"),
                    callback = function()
                        UIManager:close(success_dlg)
                    end,
                },
                {
                    text = t("updater_btn_restart"),
                    is_enter_default = true,
                    callback = function()
                        UIManager:close(success_dlg)
                        UIManager:restartKOReader()
                    end,
                },
            }},
        }
        UIManager:show(success_dlg)
    end

    if ok_tr and Trapper and Trapper.dismissableRunInSubprocess then
        local completed, result = Trapper:dismissableRunInSubprocess(
            doDownloadAndInstall,
            progress_msg,
            function(res) handleInstallResult(res) end
        )
        if completed and result then
            UIManager:scheduleIn(0.2, function() handleInstallResult(result) end)
        elseif completed == false then
            _closeWidget(progress_msg)
            pcall(os.remove, tmp_zip)
            _toast(t("updater_cancelled_update"))
        end
    else
        UIManager:scheduleIn(0.3, function()
            handleInstallResult(doDownloadAndInstall())
        end)
    end
end

-- ---------------------------------------------------------------------------
-- Version Check
-- ---------------------------------------------------------------------------

local function _formatInlineNotes(notes, screen_h)
    if not notes or notes == "" then
        return nil, false
    end

    -- Strip leading redundant "What's New" headers
    local cleaned = notes:gsub("^[Ww]hat'?s%s+[Nn]ew[:%s]*\n*", "")
    cleaned = cleaned:match("^%s*(.-)%s*$") or cleaned
    if cleaned == "" then
        return nil, false
    end

    local max_lines
    local max_chars
    if screen_h < 700 then
        -- Small screen or landscape orientation (e.g. 600px height)
        max_lines = 3
        max_chars = 140
    elseif screen_h < 900 then
        -- Standard screen (e.g. 800px height portrait or 758px landscape)
        max_lines = 5
        max_chars = 220
    else
        -- Large screen (e.g. 1072+ px height)
        max_lines = 7
        max_chars = 320
    end

    local raw_lines = {}
    for line in (cleaned .. "\n"):gmatch("([^\n]*)\n") do
        if #raw_lines > 0 or line:match("%S") then
            table.insert(raw_lines, line)
        end
    end
    while #raw_lines > 0 and raw_lines[#raw_lines]:match("^%s*$") do
        table.remove(raw_lines)
    end

    local result_lines = {}
    local total_chars = 0
    local is_truncated = false

    for _, line in ipairs(raw_lines) do
        if #result_lines >= max_lines then
            is_truncated = true
            break
        end
        if total_chars + #line > max_chars then
            if #result_lines == 0 then
                local sub = line:sub(1, max_chars)
                local last_space = sub:match("^.*()%s")
                if last_space and last_space > 20 then
                    sub = sub:sub(1, last_space - 1)
                end
                table.insert(result_lines, sub .. "...")
            end
            is_truncated = true
            break
        end
        table.insert(result_lines, line)
        total_chars = total_chars + #line + 1
    end

    if #raw_lines > #result_lines then
        is_truncated = true
    end

    local preview = table.concat(result_lines, "\n"):match("^%s*(.-)%s*$")
    if is_truncated and preview then
        if not preview:match("%.%.%.$") then
            preview = preview .. "\n..."
        end
    end

    return preview, is_truncated
end

local function _showFullNotesViewer(title_str, full_notes, download_url, latest_version, parent_dialog)
    local TextViewer = require("ui/widget/textviewer")
    local viewer
    local viewer_buttons = {{
        {
            text = t("updater_btn_back"),
            callback = function()
                UIManager:close(viewer)
            end,
        },
    }}
    if download_url then
        table.insert(viewer_buttons[1], {
            text = t("updater_btn_download"),
            is_enter_default = true,
            callback = function()
                UIManager:close(viewer)
                if parent_dialog then
                    UIManager:close(parent_dialog)
                end
                _applyUpdate(download_url, latest_version)
            end,
        })
    end
    viewer = TextViewer:new{
        title = title_str,
        text = full_notes,
        buttons_table = viewer_buttons,
    }
    UIManager:show(viewer)
end

local function _showUpdateDialog(release, current)
    local latest       = release.version
    local download_url = release.download_url
    local notes        = release.notes

    if not _versionLessThan(current, latest) then
        logger.info("xray updater: up to date (" .. current .. ")")
        _toast(t("updater_up_to_date", current))
        return
    end

    logger.info("xray updater: new version available:", latest)

    local ok_dev, Device = pcall(require, "device")
    local Screen = ok_dev and Device and Device.screen
    local screen_h = (Screen and Screen.getHeight and Screen:getHeight()) or 800

    local header = t("updater_available_header", latest, current)
    local footer = t("updater_download_prompt")

    local inline_notes, has_more_notes = _formatInlineNotes(notes, screen_h)
    local notes_block = inline_notes
        and ("\n\n" .. t("updater_whats_new") .. "\n" .. inline_notes)
        or  ""

    local notes_viewer_title = t("updater_release_notes_title", latest)

    local ButtonDialog = require("ui/widget/buttondialog")
    if not download_url then
        local no_asset_dlg
        local no_asset_buttons = {}
        if has_more_notes and notes then
            table.insert(no_asset_buttons, {
                {
                    text = t("updater_btn_view_notes"),
                    callback = function()
                        _showFullNotesViewer(notes_viewer_title, notes, nil, latest, no_asset_dlg)
                    end,
                },
            })
        end
        table.insert(no_asset_buttons, {
            {
                text = t("updater_btn_cancel"),
                callback = function()
                    UIManager:close(no_asset_dlg)
                end,
            },
            {
                text = t("updater_btn_open_browser"),
                is_enter_default = true,
                callback = function()
                    UIManager:close(no_asset_dlg)
                    if ok_dev and Device and Device.canOpenLink and Device:canOpenLink() then
                        Device:openLink(release.html_url or string.format(
                            "https://github.com/%s/%s/releases/latest",
                            GITHUB_OWNER, GITHUB_REPO
                        ))
                    end
                end,
            },
        })

        local dlg_props = {
            title = header .. notes_block .. "\n\n" .. t("updater_no_asset"),
            buttons = no_asset_buttons,
        }
        if screen_h < 700 then
            local ok_f, Font = pcall(require, "ui/font")
            if ok_f and Font then
                dlg_props.info_face = Font:getFace("x_smallinfofont")
            end
        end
        no_asset_dlg = ButtonDialog:new(dlg_props)
        UIManager:show(no_asset_dlg)
        return
    end

    local update_dlg
    local update_buttons = {}
    if has_more_notes and notes then
        table.insert(update_buttons, {
            {
                text = t("updater_btn_view_notes"),
                callback = function()
                    _showFullNotesViewer(notes_viewer_title, notes, download_url, latest, update_dlg)
                end,
            },
        })
    end
    table.insert(update_buttons, {
        {
            text = t("updater_btn_cancel"),
            callback = function()
                UIManager:close(update_dlg)
            end,
        },
        {
            text = t("updater_btn_download"),
            is_enter_default = true,
            callback = function()
                UIManager:close(update_dlg)
                _applyUpdate(download_url, latest)
            end,
        },
    })

    local dlg_props = {
        title = header .. notes_block .. footer,
        buttons = update_buttons,
    }
    if screen_h < 700 then
        local ok_f, Font = pcall(require, "ui/font")
        if ok_f and Font then
            dlg_props.info_face = Font:getFace("x_smallinfofont")
        end
    end
    update_dlg = ButtonDialog:new(dlg_props)
    UIManager:show(update_dlg)
end

local function _doFetch(use_beta)
    local cached = _loadCache(use_beta)
    if cached then
        logger.info("xray updater: using cache (" .. (use_beta and "beta" or "stable") .. ")")
        return cached
    end
    local body, err = _httpGet(_apiUrl(use_beta))
    if not body then return { error = err } end
    local release, parse_err = _parseRelease(body, use_beta)
    if not release then return { error = "parse error: " .. tostring(parse_err) } end
    _saveCache(release, use_beta)
    return release
end

function M._doCheckForUpdates(current, use_beta)
    local checking_msg = _toast(t("updater_checking"), 15)
    local ok_tr, Trapper = pcall(require, "ui/trapper")

    local function handleCheckResult(release)
        _closeWidget(checking_msg)
        if not release then
            _toast(t("updater_error_checking"))
            return
        end
        if release.error then
            logger.err("xray updater: check error:", release.error)
            _toast(t("updater_error_checking_detail", tostring(release.error)))
            return
        end
        _showUpdateDialog(release, current)
    end

    if ok_tr and Trapper and Trapper.dismissableRunInSubprocess then
        local completed, result = Trapper:dismissableRunInSubprocess(
            function() return _doFetch(use_beta) end,
            checking_msg,
            function(res) handleCheckResult(res) end
        )
        if completed and result then
            UIManager:scheduleIn(0.2, function() handleCheckResult(result) end)
        elseif completed == false then
            _closeWidget(checking_msg)
            _toast(t("updater_cancelled_check"))
        end
    else
        UIManager:scheduleIn(0.3, function()
            handleCheckResult(_doFetch(use_beta))
        end)
    end
end

-- localization param allows the caller to pass the X-Ray loc module
function M.checkForUpdates(loc, use_beta)
    M.loc = loc
    local current = _currentVersion()
    local ok_nm, NetworkMgr = pcall(require, "ui/network/manager")
    if ok_nm and NetworkMgr and NetworkMgr.runWhenOnline then
        NetworkMgr:runWhenOnline(function()
            M._doCheckForUpdates(current, use_beta)
        end)
        return
    end
    M._doCheckForUpdates(current, use_beta)
end

function M.checkSilentForUpdates(loc, use_beta)
    M.loc = loc
    local current = _currentVersion()
    local release = _doFetch(use_beta)
    
    if release and not release.error then
        if _versionLessThan(current, release.version) then
            _showUpdateDialog(release, current)
        end
    end
end

M._cleanReleaseNotes = _cleanReleaseNotes
M._formatInlineNotes = _formatInlineNotes
M._showUpdateDialog = _showUpdateDialog

return M
