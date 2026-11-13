--[[
    xray_booktype.lua
    Book type detection (heuristic & AI), override handling, and book type menus for KOReader X-Ray Plugin.
--]]

local UIManager = require("ui/uimanager")

local plugin_path = ((...) or ""):match("(.-)[^%.]+$") or ""

local M = {}

local function isArchiveFormat(path)
    if not path then return false end
    local ext = path:match("%.([^%.]+)$")
    if not ext then return false end
    ext = ext:lower()
    return ext == "cbz" or ext == "cbr" or ext == "cb7" or ext == "cbt"
end
M.isArchiveFormat = isArchiveFormat

function M:detectBookTypeHeuristic()
    local book_path = self.ui and self.ui.document and self.ui.document.file
    if not book_path then return "unknown", false end
    
    if isArchiveFormat(book_path) then
        return "manga", true -- archive format for comics/manga: highly confident
    end

    local props = self.ui.document:getProps() or {}
    local subjects = props.subject or props.Subject or ""
    local title = (props.title or ""):lower()
    local filename = (book_path:match("([^/\\]+)$") or ""):lower()

    local manga_kw = { "manga", "graphic novel", "comic", "omnibus", "vol%.", "chapter" }
    local poetry_kw = { "poetry", "poems", "verse" }
    local cookbook_kw = { "cookbook", "cook book", "recipe", "cooking" }
    local textbook_kw = { "textbook", "text book", "academic", "manual" }
    local travel_kw = { "travel guide", "lonely planet", "rough guide" }
    local fiction_kw = { "fiction", "novel", "fantasy", "thriller", "mystery", "romance",
                         "horror", "science fiction", "sci%-fi", "literary", "adventure",
                         "short stor", "young adult", "ya fiction" }
    local nonfiction_kw = { "nonfiction", "non%-fiction", "history", "biography", "memoir",
                            "autobiography", "science", "self%-help", "psychology", "economics",
                            "philosophy", "true crime", "politics", "essay" }

    local function match_keywords(str, kw_list)
        if not str or str == "" then return false end
        str = str:lower()
        for _, kw in ipairs(kw_list) do
            if str:find(kw) then return true end
        end
        return false
    end

    -- 1. Niche checks
    if match_keywords(subjects, manga_kw) then return "manga", true end
    if match_keywords(title, manga_kw) or match_keywords(filename, manga_kw) then return "manga", false end

    if match_keywords(subjects, poetry_kw) then return "poetry", true end
    if match_keywords(title, poetry_kw) or match_keywords(filename, poetry_kw) then return "poetry", false end

    if match_keywords(subjects, cookbook_kw) then return "cookbook", true end
    if match_keywords(title, cookbook_kw) or match_keywords(filename, cookbook_kw) then return "cookbook", false end

    if match_keywords(subjects, textbook_kw) then return "textbook", true end
    if match_keywords(title, textbook_kw) or match_keywords(filename, textbook_kw) then return "textbook", false end

    if match_keywords(subjects, travel_kw) then return "travel", true end
    if match_keywords(title, travel_kw) or match_keywords(filename, travel_kw) then return "travel", false end

    -- 2. Fiction / Non-Fiction positive checks
    if match_keywords(subjects, fiction_kw) then return "prose_fiction", true end
    if match_keywords(title, fiction_kw) or match_keywords(filename, fiction_kw) then return "prose_fiction", false end

    if match_keywords(subjects, nonfiction_kw) then return "prose_nonfiction", true end
    if match_keywords(title, nonfiction_kw) or match_keywords(filename, nonfiction_kw) then return "prose_nonfiction", false end

    -- 3. File extension fallback
    local ext = book_path:match("%.([^%.]+)$")
    if ext then
        ext = ext:lower()
        if ext == "epub" or ext == "mobi" or ext == "azw" or ext == "azw3" or ext == "fb2" or ext == "txt" then
            return "prose_fiction", false -- default to prose fiction (low confidence guess)
        end
    end

    return "unknown", false
end

