-- Localization Manager for X-Ray Plugin (with .po support)

local logger = require("logger")
local json = require("json")
local ok, lfs = pcall(require, "libs/libkoreader-lfs")
if not ok or type(lfs) ~= "table" then
    ok, lfs = pcall(require, "lfs")
end
if not ok then
    logger.error("Localization: lfs module not found!")
end
local plugin_path = ((...) or ""):match("(.-)[^%.]+$") or ""
if plugin_path ~= "" then
    local path_to_dir = plugin_path:gsub("%.", "/")
    if not package.path:find(path_to_dir) then
        package.path = package.path .. ";" .. path_to_dir .. "?.lua"
    end
end


local Localization = {
    current_language = "en",
    translations = {},
    available_languages = {},
}

-- Simple .po file parser
function Localization:parsePO(filepath)
    local translations = {}
    local file = io.open(filepath, "r")
    
    if not file then
        logger.warn("Localization: Cannot open .po file:", filepath)
        return nil
    end
    
    local msgid = nil
    local msgstr = nil
    local in_msgid = false
    local in_msgstr = false
    
    for line in file:lines() do
        -- Skip comments and empty lines
        if not (line:match("^#") or line:match("^%s*$")) then
            -- Start of msgid
            if line:match('^msgid%s+"') then
                -- Save previous translation
                if msgid and msgstr then
                    translations[msgid] = msgstr
                end
                
                msgid = line:match('^msgid%s+"(.-)"')
                msgstr = nil
                in_msgid = true
                in_msgstr = false
            
            -- Start of msgstr
            elseif line:match('^msgstr%s+"') then
                msgstr = line:match('^msgstr%s+"(.-)"')
                in_msgid = false
                in_msgstr = true
            
            -- Continuation line
            elseif line:match('^"') then
                local continuation = line:match('^"(.-)"')
                if in_msgid and msgid then
                    msgid = msgid .. continuation
                elseif in_msgstr and msgstr then
                    msgstr = msgstr .. continuation
                end
            end
        end

    end
    
    -- Save last translation
    if msgid and msgstr then
        translations[msgid] = msgstr
    end
    
    file:close()
    
    -- Process escape sequences
    for key, value in pairs(translations) do
        value = value:gsub("\\n", "\n")
        value = value:gsub("\\t", "\t")
        value = value:gsub('\\"', '"')
        value = value:gsub("\\\\", "\\")
        translations[key] = value
    end
    
    return translations
end

-- Initialize localization system
function Localization:init(path)
    logger.info("Localization: Initializing...")
    
    -- Use provided path or hardcoded default
    self.path = path or "plugins/xray.koplugin"
    
    -- Robust path handling for Windows/Unix
    self.path = self.path:gsub("\\", "/")
    
    -- Discover available language files
    self:discoverLanguages()
    
    -- Load saved language preference
    self:loadLanguage()
    
    -- Load translation file
    self:loadTranslations()
    
    logger.info("Localization: Initialized with language:", self.current_language)
end