function M:getEffectiveBookType()
    local cached = self.book_data or {}
    if cached.book_type_label_override and cached.book_type_label_override ~= "auto" then
        return cached.book_type_label_override
    end
    local book_path = self.ui and self.ui.document and self.ui.document.file
    if isArchiveFormat(book_path) then
        if cached.book_type_label == "manga" or cached.book_type_label == "graphic_novel" then
            return cached.book_type_label
        end
        return "manga"
    end
    if cached.book_type_label and cached.book_type_label ~= "" then
        return cached.book_type_label
    end
    local heur = self:detectBookTypeHeuristic()
    if heur and heur ~= "unknown" then
        return heur
    end
    return "unknown"
end

function M:triggerBookTypeDetection()
    if self.destroyed or not self.ui or not self.ui.document then return true end
    local doc_file = self.ui.document.file
    if not doc_file then return true end

    if not self.book_data then
        self.book_data = {}
    end
    local cached = self.book_data
    local is_archive = isArchiveFormat(doc_file)

    local function newBookTypeResultFile()
        local ok_ds, DataStorage = pcall(require, "datastorage")
        local data_dir = (ok_ds and DataStorage and DataStorage.getDataDir and DataStorage:getDataDir())
                      or (ok_ds and DataStorage and DataStorage.getSettingsDir and DataStorage:getSettingsDir())
                      or "/tmp"
        return string.format(
            "%s/xray/book_type_detect_res_%d_%d.json",
            data_dir,
            os.time(),
            math.random(1000, 9999)
        )
    end

    -- Check if we already have a unit cache first to avoid scans
    local scan_already_triggered = false
    local function hasUnitCache()
        if self.unit_xp_matches ~= nil then
            return true
        end
        if self.loadUnitCache then
            return self:loadUnitCache()
        end
        return false
    end

    local function checkAndTriggerScan()
        local settings = self.ai_helper and self.ai_helper.settings or {}
        local disabled_types = settings.unit_disabled_book_types or { "manga", "graphic_novel", "children", "poetry" }
        local book_type = self:getEffectiveBookType()
        local is_disabled = false
        for _, t in ipairs(disabled_types) do
            if t == book_type then
                is_disabled = true
                break
            end
        end

        if is_disabled then
            if self.clearUnitUnderlines then self:clearUnitUnderlines() end
        else
            local has_cache = hasUnitCache()
            if not has_cache and not scan_already_triggered then
                scan_already_triggered = true
                if self.scanBookForUnits then self:scanBookForUnits() end
            else
                if self.applyUnitUnderlines then self:applyUnitUnderlines() end
            end
        end
    end

    if cached.book_type_label and cached.book_type_label ~= "" then
        -- Backward-compatibility & self-healing for archive formats:
        -- Never let archive formats be classified as prose fiction or non-comic types
        local cache_dirty = false
        if is_archive then
            if cached.book_type_label ~= "manga" and cached.book_type_label ~= "graphic_novel" then
                cached.book_type_label = "manga"
                cache_dirty = true
            end
            if cached.book_type_confident ~= true then
                cached.book_type_confident = true
                cache_dirty = true
            end
            if cached.book_type_detected_by_ai then
                cached.book_type_detected_by_ai = false
                cache_dirty = true
            end
        elseif cached.book_type_confident == nil then
            -- Check if legacy cache was a confident heuristic match
            local heur, is_confident = self:detectBookTypeHeuristic()
            if is_confident and heur == cached.book_type_label then
                cached.book_type_confident = true
                cache_dirty = true
            end
        end

        if cache_dirty and self.cache_manager and doc_file then
            self.cache_manager:asyncSaveCache(doc_file, cached)
        end

        checkAndTriggerScan()

        local has_override = cached.book_type_label_override and cached.book_type_label_override ~= "auto"
        local should_refine = not is_archive
            and not has_override
            and not cached.book_type_confident
            and not cached.book_type_detected_by_ai
            and not self._book_type_detecting
            and self.ai_helper:hasApiKey()

        if should_refine then
            -- Avoid forking background AI processes concurrently while unit scanner is running or starting
            local has_cache = hasUnitCache()
            if self._unit_scan_in_progress or not has_cache then
                UIManager:scheduleIn(15, function()
                    if not self.destroyed and self.ui and self.ui.document and not self._unit_scan_in_progress then
                        if self.triggerBookTypeDetection then
                            self:triggerBookTypeDetection()
                        end
                    end
                end)
                return
            end
            self._book_type_detecting = true
            local result_file = newBookTypeResultFile()
            local props = (self.ui and self.ui.document and self.ui.document.getProps and self.ui.document:getProps()) or {}
            local title = props.title or "Unknown"
            local author = props.authors or "Unknown"
            local series = props.series or props.Series or "None"
            local description = props.subject or props.Subject or "None"
            local pid = self.ai_helper:detectBookTypeAsync(title, author, series, description, result_file)
            if pid then
                local function pollResult()
                    if self.destroyed or not self.ui or not self.ui.document then
                        self._book_type_detecting = nil
                        return
                    end
                    local res = self.ai_helper:checkAsyncResult(result_file, pid)
                    if res == nil then
                        UIManager:scheduleIn(1, pollResult)
                    else
                        self._book_type_detecting = nil
                        if type(res) == "table" and res.book_type_label then
                            if not isArchiveFormat(doc_file) then
                                cached.book_type_label = res.book_type_label
                                cached.book_type_detected_by_ai = true
                                cached.book_type_confident = true
                                if self.cache_manager and doc_file then
                                    self.cache_manager:asyncSaveCache(doc_file, cached)
                                end
                                checkAndTriggerScan()
                            end
                        end
                    end
                end
                UIManager:scheduleIn(1, pollResult)
            else
                self._book_type_detecting = nil
            end
        end
        return true
    end

    -- Run Layer 1 & 2 heuristic
    local heur, is_confident = self:detectBookTypeHeuristic()
    if is_archive then
        heur = "manga"
        is_confident = true
    end

    if heur ~= "unknown" then
        cached.book_type_label = heur
        cached.book_type_confident = is_confident or is_archive
        cached.book_type_detected_by_ai = false
        if self.cache_manager and doc_file then
            self.cache_manager:asyncSaveCache(doc_file, cached)
        end
        checkAndTriggerScan()

        if cached.book_type_confident then
            return true -- high confidence heuristic or archive format, no AI needed
        end

        -- Low confidence heuristic, we run Layer 3 AI background refinement since confidence is low
        if not self.ai_helper:hasApiKey() or self._book_type_detecting then
            return true
        end
        self._book_type_detecting = true
        self:log("XRayPlugin: Starting Layer 3 AI book type refinement in background...")
        local result_file = newBookTypeResultFile()
        local props = (self.ui and self.ui.document and self.ui.document.getProps and self.ui.document:getProps()) or {}
        local title = props.title or "Unknown"
        local author = props.authors or "Unknown"
        local series = props.series or props.Series or "None"
        local description = props.subject or props.Subject or "None"
        local pid = self.ai_helper:detectBookTypeAsync(title, author, series, description, result_file)
        if pid then
            local function pollResult()
                if self.destroyed or not self.ui or not self.ui.document then
                    self._book_type_detecting = nil
                    return
                end
                local res = self.ai_helper:checkAsyncResult(result_file, pid)
                if res == nil then
                    UIManager:scheduleIn(1, pollResult)
                else
                    self._book_type_detecting = nil
                    if type(res) == "table" and res.book_type_label then
                        if not isArchiveFormat(doc_file) then
                            self:log("XRayPlugin: Book type AI refinement complete! Result: " .. tostring(res.book_type_label))
                            cached.book_type_label = res.book_type_label
                            cached.book_type_detected_by_ai = true
                            cached.book_type_confident = true
                            if self.cache_manager and doc_file then
                                self.cache_manager:asyncSaveCache(doc_file, cached)
                            end
                            checkAndTriggerScan()
                        end
                    end
                end
            end
            UIManager:scheduleIn(1, pollResult)
        else
            self._book_type_detecting = nil
        end
        return true
    end

    -- Run Layer 3 LLM classification directly if API keys exist and heuristic was unknown
    if not self.ai_helper:hasApiKey() or self._book_type_detecting or is_archive then
        checkAndTriggerScan()
        return true
    end

    self._book_type_detecting = true
    self:log("XRayPlugin: Starting Layer 3 AI book type detection in background...")
    local result_file = newBookTypeResultFile()
    
    local props = (self.ui and self.ui.document and self.ui.document.getProps and self.ui.document:getProps()) or {}
    local title = props.title or "Unknown"
    local author = props.authors or "Unknown"
    local series = props.series or props.Series or "None"
    local description = props.subject or props.Subject or "None"

    local pid, err_c, err_m = self.ai_helper:detectBookTypeAsync(title, author, series, description, result_file)
    if not pid then
        self._book_type_detecting = nil
        self:log("XRayPlugin: Book type AI detection trigger failed: " .. tostring(err_m))
        checkAndTriggerScan()
        return true
    end

    local function pollResult()
        if self.destroyed or not self.ui or not self.ui.document then
            self._book_type_detecting = nil
            return
        end
        local res = self.ai_helper:checkAsyncResult(result_file, pid)
        if res == nil then
            UIManager:scheduleIn(1, pollResult)
        else
            self._book_type_detecting = nil
            if type(res) == "table" and res.book_type_label then
                if not isArchiveFormat(doc_file) then
                    self:log("XRayPlugin: Book type AI detection complete! Result: " .. tostring(res.book_type_label))
                    cached.book_type_label = res.book_type_label
                    cached.book_type_detected_by_ai = true
                    cached.book_type_confident = true
                    if self.cache_manager and doc_file then
                        self.cache_manager:asyncSaveCache(doc_file, cached)
                    end
                    checkAndTriggerScan()
                end
            else
                self:log("XRayPlugin: Book type AI detection returned invalid or empty result: " .. tostring(res))
                checkAndTriggerScan()
            end
        end
    end
    UIManager:scheduleIn(1, pollResult)
    return true
end

function M:handleBookTypeOverride(val)
    if self.destroyed or not self.ui or not self.ui.document then return end
    local doc_file = self.ui.document.file
    if not doc_file then return end

    if not self.book_data then
        self.book_data = {}
    end
    self.book_data.book_type_label_override = val
    if self.cache_manager then
        self.cache_manager:asyncSaveCache(doc_file, self.book_data)
    end

    local cache_loaded = false
    if self.loadUnitCache then
        cache_loaded = self:loadUnitCache()
    end

    local settings = self.ai_helper and self.ai_helper.settings or {}
    local disabled_types = settings.unit_disabled_book_types or { "manga", "graphic_novel", "children", "poetry" }
    local is_disabled = false
    local book_type = self:getEffectiveBookType()
    for _, t in ipairs(disabled_types) do
        if t == book_type then
            is_disabled = true
            break
        end
    end

    if is_disabled then
        if self.clearUnitUnderlines then self:clearUnitUnderlines() end
    elseif not cache_loaded then
        self:closeAllMenus()
        if self.scanBookForUnits then self:scanBookForUnits() end
    else
        if self.applyUnitUnderlines then self:applyUnitUnderlines() end
    end
end

function M:showBookTypeOverrideCard(refresh_parent)
    local XRaySettingsCard = require(plugin_path .. "xray_settings_card")
    local book_types = {
        { key = "prose_fiction", text = self.loc:t("unit_book_type_prose_fiction") or "Fiction (Novels, Stories)" },
        { key = "prose_nonfiction", text = self.loc:t("unit_book_type_prose_nonfiction") or "Non-Fiction (History, Science, etc.)" },
        { key = "manga", text = self.loc:t("unit_book_type_manga") or "Manga" },
        { key = "graphic_novel", text = self.loc:t("unit_book_type_graphic_novel") or "Graphic Novels & Comics" },
        { key = "children", text = self.loc:t("unit_book_type_children") or "Children's Books" },
        { key = "poetry", text = self.loc:t("unit_book_type_poetry") or "Poetry & Verse" },
        { key = "cookbook", text = self.loc:t("unit_book_type_cookbook") or "Cookbooks & Recipes" },
        { key = "textbook", text = self.loc:t("unit_book_type_textbook") or "Textbooks & Academic" },
        { key = "travel", text = self.loc:t("unit_book_type_travel") or "Travel Guides" },
        { key = "unknown", text = self.loc:t("unit_book_type_unknown") or "Unknown/Other" },
    }

    local override_opts = {
        { text = self.loc:t("unit_book_type_auto") or "Auto-detect", value = "auto" }
    }
    for _, bt in ipairs(book_types) do
        table.insert(override_opts, { text = bt.text, value = bt.key })
    end

    XRaySettingsCard.show(self, {
        title = self.loc:t("unit_book_type_override") or "Override for this book",
        options = override_opts,
        get_current_func = function()
            local cached = self.book_data or {}
            return cached.book_type_label_override or "auto"
        end,
        save_func = function(val)
            self:handleBookTypeOverride(val)
            if refresh_parent then refresh_parent() end
        end,
    })