-- Discover available .po files
function Localization:discoverLanguages()
    local lang_dir = self.path .. "/languages"
    
    self.available_languages = {}
    
    if not lfs then
        logger.error("Localization: lfs not available, skipping language discovery")
        return
    end
    local attr = lfs.attributes(lang_dir)

    if not attr or attr.mode ~= "directory" then
        logger.warn("Localization: Languages directory not found:", lang_dir)
        -- Try fallback to hardcoded path if current path failed
        if self.path ~= "plugins/xray.koplugin" then
            self.path = "plugins/xray.koplugin"
            lang_dir = self.path .. "/languages"
            attr = lfs.attributes(lang_dir)
            if not attr or attr.mode ~= "directory" then
                logger.error("Localization: Languages directory NOT found even with fallback!")
                return
            end
        else
            return
        end
    end
    
    for file in lfs.dir(lang_dir) do

        if file:match("%.po$") then
            local lang_code = file:match("^(.+)%.po$")
            if lang_code then
                table.insert(self.available_languages, lang_code)
                logger.info("Localization: Found language:", lang_code)
            end
        end
    end
    
    table.sort(self.available_languages)
    logger.info("Localization: Discovered", #self.available_languages, "languages")
end

-- Load translations from .po file
function Localization:loadTranslations()
    local po_file = self.path .. "/languages/" .. self.current_language .. ".po"
    
    logger.info("Localization: Loading translations from:", po_file)
    
    local translations = self:parsePO(po_file)
    
    if translations then
        self.translations = translations
        logger.info("Localization: Loaded", self:tableSize(translations), "translations")
    else
        logger.warn("Localization: Failed to load .po file:", po_file)
        
        -- Fallback to English
        if self.current_language ~= "en" then
            logger.info("Localization: Falling back to English")
            self.current_language = "en"
            po_file = self.path .. "/languages/en.po"
            translations = self:parsePO(po_file)
            if translations then
                self.translations = translations
            else
                self.translations = {}
                logger.error("Localization: Failed to load fallback!")
            end
        else
            self.translations = {}
        end
    end
end

-- Helper: count table size
function Localization:tableSize(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

-- Get translated string with better error handling
function Localization:t(key, ...)
    local translation = self.translations[key]
    
    if not translation or translation == "" then
        logger.warn("Localization: Missing translation key:", key)
        -- Return a user-friendly fallback instead of the key
        local fallbacks = {
            msg_suggest_lang = "This book is in %s. Switch X-Ray language to match?",
            cache_saved = "[Saved]",
            cache_save_failed = "[Save failed]",
            ai_fetch_complete = "Fetched from %s\n\nBook: %s\nAuthor: %s\n\nCharacters: %d | Locations: %d | Themes: %d | Events: %d | History: %d\n\n%s\n\n%s",
            fetching_ai = "Fetching from %s...",
            updating_ai = "Updating X-Ray Data...",
            fetching_author = "Fetching author info from %s...",
            menu_update_xray = "Update X-Ray Data (Merge)",
            menu_fetch_more_chars = "Fetch More Characters",
            no_api_key = "No API key set!",
            ai_key_required = "An AI API key is required.",
            ai_error = "AI Error: ",
            no_author_data_fetch = "No author info available. Fetch from AI?",
            xray_mode_desc = "Adds an 'X-Ray' button to dictionary and selection menus for instant lookups.",
            no_data_prompt = "No X-Ray data found for this book. Would you like to fetch it from AI now?",
            menu_clear_logs = "Clear Logs",
            logs_cleared = "Logs cleared!",
            spoiler_free_option = "Spoiler-free Mode (Up to %d%% of the book)",
            spoiler_free_about = "Spoiler-free mode limits AI extraction to the pages you have already read (up to your current page), preventing spoilers from future chapters.\n\nFull Book Mode analyzes the entire book, which may contain spoilers.",
            updater_check = "Check for Updates",
            updater_checking = "Checking for updates...",
            updater_error_checking = "Error checking for updates.",
            updater_error_checking_detail = "Error checking for updates: %s",
            updater_up_to_date = "X-Ray is up to date (%s).",
            updater_available_header = "X-Ray %s is available!\nYou have %s.",
            updater_download_prompt = "\n\nDownload and install now?",
            updater_whats_new = "What's new:",
            updater_no_asset = "No automatic update file was found.\n\nOpen the releases page on GitHub?",
            updater_btn_open_browser = "Open in browser",
            updater_btn_cancel = "Cancel",
            updater_btn_download = "Download and install",
            updater_downloading = "Downloading X-Ray %s...",
            updater_err_download = "Download error: %s",
            updater_err_extract = "Extraction error: %s",
            updater_success_restart = "X-Ray %s successfully installed.\n\nRestart KOReader to apply the update?",
            updater_btn_restart = "Restart",
            updater_btn_later = "Later",
            updater_cancelled_update = "Update cancelled.",
            updater_cancelled_check = "Update check cancelled.",
            search_character = "Search Characters...",
            search_character_title = "Character Search",
            search_hint = "Enter character name",
            search_button = "Search",
            character_not_found = "No character found matching '%s'",
            multiple_matches = "Multiple matches for '%s'. Which did you mean?",
            label_name = "NAME",
            label_aliases = "ALIASES",
            label_role = "ROLE",
            label_gender = "GENDER",
            label_occupation = "OCCUPATION",
            label_description = "DESCRIPTION",
            msg_added_characters = "Added %d new characters!",
            msg_no_bio = "No biography available.",
            menu_mentions_settings = "Mentions Settings",
            mentions_enabled = "Enabled",
            mentions_disabled = "Disabled",
            mentions_scanning = "Scanning... %1 of %2 chapters",
            mentions_setting_title = "Mentions Settings",
            mentions_setting_desc = "Mentions scanning allows you to find every occurrence of a character or location in the book. This happens automatically in the background to ensure the reader stays responsive.\n\nDisabling this will hide the 'Find Mentions' button.",
            mentions_preference_desc = "Select your preference for character and location mentions:",
            auto_dupe_check_enabled = "Enabled",
            auto_dupe_check_disabled = "Disabled",
            auto_dupe_check_setting_title = "Duplicate Check",
            auto_dupe_check_preference_desc = "Select your preference for automatic AI duplicate detection:",
            auto_dupe_check_setting_desc = "When enabled, X-Ray automatically asks the AI to check for duplicate characters and locations after every data fetch. If duplicates are detected, you will be prompted to review and merge them.\n\nDisabling this will stop all background duplicate scanning. You can still merge duplicates manually via the Characters or Locations menu.\n\nNote: each check uses one AI API call. Users on free-tier or quota-limited plans may prefer to disable this.",
            mentions_title = "Mentions: %s",
            mentions_none = "No mentions found for '%s' yet.",
            mentions_refresh = "Refresh Mentions",
            mentions_at_location = "Mention: %s",
            find_mentions = "Find Mentions",
            menu_about = "About",
            menu_frequency = "Frequency",
            auto_update_ultra = "Ultra: checks every %d pages",
            auto_fetch_page_interval_prompt = "Page Interval",
            menu_reasoning_effort = "AI Reasoning Effort",
            reasoning_low = "Low",
            reasoning_medium = "Medium",
            reasoning_high = "High",
            reasoning_unset = "Unset (Default)",
            reasoning_about = "Controls 'thinking' depth for reasoning models:\n\n• Unset: No specific instruction sent; model uses its internal defaults.\n• Low: Fast, economical extraction for simple books.\n• Medium: Balanced depth for most narratives.\n• High: Detailed analysis for complex character webs.\n\nApplies to: GPT-5.x (o1/o3/gpt-5), Claude (sonnet/opus/haiku), and Gemini 2.5+.\n\nNote: DeepSeek V4 reasons inherently — this setting has no effect on it.",
            label_reasoning = "AI REASONING",
            linked_entries = "Linked Entries",
            menu_linked_entries_settings = "Linked Entries Settings",
            linked_entries_enabled = "Enabled",
            linked_entries_disabled = "Disabled",
            linked_entries_setting_desc = "Linked Entries automatically connects characters, locations, and historical figures when they are mentioned in each other's descriptions.\n\nDisabling this will hide the 'Linked Entries' button from detail dialogs.",
            quick_menu_title = "X-Ray Quick Menu",
            merge_duplicates = "⋈ Merge Duplicates...",
            merge_pick_primary = "Choose the entry to KEEP",
            merge_pick_secondary = "Choose the entry to REMOVE",
            merge_confirm = "Merge %s into %s? The secondary entry will be deleted and its aliases absorbed.",
            merge_success = "Entries merged successfully.",
            merge_failed = "Merge failed.",
            merge_back = "← Back",
            menu_display_ui_settings = "Display & UI Settings",
            menu_content_fetch_settings = "Content & Fetch Settings",
            menu_entity_ui_mode = "Entity Description Style",
            entity_ui_style_both = "Modern Popup (Both)",
            entity_ui_style_in_text = "Modern Popup (In-text only)",
            entity_ui_style_menu = "Modern Popup (Menu only)",
            entity_ui_style_classic = "Classic Dialog",
            entity_ui_style_desc = "Select when to use the new Modern Popup UI instead of the Classic Dialog for entity descriptions.",
            merging_smartly = "Merging...",
            custom_api_name = "Custom API %d (OpenAI-compatible)",
            custom_api_endpoint_title = "Custom API %d — Endpoint URL",
            custom_api_key_title = "Custom API %d — API Key",
            custom_api_model_title = "Custom API %d — Default Model",
            custom_api_endpoint_hint = "e.g., https://openrouter.ai/api/v1/chat/completions",
            custom_api_model_hint = "e.g., google/gemini-2.5-flash or openai/gpt-4o",
            custom_api_saved = "Custom API %d configuration saved.",
            custom_api_not_configured = "(not configured — tap to set up)",
            custom_api_is_reasoning = "Is Reasoning Model (e.g. DeepSeek-V4-Pro, DeepSeek-R1)",
            menu_desc_length_settings = "Description Length Settings",
            desc_len_short = "Short",
            desc_len_default = "Default",
            desc_len_detailed = "Detailed",
            desc_len_v_detailed = "Very Detailed",
            desc_len_about_chars = "CHARACTER DESCRIPTIONS\n\n• Short (~80 chars): Name, role, and a brief note.\n• Default (~200 chars): Standard analysis.\n• Detailed (~350 chars): Rich character study with traits and motivations.\n• Very Detailed (~500 chars): Deep analysis.\n\nTRADE-OFF\nLonger descriptions → fewer characters returned during initial/full fetches. Subsequent 'Fetch More' runs are unaffected.",
            desc_len_about_locs = "LOCATION DESCRIPTIONS\n\n• Short (~50 chars): Place name and one-line context.\n• Default (~100 chars): Standard description.\n• Detailed (~200 chars): Atmosphere, significance, and events.\n• Very Detailed (~300 chars): Full description.\n\nTRADE-OFF\nLonger descriptions → fewer locations returned during initial/full fetches.",
            desc_len_about_hist = "HISTORICAL FIGURE BIOGRAPHIES\n\n• Short (~50 chars): Name and primary role.\n• Default (~100 chars): Standard biography.\n• Detailed (~200 chars): Life, significance, and book context.\n• Very Detailed (~300 chars): Comprehensive biography.\n\nTRADE-OFF\nLonger biographies → fewer historical figures returned during initial/full fetches.",
            desc_len_about_timeline = "TIMELINE — ONE EVENT PER CHAPTER (always)\n\nTimeline always has exactly one entry per chapter. This setting only affects how much detail is included in each summary.\n\n• Short (~50 chars): Brief one-phrase summary.\n• Default (~80 chars): Standard summary.\n• Detailed (~150 chars): Includes context and consequences.\n• Very Detailed (~200 chars): Full narrative description.\n\nThere is no count trade-off for the timeline.",
            mention_return_label = "← Back to p.%d",
            mention_return_btn = "← Back",
            mention_dismiss_btn = "✕",
            msg_fetch_failed = "AI request failed. Please check your connection or API settings.",
            menu_beta_channel = "Beta Channel Settings",
            beta_enabled = "Beta Channel Enabled",
            beta_disabled = "Stable Channel (Recommended)",
            beta_channel_desc = "The beta channel allows you to receive pre-release versions of the X-Ray plugin. These versions include the latest features and bug fixes but may be less stable than the regular release.",
            beta_preference_desc = "Select your update channel preference:",
            error_quota_title = "Quota Exceeded",
            error_quota_desc = "Your API credits are exhausted or you have reached the rate limit. Please check your billing status or wait a while before trying again.",
            error_api_key_title = "Invalid API Key",
            error_api_key_desc = "The API key provided was rejected. Please check your settings and ensure the key is correct.",
            error_model_access_title = "Permission Denied",
            error_model_access_desc = "Your API key does not have access to the selected model. You might need to use a different model or provider.",
            error_service_down_title = "Service Unavailable",
            error_service_down_desc = "The AI service is temporarily unavailable or overloaded. Please try again in a few minutes.",
            error_timeout_title = "Connection Timed Out",
            error_timeout_desc = "The request took too long. This can happen with complex books or slow network connections.",
            error_parse_title = "Data Error",
            error_parse_desc = "The AI returned a response that could not be processed. This might be a temporary glitch.",
            error_unknown_title = "Fetch Failed",
            error_unknown_desc = "An unexpected error occurred: %s",
            error_model_not_found_title = "Model Not Found",
            error_model_not_found_desc = "The selected AI model is unavailable or the endpoint URL is incorrect.",
            menu_terms = "Glossary",
            menu_book_mode = "Book Mode",
            search_term = "Search Terms",
            label_expanded = "STANDS FOR",
            label_category = "CATEGORY",
            label_definition = "DEFINITION",
            no_terms_data = "No terms data yet. Please use 'Fetch X-Ray Data' first.",
            term_not_found = "No term found matching '%s'",
            msg_added_terms = "Added %d new terms!",
            extracting_more_terms = "Extracting additional terms...",
            book_mode_desc = "Select the mode for this book.",
            book_mode_auto = "Auto",
            book_mode_fiction = "Fiction",
            book_mode_nonfiction = "Non-Fiction",
            book_mode_saved = "Book mode saved!",
                        current_mode = "Current: ",
            menu_fetch_more_terms = "Fetch More Terms",
            model_free = "free",
            model_paid = "paid",
            menu_series_context = "Series Context",
            series_context_enabled_toggle = "Enable Series Context",
            series_context_prompt_title = "Series Detected",
            series_context_prompt_text = "This appears to be Book %d of '%s'. Load a recap of the previous %d book(s)?\n\n(You can disable this in Settings → Series Context)",
            fetching_series_context = "Fetching series context: Book %d of %d…",
            series_context_loaded = "Series context loaded (%d prior books).",
            series_prior_label = "[Prior]",
            series_prior_books_header = "── Prior Books ──",
            series_no_prior_detected = "No prior books detected for this series.",
            menu_fetch_series_context = "Fetch / Refresh Series Context",
            later = "Later",
            dont_ask_again = "Don't ask again",
            series_ask_later_msg = "Series recap postponed. We will ask again when you open/resume this book.",
            series_disabled_msg = "Auto-prompt disabled for this book. You can manually fetch recap from X-Ray menu.",
            relookup_button = "Re-lookup '%s'",
            low_conf_match = "Partial match — showing '%s' for your query. Tap below to fetch the exact term.",
            ai_scanning_duplicates = "AI is scanning for duplicates...",
            no_duplicates_found = "No duplicates found.",
            ai_merged_n = "Merged %d pair(s) successfully.",
            ai_merge_confirm_title = "AI Duplicate Detected",
            no_merges_performed = "No merges were performed.",
            merge_button = "Merge",
            skip = "Skip",
            stop = "Stop",
            reason = "Reason",
            entity_label_characters = "characters",
            entity_label_locations = "locations",
            pending_duplicates_prompt = "AI found %d possible duplicate(s) from the last fetch. Review now?",
            review = "Review",
        }
        translation = fallbacks[key] or key
    end
    
    -- Format with arguments
    local arg_count = select('#', ...)
    if arg_count > 0 then
        -- Convert nil arguments to "???" to avoid string.format errors
        local args = {}
        for i = 1, arg_count do
            local arg = select(i, ...)
            if arg == nil then
                args[i] = "???"
            else
                args[i] = arg
            end
        end
        
        -- Check if it contains positional arguments like %1$d or %2$s
        if translation:find("%%%d+%$") then
            local success, result = pcall(function()
                return string.gsub(translation, "%%(%d+)%$([-+ #0]?%d*%.?%d*[cdeEfgGiouuxXsqp%%])", function(index, spec)
                    local idx = tonumber(index)
                    local val = args[idx]
                    if val == nil then val = "???" end
                    if spec == "%" then return "%" end
                    return string.format("%" .. spec, val)
                end)
            end)
            if success then
                return result
            else
                logger.warn("Localization: Positional format error for key:", key)
                logger.warn("Localization: Error:", result)
                return translation
            end
        else
            local success, result = pcall(string.format, translation, (unpack or table.unpack)(args))
            if success then
                return result
            else
                logger.warn("Localization: Format error for key:", key)
                logger.warn("Localization: Error:", result)
                return translation
            end
        end
    end
    
    return translation
end

-- Load/save language preference (same as before)
function Localization:loadLanguage()
    local DataStorage = require("datastorage")
    local settings_dir = DataStorage:getSettingsDir()
    local xray_dir = settings_dir .. "/xray"
    local settings_file = xray_dir .. "/settings.json"
    local legacy_file   = xray_dir .. "/language.txt"
    
    -- 1. Graceful migration: read old language.txt if it exists, then delete it
    local migrated_lang = nil
    local legacy_f = io.open(legacy_file, "r")
    if legacy_f then
        local val = legacy_f:read("*a"):match("^%s*(.-)%s*$")
        legacy_f:close()
        os.remove(legacy_file)
        if val and #val > 0 then migrated_lang = val end
        logger.info("Localization: Migrated language.txt -> settings.json")
    end
    
    -- 2. Read from settings.json
    local lang = migrated_lang
    local sf = io.open(settings_file, "r")
    if sf then
        local content = sf:read("*a")
        sf:close()
        local ok_j, decoded = pcall(json.decode, content)
        if ok_j and type(decoded) == "table" and decoded.language then
            lang = decoded.language  -- settings.json wins if key exists
        end
    end
    
    -- 3. If we migrated a value but settings.json didn't have one, persist it now
    if migrated_lang and not lang then
        lang = migrated_lang
        self:saveLanguageToJson(xray_dir, settings_file, lang)
    end
    
    if lang and self:languageExists(lang) then
        self.current_language = lang
    else
        self.current_language = "en"
    end
end

function Localization:languageExists(lang_code)
    for _, code in ipairs(self.available_languages) do
        if code == lang_code then return true end
    end
    return false
end

function Localization:getLanguage()
    return self.current_language
end

function Localization:getLanguageName()
    return self.translations["language_name"] or self.current_language
end

function Localization:setLanguage(lang_code)
    if not self:languageExists(lang_code) then
        logger.warn("Localization: Cannot set non-existent language:", lang_code)
        return false
    end
    
    self.current_language = lang_code
    
    local DataStorage = require("datastorage")
    local settings_dir = DataStorage:getSettingsDir()
    local xray_dir = settings_dir .. "/xray"
    lfs.mkdir(xray_dir)
    
    local settings_file = xray_dir .. "/settings.json"
    self:saveLanguageToJson(xray_dir, settings_file, lang_code)
    
    self:loadTranslations()
    
    local AIHelper = require(plugin_path .. "xray_aihelper")
    if AIHelper then
        AIHelper:loadLanguage()
    end
    
    return true
end

function Localization:saveLanguageToJson(xray_dir, settings_file, lang_code)
    local existing = {}
    local sf = io.open(settings_file, "r")
    if sf then
        local content = sf:read("*a")
        sf:close()
        local ok, decoded = pcall(json.decode, content)
        if ok and type(decoded) == "table" then existing = decoded end
    end
    existing.language = lang_code
    local out = io.open(settings_file, "w")
    if out then
        out:write(json.encode(existing))
        out:close()
        logger.info("Localization: Language saved to settings.json:", lang_code)
    end
end

-- Reload translations (call this after editing .po files)
function Localization:reload()
    logger.info("Localization: Reloading translations...")
    self:loadTranslations()
    
    -- Clear cached translations in AIHelper if it exists
    local AIHelper = require(plugin_path .. "xray_aihelper")
    if AIHelper and AIHelper.localization then
        AIHelper.localization = nil
    end
    
    logger.info("Localization: Reload complete")
end

return Localization