end

function M:getBookTypeFilterMenu()
    local book_types = {
        { key = "prose_fiction", text = self.loc:t("unit_book_type_prose_fiction") or "Fiction (Novels, Stories)" },
        { key = "prose_nonfiction", text = self.loc:t("unit_book_type_prose_nonfiction") or "Non-Fiction (History, Science, etc.)" },
        { key = "manga", text = self.loc:t("unit_book_type_manga") or "Manga" },
        { key = "graphic_novel", text = self.loc:t("unit_book_type_graphic_novel") or "Graphic Novels & Comics" },
        { key = "children", text = self.loc:t("unit_book_type_children") or "Children's Books" },
        { key = "poetry", text = self.loc:t("unit_book_type_poetry") or "Poetry & Verse" },
        { key = "cookbook", text = self.loc:t("unit_book_type_cookbook") or "Cookbooks & Recipes" },
        { key = "textbook", text = self.loc:t("unit_book_type_textbook") or "Textbooks & Academic" },
        { key = "travel", text = self.loc:t("unit_book_type_travel") or "Travel Guides" },
        { key = "unknown", text = self.loc:t("unit_book_type_unknown") or "Unknown/Other" },
    }

    local function getDetectedStr()
        local cached = self.book_data or {}
        local raw = cached.book_type_label
        local via = "Heuristic"
        if cached.book_type_detected_by_ai then
            via = "AI"
        elseif not raw or raw == "" then
            raw = self:detectBookTypeHeuristic()
        end
        local label = "Unknown/Other"
        for _, bt in ipairs(book_types) do
            if bt.key == raw then label = bt.text; break end
        end
        -- Strip parenthetical text to prevent truncation in native menus
        label = label:gsub("%s*%b()", "")
        return string.format("%s (%s)", label, via)
    end

    local menu = {
        {
            text = (self.loc:t("unit_book_type_detected") or "Detected Book Type") .. ": " .. getDetectedStr(),
            enabled = false,
        },
        {
            text = self.loc:t("unit_book_type_override") or "Override for this book",
            keep_menu_open = true,
            callback = function()
                self:showBookTypeOverrideCard()
            end
        },
        {
            text = self.loc:t("unit_book_type_manage") or "Manage Enabled Types",
            keep_menu_open = true,
            sub_item_table_func = function()
                local opts = {}
                for _, bt in ipairs(book_types) do
                    table.insert(opts, {
                        text = bt.text,
                        checked_func = function()
                            local disabled = self.ai_helper.settings.unit_disabled_book_types or { "manga", "graphic_novel", "children", "poetry" }
                            local disabled_map = {}
                            for _, k in ipairs(disabled) do disabled_map[k] = true end
                            return not disabled_map[bt.key]
                        end,
                        callback = function()
                            local disabled = self.ai_helper.settings.unit_disabled_book_types or { "manga", "graphic_novel", "children", "poetry" }
                            local new_disabled = {}
                            local found = false
                            for _, k in ipairs(disabled) do
                                if k == bt.key then
                                    found = true
                                else
                                    table.insert(new_disabled, k)
                                end
                            end
                            if not found then
                                table.insert(new_disabled, bt.key)
                            end
                            self.ai_helper:saveSettings({ unit_disabled_book_types = new_disabled })

                            local cache_loaded = false
                            if self.loadUnitCache then
                                cache_loaded = self:loadUnitCache()
                            end

                            local is_disabled = false
                            local book_type = self:getEffectiveBookType()
                            for _, t in ipairs(new_disabled) do
                                if t == book_type then
                                    is_disabled = true
                                    break
                                end
                            end

                            if is_disabled then
                                if self.clearUnitUnderlines then self:clearUnitUnderlines() end
                            elseif not cache_loaded then
                                self:closeAllMenus()
                                if self.scanBookForUnits then self:scanBookForUnits() end
                            else
                                if self.applyUnitUnderlines then self:applyUnitUnderlines() end
                            end
                        end
                    })
                end
                return opts
            end
        }
    }
    return menu
end

return M
