-- X-Ray UI and Menu Functions

local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")
local ConfirmBox = require("ui/widget/confirmbox")
local ButtonDialog = require("ui/widget/buttondialog")
local Menu = require("ui/widget/menu")
local Screen = require("device").screen
local _ = require("gettext")
local plugin_path = ((...) or ""):match("(.-)[^%.]+$") or ""

local M = {}

function M:showLanguageSelection()
    local Menu = require("ui/widget/menu")
    local settings_lang = (self.ai_helper and self.ai_helper.settings) and self.ai_helper.settings.language or "auto"
    
    local function changeLang(lang_code)
        UIManager:close(self.ldlg)
        self.ldlg = nil
        
        if self.ai_helper then
            self.ai_helper:saveSettings({ language = lang_code })
        end
        
        -- Apply the new setting immediately
        self:applyLanguageLogic()
        
        local msg = (self.loc and self.loc:t("language_changed_reopen")) or "Language changed. Reopen the menu to see the changes."
        
        -- Use the centralized silver-bullet clear
        self:closeAllMenus()
        
        UIManager:show(InfoMessage:new{
            text = "[OK] " .. msg,
            timeout = 3
        })
    end
    
    local items = {
        {
            text = (settings_lang == "auto" and "[✓] " or "[  ] ") .. (self.loc:t("lang_follow_system") or "Automatic (Follow System)"),
            callback = function() changeLang("auto") end
        },
        {
            text = (settings_lang == "book" and "[✓] " or "[  ] ") .. (self.loc:t("lang_follow_book") or "Automatic (Follow Book)"),
            callback = function() changeLang("book") end,
            separator = true
        }
    }
    
    local LANGUAGE_NAMES = {
        en = "English",
        de = "Deutsch",
        fr = "Français",
        ru = "Русский",
        zh_CN = "简体中文",
        tr = "Türkçe",
        pt_br = "Português",
        es = "Español",
        uk = "Українська",
        hu = "Magyar",
        nl = "Nederlands",
    }
    
    local langs = self.loc and self.loc.available_languages or { "en", "de", "fr", "ru", "zh_CN", "tr", "pt_br", "es", "uk", "hu" }
    for _, code in ipairs(langs) do
        local name = LANGUAGE_NAMES[code] or code:upper()
        table.insert(items, {
            text = (settings_lang == code and "[✓] " or "[  ] ") .. name,
            callback = function() changeLang(code) end
        })
    end
    
    local dialog_title = (self.loc and self.loc:t("menu_language")) or "Language Selection"
    self.ldlg = Menu:new{
        title = dialog_title,
        item_table = items,
        is_borderless = true,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        on_close_callback = function()
            self.ldlg = nil
        end
    }
    UIManager:show(self.ldlg)
end

function M:resolveLanguage(code)
    local supported = {}
    if self.loc and self.loc.available_languages then
        for _, c in ipairs(self.loc.available_languages) do
            supported[c] = 1
        end
    else
        supported = { en=1, de=1, fr=1, ru=1, zh_CN=1, tr=1, pt_br=1, es=1, uk=1, hu=1 }
    end
    
    if code == "auto" or not code then
        local gettext = require("gettext")
        local ko_lang = gettext.getLanguage and gettext.getLanguage()
        
        -- Fallback to G_reader_settings if gettext doesn't provide it
        if not ko_lang and G_reader_settings then
            ko_lang = G_reader_settings:readSetting("language")
        end
        
        if ko_lang then
            local lang = ko_lang:sub(1, 2):lower()
            if ko_lang:lower():find("zh_cn") or ko_lang:lower():find("zh-cn") then lang = "zh_CN"
            elseif ko_lang:lower():find("pt_br") or ko_lang:lower():find("pt-br") then lang = "pt_br" end
            if supported[lang] then return lang end
        end
        return "en"
    elseif code == "book" then
        if self.ui and self.ui.document then
            local props = self.ui.document:getProps()
            local book_lang = props.language
            if book_lang then
                local lang = book_lang:sub(1, 2):lower()
                if book_lang:lower():find("zh") then lang = "zh_CN"
                elseif book_lang:lower():find("pt") then lang = "pt_br" end
                if supported[lang] then return lang end
            end
        end
        return self:resolveLanguage("auto")
    end
    return code or "en"
end

function M:applyLanguageLogic()
    local settings_lang = (self.ai_helper and self.ai_helper.settings) and self.ai_helper.settings.language or "auto"
    local resolved = self:resolveLanguage(settings_lang)
    
    self:log("XRayPlugin: Applying language logic. Settings: " .. tostring(settings_lang) .. ", Resolved: " .. tostring(resolved))
    
    if self.loc and self.loc.setLanguage then
        self.loc:setLanguage(resolved)
    end
    
    if self.ai_helper then
        self.ai_helper.current_language = resolved
        self.ai_helper:loadLanguage()
    end
end

function M:checkBookLanguageMatch()
    local settings_lang = (self.ai_helper and self.ai_helper.settings) and self.ai_helper.settings.language or "auto"
    -- Only suggest if we are NOT in "Follow Book" mode already
    if settings_lang == "book" then return end
    
    if not self.ui or not self.ui.document then return end
    local props = self.ui.document:getProps()
    local book_lang = props.language
    if not book_lang or book_lang == "" then return end
    
    local lang = book_lang:sub(1, 2):lower()
    if book_lang:find("zh") then lang = "zh_CN"
    elseif book_lang:find("pt") then lang = "pt_br" end
    
    local LANGUAGE_NAMES = {
        en = "English",
        de = "Deutsch",
        fr = "Français",
        ru = "Русский",
        zh_CN = "简体中文",
        tr = "Türkçe",
        pt_br = "Português",
        es = "Español",
        uk = "Українська",
        hu = "Magyar",
        nl = "Nederlands",
    }
    
    local supported = {}
    if self.loc and self.loc.available_languages then
        for _, c in ipairs(self.loc.available_languages) do
            supported[c] = LANGUAGE_NAMES[c] or c:upper()
        end
    else
        for c, name in pairs(LANGUAGE_NAMES) do
            supported[c] = name
        end
    end
    
    if not supported[lang] then return end
    
    local current_lang = self.loc:getLanguage()
    if lang == current_lang then return end
    
    if self.suggestion_dismissed[self.ui.document.file] then return end
    
    -- Check if we should ignore this book (from cache)
    if not self.cache_manager then self.cache_manager = require(plugin_path .. "xray_cachemanager"):new() end
    local cache = self.cache_manager:loadCache(self.ui.document.file)
    if cache and cache.ignore_lang_mismatch then return end

    -- Show prompt
    local lang_name = supported[lang]
    local msg = string.format(self.loc:t("msg_suggest_lang") or "This book is in %s. Switch X-Ray language to match?", lang_name)
    
    local ButtonDialog = require("ui/widget/buttondialog")
    local mismatch_dialog
    mismatch_dialog = ButtonDialog:new{
        title = self.loc:t("lang_mismatch_title") or "Language Mismatch",
        text = msg,
        buttons = {
            {
                {
                    text = self.loc:t("yes") or "Yes",
                    is_enter_default = true,
                    callback = function()
                        if self.ai_helper then
                            self.ai_helper:saveSettings({ language = lang })
                            self:applyLanguageLogic()
                            UIManager:close(mismatch_dialog)
                            UIManager:show(InfoMessage:new{
                                text = self.loc:t("language_changed_reopen") or "Language changed.",
                                timeout = 3
                            })
                        end
                    end
                },
                {
                    text = self.loc:t("no") or "No",
                    callback = function()
                        self.suggestion_dismissed[self.ui.document.file] = true
                        UIManager:close(mismatch_dialog)
                    end
                }
            },
            {
                {
                    text = self.loc:t("dont_ask_again") or "Don't ask again",
                    callback = function()
                        local current_cache = self.cache_manager:loadCache(self.ui.document.file) or {}
                        current_cache.ignore_lang_mismatch = true
                        self.cache_manager:saveCache(self.ui.document.file, current_cache)
                        UIManager:close(mismatch_dialog)
                    end
                }
            }
        }
    }
    UIManager:show(mismatch_dialog)
end

function M:closeAllMenus()
    -- Mark as cancelled to stop background tasks
    self.is_cancelled = true
    
    if self.bg_scan_handle and self.bg_scan_handle.cancel then
        pcall(function() self.bg_scan_handle:cancel() end)
    end
    if self.active_mention_scan and self.active_mention_scan.cancel_handle then
        pcall(function() self.active_mention_scan.cancel_handle:cancel() end)
        self.active_mention_scan = nil
    end

    if self.clearHighlightOverlay then
        pcall(function() self:clearHighlightOverlay() end)
    end

    -- 1. Close all custom plugin modals instantly
    local menus = {
        self.mentions_menu, self.char_menu, self.loc_menu,
        self.timeline_menu, self.hf_menu, self.xray_menu,
        self.terms_menu, self.active_details_dialog, self.return_banner
    }
    for i = 1, 9 do
        if menus[i] then pcall(function() UIManager:close(menus[i]) end) end
    end
    self.mentions_menu = nil; self.char_menu = nil; self.loc_menu = nil
    self.timeline_menu = nil; self.hf_menu = nil; self.xray_menu = nil
    self.terms_menu = nil; self.active_details_dialog = nil; self.return_banner = nil
    
    local function executeClear()
        -- 2. Dismiss native KOReader top menu stack
        if self.ui and self.ui.menu then
            pcall(function()
                if type(self.ui.menu.onCloseReaderMenu) == "function" then
                    self.ui.menu:onCloseReaderMenu()
                end
            end)
        end

        -- 3. Cleanup selection and highlights
        pcall(function()
            local Event = require("ui/event")
            local ok, DictQuickLookup = pcall(require, "ui/widget/dictquicklookup")
            if ok and DictQuickLookup and DictQuickLookup.window_list then
                for i = #DictQuickLookup.window_list, 1, -1 do
                    local window = DictQuickLookup.window_list[i]
                    if window and window.onClose then pcall(function() window:onClose() end) end
                end
            end
            if self.ui.highlight and self.ui.highlight.clear then
                pcall(function() self.ui.highlight:clear() end)
            end
            self.ui:handleEvent(Event:new("ClearSelection"))
        end)
    end
    
    -- Pass 1: Immediate
    executeClear()
    
    -- Pass 2: Staggered 100ms safety pass
    UIManager:scheduleIn(0.1, function()
        executeClear()
        -- Reset cancellation flag after all passes are done
        self.is_cancelled = false
    end)
end

function M:showCharacters()
    self.characters = self.characters or {}
    local items = {}
    if #self.characters > 0 then
        table.insert(items, { text = "⌕ " .. self.loc:t("search_character"), callback = function() self:showCharacterSearch() end })
        table.insert(items, { text = "⋈ " .. (self.loc:t("merge_duplicates") or "Merge Duplicates..."), callback = function() self:showMergeFlow(self.characters, "characters") end })
    end
    table.insert(items, { text = "✚ " .. (self.loc:t("menu_fetch_more_chars") or "Fetch More Characters"), keep_menu_open = true, callback = function() self:fetchMoreCharacters() end, separator = #self.characters > 0 })
    for _, char in ipairs(self.characters) do
        local name = char.name or "Unknown"
        if char.source == "series_prior" then
            name = name .. " " .. (self.loc:t("series_prior_label") or "[Prior]")
        end
        local text = "• " .. name
        -- Aliases are no longer listed in the main character list to reduce clutter,
        -- as they are still visible in the individual character infobox.
        if char.description and #char.description > 0 then text = text .. "\n  " .. char.description:sub(1, 80) .. (#char.description > 80 and "..." or "") end
        table.insert(items, { 
            text = text, 
            keep_menu_open = true,
            callback = function() self:showCharacterDetails(char) end 
        })
    end

    -- Close any existing character menu before showing the updated one
    if self.char_menu then
        UIManager:close(self.char_menu)
        self.char_menu = nil
    end

    self.char_menu = Menu:new{
        title = self.loc:t("menu_characters") .. " (" .. #self.characters .. ")",
        item_table = items,
        is_borderless = true,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        on_close_callback = function() 
            if self.is_cancelled then return end
            self:showFullXRayMenu() 
        end,
    }
    UIManager:show(self.char_menu)
end

function M:findRelatedEntities(text, exclude_name)
    if not text or text == "" then return {} end
    local related = {}
    local seen = {}
    if exclude_name then seen[exclude_name:lower()] = true end

    local lower_text = text:lower()

    -- Honorifics: fast-path blocklist for known titles.
    -- Tokens < 3 chars are already blocked by isTooGeneric's length check;
    -- 3-char titles (mr., mrs, sir, dr., etc.) are listed here since they can
    -- have plausible frequency ratios in densely character-focused descriptions.
    local honorifics = {
        ["mr"] = true, ["mr."] = true, ["mrs"] = true, ["mrs."] = true, ["ms"] = true, ["ms."] = true,
        ["dr"] = true, ["dr."] = true, ["sir"] = true, ["rev"] = true, ["rev."] = true, ["lt"] = true, ["lt."] = true,
        ["col"] = true, ["col."] = true, ["sgt"] = true, ["sgt."] = true, ["gen"] = true, ["gen."] = true,
        ["miss"] = true, ["lord"] = true, ["lady"] = true, ["dame"] = true, ["prof"] = true, ["prof."] = true,
        ["capt"] = true, ["capt."] = true, ["st"] = true, ["st."] = true, ["jr"] = true, ["jr."] = true,
        
        -- International
        ["m"] = true, ["m."] = true, ["mme"] = true, ["mme."] = true, ["mlle"] = true, ["mlle."] = true, ["mgr"] = true,
        ["herr"] = true, ["frau"] = true, ["hr"] = true, ["hr."] = true, ["fr"] = true, ["fr."] = true,
        ["sr"] = true, ["sr."] = true, ["sra"] = true, ["sra."] = true, ["don"] = true, ["dona"] = true, ["doña"] = true,
        ["bey"] = true, ["hanım"] = true,
        ["пан"] = true, ["пані"] = true, ["г-н"] = true, ["г-жа"] = true,
    }

    -- Frequency-ratio guard: if a candidate term appears 5× more often than the
    -- entity's full name in the text, it is too generic to be a useful identifier.
    -- This is language-agnostic — articles, stop words, and AI-hallucinated
    -- one-word aliases will all fail this test naturally.
    local function countInText(term)
        local escaped = term:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1")
        local pattern = escaped
        if #term < 4 then
            pattern = "%f[%w]" .. escaped .. "%f[%W]"
        end
        local _, n = lower_text:gsub(pattern, "")
        return n
    end
    local function isTooGeneric(term, entity_name)
        local term_l = term:lower()
        if #term < 2 or honorifics[term_l] then return true end
        local name_freq = math.max(1, countInText(entity_name:lower()))
        return countInText(term_l) > name_freq * 5
    end

    -- Check if a term appears in the text surrounded by non-word characters.
    -- Pads the text so names at the very start/end of a string also match.
    local function termFound(term)
        if not term or #term < 2 then return false end
        local escaped = term:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1")
        return (" " .. lower_text .. " "):find("[^%w]" .. escaped:lower() .. "[^%w]") ~= nil
    end

    local function scanList(list, type_name)
        if not list then return end
        for _, item in ipairs(list) do
            local name = item.name
            if name and not seen[name:lower()] then
                local found = false

                -- Strategy 1: Full name match
                if termFound(name) then
                    found = true
                end

                -- Strategy 2: Aliases (skip generic and honorific-only aliases)
                if not found and item.aliases then
                    for _, alias in ipairs(item.aliases) do
                        if type(alias) == "string"
                                  and not honorifics[alias:lower()]
                                  and not isTooGeneric(alias, name)
                                  and termFound(alias) then
                            found = true
                            break
                        end
                    end
                end

                if found then
                    seen[name:lower()] = true
                    table.insert(related, { item = item, type = type_name })
                end
            end
        end
    end

    scanList(self.characters, "character")
    scanList(self.locations, "location")
    scanList(self.historical_figures, "historical")
    scanList(self.terms, "term")

    return related
end

function M:showRelatedEntities(related)
    local items = {}
    if self.active_related_menu then
        UIManager:close(self.active_related_menu)
        self.active_related_menu = nil
    end

    for _, entry in ipairs(related) do
        local item = entry.item
        local item_type = entry.type
        local display_type = item_type:sub(1,1):upper() .. item_type:sub(2)
        table.insert(items, {
            text = (item.name or "???") .. " (" .. display_type .. ")",
            callback = function()
                -- Close both the linked entries menu and any open detail dialog
                -- before opening the new entity's detail.
                if self.active_related_menu then
                    UIManager:close(self.active_related_menu)
                    self.active_related_menu = nil
                end
                if self.active_details_dialog then
                    UIManager:close(self.active_details_dialog)
                    self.active_details_dialog = nil
                end
                if item_type == "character" then
                    self:showCharacterDetails(item)
                elseif item_type == "location" then
                    self:showLocationDetails(item)
                elseif item_type == "historical" then
                    self:showHistoricalFigureDetails(item)
                elseif item_type == "term" then
                    self:showTermDetails(item)
                end
            end
        })
    end
    
    self.active_related_menu = Menu:new{
        title = self.loc:t("linked_entries") or "Linked Entries",
        item_table = items,
        on_close_callback = function()
            self.active_related_menu = nil
        end
    }
    UIManager:show(self.active_related_menu)
end

function M:showCharacterDetails(character)
    local lines = {
        (self.loc:t("label_name") or "NAME") .. ": " .. (character.name or "???")
    }
    if character.aliases and type(character.aliases) == "table" and #character.aliases > 0 then
        local meaningful_aliases = {}
        local name_lower = (character.name or ""):lower()
        -- Filter out aliases that are already trivial parts of the name
        for _, alias in ipairs(character.aliases) do
            local al_lower = tostring(alias):lower()
            if #al_lower > 1 and not name_lower:find(al_lower, 1, true) then
                table.insert(meaningful_aliases, alias)
            end
        end
        if #meaningful_aliases > 0 then
            table.insert(lines, (self.loc:t("label_aliases") or "ALIASES") .. ": " .. table.concat(meaningful_aliases, ", "))
        end
    end
    table.insert(lines, (self.loc:t("label_role") or "ROLE") .. ": " .. (character.role or "---"))
    table.insert(lines, (self.loc:t("label_gender") or "GENDER") .. ": " .. (character.gender or "---"))
    table.insert(lines, (self.loc:t("label_occupation") or "OCCUPATION") .. ": " .. (character.occupation or "---"))
    if character.ai_reasoning then
        table.insert(lines, "")
        table.insert(lines, "[" .. (self.loc:t("label_reasoning") or "AI REASONING") .. "]")
        table.insert(lines, character.ai_reasoning)
    end
    table.insert(lines, "")
    table.insert(lines, (self.loc:t("label_description") or "DESCRIPTION") .. ":")
    table.insert(lines, character.description or "---")
    local body_text = table.concat(lines, "\n")
    
    local linked_enabled = self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.linked_entries_enabled ~= false
    local related = linked_enabled and self:findRelatedEntities(character.description or "", character.name) or {}
    local mentions_enabled = self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.mentions_enabled ~= false
    
    if #related > 0 then
        local buttons = {
            {
                {
                    text = self.loc:t("linked_entries") or "Linked Entries",
                    callback = function()
                        self:showRelatedEntities(related)
                    end,
                }
            },
            {
                {
                    text = self.loc:t("find_mentions") or "Find Mentions",
                    callback = function()
                        if self.active_details_dialog then UIManager:close(self.active_details_dialog); self.active_details_dialog = nil end
                        self:showMentionsForEntity(character)
                    end,
                },
                {
                    text = self.loc:t("close") or "Close",
                    callback = function()
                        if self.active_details_dialog then UIManager:close(self.active_details_dialog) end
                        self.active_details_dialog = nil
                    end,
                }
            }
        }
        
        if not mentions_enabled then
            table.remove(buttons[2], 1)
        end
        
        self.active_details_dialog = ButtonDialog:new{
            title = table.concat(lines, "\n"),
            buttons = buttons,
        }
    else
        if mentions_enabled then
            self.active_details_dialog = ConfirmBox:new{
                text = table.concat(lines, "\n"),
                icon = "info",
                ok_text = self.loc:t("find_mentions") or "Find Mentions",
                cancel_text = self.loc:t("close") or "Close",
                ok_callback = function()
                    if self.active_details_dialog then UIManager:close(self.active_details_dialog); self.active_details_dialog = nil end
                    self:showMentionsForEntity(character)
                end,
                cancel_callback = function()
                    self.active_details_dialog = nil
                end,
            }
        else
            self.active_details_dialog = ConfirmBox:new{
                text = table.concat(lines, "\n"),
                icon = "info",
                ok_text = self.loc:t("close") or "Close",
                ok_callback = function() self.active_details_dialog = nil end,
                cancel_callback = function() self.active_details_dialog = nil end,
            }
        end
    end
    UIManager:show(self.active_details_dialog)
end

function M:showLocationDetails(loc_item)
    local name = loc_item.name or "???"
    local desc = loc_item.description or ""
    local body_text = name .. "\n\n" .. desc
    local linked_enabled = self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.linked_entries_enabled ~= false
    local related = linked_enabled and self:findRelatedEntities(desc, name) or {}
    local mentions_enabled = self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.mentions_enabled ~= false
    
    if #related > 0 then
        local buttons = {
            {
                {
                    text = self.loc:t("linked_entries") or "Linked Entries",
                    callback = function()
                        self:showRelatedEntities(related)
                    end,
                }
            },
            {
                {
                    text = self.loc:t("find_mentions") or "Find Mentions",
                    callback = function()
                        if self.active_details_dialog then UIManager:close(self.active_details_dialog); self.active_details_dialog = nil end
                        self:showMentionsForEntity(loc_item)
                    end,
                },
                {
                    text = self.loc:t("close") or "Close",
                    callback = function()
                        if self.active_details_dialog then UIManager:close(self.active_details_dialog) end
                        self.active_details_dialog = nil
                    end,
                }
            }
        }
        
        if not mentions_enabled then
            table.remove(buttons[2], 1)
        end
        
        self.active_details_dialog = ButtonDialog:new{
            title = body_text,
            buttons = buttons,
        }
    else
        if mentions_enabled then
            self.active_details_dialog = ConfirmBox:new{
                text = body_text,
                icon = "info",
                ok_text = self.loc:t("find_mentions") or "Find Mentions",
                cancel_text = self.loc:t("close") or "Close",
                ok_callback = function()
                    if self.active_details_dialog then UIManager:close(self.active_details_dialog); self.active_details_dialog = nil end
                    self:showMentionsForEntity(loc_item)
                end,
                cancel_callback = function()
                    self.active_details_dialog = nil
                end,
            }
        else
            self.active_details_dialog = ConfirmBox:new{
                text = body_text,
                icon = "info",
                ok_text = self.loc:t("close") or "Close",
                ok_callback = function() self.active_details_dialog = nil end,
                cancel_callback = function() self.active_details_dialog = nil end,
            }
        end
    end
    UIManager:show(self.active_details_dialog)
end

function M:showTermDetails(term)
    local name = term.name or "???"
    local lines = { (self.loc:t("label_name") or "NAME") .. ": " .. name }
    if term.aliases and type(term.aliases) == "table" and #term.aliases > 0 then
        local meaningful_aliases = {}
        local name_lower = name:lower()
        for _, alias in ipairs(term.aliases) do
            local al_lower = tostring(alias):lower()
            if #al_lower > 1 and not name_lower:find(al_lower, 1, true) then
                table.insert(meaningful_aliases, alias)
            end
        end
        if #meaningful_aliases > 0 then
            table.insert(lines, (self.loc:t("label_aliases") or "ALIASES") .. ": " .. table.concat(meaningful_aliases, ", "))
        end
    end
    if term.expanded and term.expanded ~= "" and term.expanded ~= term.name then
        table.insert(lines, (self.loc:t("label_expanded") or "STANDS FOR") .. ": " .. term.expanded)
    end
    if term.category and term.category ~= "" then
        table.insert(lines, (self.loc:t("label_category") or "CATEGORY") .. ": " .. term.category)
    end
    table.insert(lines, "")
    table.insert(lines, (self.loc:t("label_definition") or "DEFINITION") .. ":")
    table.insert(lines, term.definition or "---")
    
    local body_text = table.concat(lines, "\n")
    local linked_enabled = self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.linked_entries_enabled ~= false
    local related = linked_enabled and self:findRelatedEntities(term.definition or "", name) or {}
    local mentions_enabled = self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.mentions_enabled ~= false

    if #related > 0 then
        local buttons = {
            {
                {
                    text = self.loc:t("linked_entries") or "Linked Entries",
                    callback = function()
                        self:showRelatedEntities(related)
                    end,
                }
            },
            {
                {
                    text = self.loc:t("find_mentions") or "Find Mentions",
                    callback = function()
                        if self.active_details_dialog then UIManager:close(self.active_details_dialog); self.active_details_dialog = nil end
                        self:showMentionsForEntity(term)
                    end,
                },
                {
                    text = self.loc:t("close") or "Close",
                    callback = function()
                        if self.active_details_dialog then UIManager:close(self.active_details_dialog) end
                        self.active_details_dialog = nil
                    end,
                }
            }
        }
        if not mentions_enabled then table.remove(buttons[2], 1) end
        self.active_details_dialog = ButtonDialog:new{ title = body_text, buttons = buttons }
    else
        if mentions_enabled then
            self.active_details_dialog = ConfirmBox:new{
                text = body_text, icon = "info",
                ok_text = self.loc:t("find_mentions") or "Find Mentions",
                cancel_text = self.loc:t("close") or "Close",
                ok_callback = function()
                    if self.active_details_dialog then UIManager:close(self.active_details_dialog); self.active_details_dialog = nil end
                    self:showMentionsForEntity(term)
                end,
                cancel_callback = function() self.active_details_dialog = nil end,
            }
        else
            self.active_details_dialog = ConfirmBox:new{
                text = body_text, icon = "info",
                ok_text = self.loc:t("close") or "Close",
                ok_callback = function() self.active_details_dialog = nil end,
                cancel_callback = function() self.active_details_dialog = nil end,
            }
        end
    end
    UIManager:show(self.active_details_dialog)
end

function M:showTerms()
    self.terms = self.terms or {}
    local items = {}
    if #self.terms > 0 then
        table.insert(items, { text = "⌕ " .. (self.loc:t("search_term") or "Search Terms"), callback = function() self:showTermSearch() end })
    end
    table.insert(items, { text = "✚ " .. (self.loc:t("menu_fetch_more_terms") or "Fetch More Terms"), callback = function() self:fetchMoreTerms() end, separator = #self.terms > 0 })
    for _, term in ipairs(self.terms) do 
        if type(term) == "table" then
            local captured_term = term
            local name = term.name or "???"
            if term.source == "series_prior" then
                name = name .. " " .. (self.loc:t("series_prior_label") or "[Prior]")
            end
            table.insert(items, {
                text = "• " .. name,
                subtext = term.definition and term.definition:sub(1, 80) .. "...",
                keep_menu_open = true,
                callback = function()
                    self:showTermDetails(captured_term)
                end
            })
        end
    end
    
    self.terms_menu = Menu:new{
        title = (self.loc:t("menu_terms") or "Glossary") .. " (" .. #self.terms .. ")",
        item_table = items,
        is_borderless = true,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        on_close_callback = function() 
            if self.is_cancelled then return end
            self:showFullXRayMenu() 
        end,
    }
    UIManager:show(self.terms_menu)
end

function M:findTermByName(word)
    if not word or not self.terms then return nil end
    local query = word:lower()
    for _, term in ipairs(self.terms) do
        if (term.name or ""):lower() == query then
            return term
        end
        if term.aliases and type(term.aliases) == "table" then
            for _, alias in ipairs(term.aliases) do
                if tostring(alias):lower() == query then
                    return term
                end
            end
        end
    end
    return nil
end

function M:showTermSearch()
    if not self.terms or #self.terms == 0 then UIManager:show(InfoMessage:new{ text = self.loc:t("no_terms_data"), timeout = 3 }); return end
    local InputDialog = require("ui/widget/inputdialog")
    local input_dialog
    input_dialog = InputDialog:new{ 
        title = self.loc:t("search_term") or "Search Terms", 
        input = "", input_hint = self.loc:t("search_hint"), 
        buttons = {
            {{ text = self.loc:t("cancel"), callback = function() UIManager:close(input_dialog) end }, 
             { text = self.loc:t("search_button") or "Search", is_enter_default = true, 
               callback = function() 
                   local search_text = input_dialog:getInputText()
                   UIManager:close(input_dialog)
                   if search_text and #search_text > 0 then 
                       local found = self:findTermByName(search_text)
                       if found then self:showTermDetails(found) 
                       else UIManager:show(InfoMessage:new{ text = self.loc:t("term_not_found", search_text) or "Term not found.", timeout = 3 }) end 
                   end 
               end 
             }}
        } 
    }
    UIManager:show(input_dialog); input_dialog:onShowKeyboard()
end

function M:showBookTypeSettings()
    local ButtonDialog = require("ui/widget/buttondialog")
    local info_dialog
    
    local function showSettings()
        if info_dialog then UIManager:close(info_dialog) end
        
        local current = "auto"
        if not self.cache_manager then self.cache_manager = require(plugin_path .. "xray_cachemanager"):new() end
        local cache = self.cache_manager:loadCache(self.ui.document.file)
        if cache and cache.book_mode_override then
            current = cache.book_mode_override
        else
            current = self.ai_helper.settings.default_book_mode or "auto"
        end

        local function setType(mode)
            local cache = self.cache_manager:loadCache(self.ui.document.file) or {}
            cache.book_mode_override = mode
            self.cache_manager:saveCache(self.ui.document.file, cache)
            self.book_type = (mode == "auto") and nil or mode
            UIManager:show(InfoMessage:new{ text = self.loc:t("book_type_saved") or "Book Type saved!", timeout = 3 })
            UIManager:setDirty(nil, "ui")
            UIManager:nextTick(function() showSettings() end)
        end

        info_dialog = ButtonDialog:new{
            title = (self.loc:t("menu_book_mode") or "Book Type") .. "\n\n" .. (self.loc:t("book_mode_desc") or "Select the type for this book:"),
            buttons = {
                {
                    { 
                        text = (current == "auto" and "[✓] " or "[  ] ") .. (self.loc:t("book_type_auto") or "Auto-Detect"), 
                        callback = function() setType("auto") end 
                    },
                    { 
                        text = (current == "fiction" and "[✓] " or "[  ] ") .. (self.loc:t("book_type_fiction") or "Fiction"), 
                        callback = function() setType("fiction") end 
                    },
                    { 
                        text = (current == "non_fiction" and "[✓] " or "[  ] ") .. (self.loc:t("book_type_nonfiction") or "Non-Fiction"), 
                        callback = function() setType("non_fiction") end 
                    },
                },
                {
                    { 
                        text = self.loc:t("menu_about") or "About", 
                        callback = function()
                            UIManager:show(InfoMessage:new{
                                text = self.loc:t("book_type_about") or "The Book Type determines which AI extraction strategy is used.\n\n- Fiction: Focuses on characters, timeline, and world-building terms (factions, spells, lore, etc.).\n- Non-Fiction: Focuses on technical terms, concepts, and historical figures.\n\n'Auto-Detect' will let the AI decide after the first fetch.",
                                timeout = 30
                            })
                        end
                    },
                    { text = self.loc:t("close") or "Close", callback = function() UIManager:close(info_dialog) end }
                }
            }
        }
        UIManager:show(info_dialog)
    end
    
    showSettings()
end

function M:showMentionsSettings()
    local ButtonDialog = require("ui/widget/buttondialog")
    local info_dialog
    
    local function showSettings()
        if info_dialog then UIManager:close(info_dialog) end
        
        local current_setting = self.ai_helper.settings.mentions_enabled ~= false -- default is true
        local enabled_text = self.loc:t("mentions_enabled") or "Enabled"
        local disabled_text = self.loc:t("mentions_disabled") or "Disabled"
        
        local buttons = {
            {
                {
                    text = (current_setting and "[✓] " or "[  ] ") .. enabled_text,
                    callback = function()
                        self.ai_helper:saveSettings({ mentions_enabled = true })
                        UIManager:setDirty(nil, "ui")
                        UIManager:nextTick(function() showSettings() end)
                    end
                },
                {
                    text = ((not current_setting) and "[✓] " or "[  ] ") .. disabled_text,
                    callback = function()
                        self.ai_helper:saveSettings({ mentions_enabled = false })
                        UIManager:setDirty(nil, "ui")
                        UIManager:nextTick(function() showSettings() end)
                    end
                }
            },
            {
                {
                    text = self.loc:t("menu_about") or "About",
                    callback = function()
                        UIManager:show(InfoMessage:new{
                            text = self.loc:t("mentions_setting_desc") or "Mentions scanning allows you to find every occurrence of a character or location in the book. This happens automatically in the background to ensure the reader stays responsive.\n\nDisabling this will stop all background scanning and hide the 'Find Mentions' button.",
                            timeout = 30
                        })
                    end
                },
                {
                    text = self.loc:t("close") or "Close",
                    callback = function()
                        UIManager:close(info_dialog)
                    end
                }
            }
        }
        
        info_dialog = ButtonDialog:new{
            title = self.loc:t("mentions_setting_title") or "Mentions Settings",
            text = self.loc:t("mentions_preference_desc") or "Select your preference for character and location mentions:",
            buttons = buttons,
        }
        UIManager:show(info_dialog)
    end
    
    showSettings()
end

function M:showLinkedEntriesSettings()
    local ButtonDialog = require("ui/widget/buttondialog")
    local InfoMessage = require("ui/widget/infomessage")
    local info_dialog
    
    local function showSettings()
        if info_dialog then UIManager:close(info_dialog) end
        
        local current_setting = self.ai_helper.settings.linked_entries_enabled ~= false -- default is true
        local enabled_text = self.loc:t("linked_entries_enabled") or "Enabled"
        local disabled_text = self.loc:t("linked_entries_disabled") or "Disabled"
        
        local buttons = {
            {
                {
                    text = (current_setting and "[✓] " or "[  ] ") .. enabled_text,
                    callback = function()
                        self.ai_helper:saveSettings({ linked_entries_enabled = true })
                        UIManager:setDirty(nil, "ui")
                        UIManager:nextTick(function() showSettings() end)
                    end
                },
                {
                    text = ((not current_setting) and "[✓] " or "[  ] ") .. disabled_text,
                    callback = function()
                        self.ai_helper:saveSettings({ linked_entries_enabled = false })
                        UIManager:setDirty(nil, "ui")
                        UIManager:nextTick(function() showSettings() end)
                    end
                }
            },
            {
                {
                    text = self.loc:t("menu_about") or "About",
                    callback = function()
                        UIManager:show(InfoMessage:new{
                            text = self.loc:t("linked_entries_setting_desc") or "Linked Entries automatically connects characters, locations, and historical figures when they are mentioned in each other's descriptions.\n\nDisabling this will hide the 'Linked Entries' button from detail dialogs.",
                            timeout = 30
                        })
                    end
                },
                {
                    text = self.loc:t("close") or "Close",
                    callback = function()
                        UIManager:close(info_dialog)
                    end
                }
            }
        }
        
        info_dialog = ButtonDialog:new{
            title = self.loc:t("menu_linked_entries_settings") or "Linked Entries Settings",
            buttons = {
                {
                    {
                        text = (current_setting and "[✓] " or "[  ] ") .. enabled_text,
                        callback = function()
                            self.ai_helper:saveSettings({ linked_entries_enabled = true })
                            UIManager:setDirty(nil, "ui")
                            UIManager:nextTick(function() showSettings() end)
                        end
                    },
                    {
                        text = ((not current_setting) and "[✓] " or "[  ] ") .. disabled_text,
                        callback = function()
                            self.ai_helper:saveSettings({ linked_entries_enabled = false })
                            UIManager:setDirty(nil, "ui")
                            UIManager:nextTick(function() showSettings() end)
                        end
                    }
                },
                {
                    {
                        text = self.loc:t("menu_about") or "About",
                        callback = function()
                            UIManager:show(InfoMessage:new{
                                text = self.loc:t("linked_entries_setting_desc") or "Linked Entries automatically connects characters, locations, and historical figures when they are mentioned in each other's descriptions.\n\nDisabling this will hide the 'Linked Entries' button from detail dialogs.",
                                timeout = 30
                            })
                        end
                    },
                    {
                        text = self.loc:t("close") or "Close",
                        callback = function()
                            UIManager:close(info_dialog)
                        end
                    }
                }
            }
        }
        UIManager:show(info_dialog)
    end
    
    showSettings()
end

function M:showMergeFlow(list, list_name)
    local ButtonDialog = require("ui/widget/buttondialog")
    local ConfirmBox = require("ui/widget/confirmbox")
    local InfoMessage = require("ui/widget/infomessage")
    
    local primary_dialog, secondary_dialog
    
    local function pickSecondary(primary_item)
        local buttons = {}
        for _, item in ipairs(list) do
            if item.name ~= primary_item.name then
                local secondary_name = item.name
                table.insert(buttons, {{
                    text = secondary_name,
                    callback = function()
                        UIManager:close(secondary_dialog)
                        secondary_dialog = nil
                        local confirm = ConfirmBox:new{
                            text = string.format(
                                self.loc:t("merge_confirm") or "Merge %s into %s? The secondary entry will be deleted and its aliases absorbed.",
                                secondary_name, primary_item.name
                            ),
                            ok_text = self.loc:t("yes") or "Yes",
                            cancel_text = self.loc:t("close") or "Close",
                            ok_callback = function()
                                local wait_msg = InfoMessage:new{ text = self.loc:t("merging_smartly") or "Merging...", timeout = 120 }
                                UIManager:show(wait_msg)
                                
                                UIManager:scheduleIn(0.1, function()
                                    local ai_merged_desc = nil
                                    if self.ai_helper and self.ai_helper:hasApiKey() then
                                        local sec_item = nil
                                        for _, it in ipairs(list) do
                                            if it.name == secondary_name then sec_item = it; break end
                                        end
                                        
                                        if sec_item and primary_item.description and sec_item.description then
                                            ai_merged_desc = self.ai_helper:mergeDescriptionsWithAI(primary_item.description, sec_item.description)
                                        end
                                    end
                                    
                                    UIManager:close(wait_msg)
                                    
                                    if self:mergeEntries(list, primary_item.name, secondary_name, ai_merged_desc) then
                                        -- Save cache: load existing, patch only the changed list
                                        if not self.cache_manager then
                                            self.cache_manager = require(plugin_path .. "xray_cachemanager"):new()
                                        end
                                        local cache = self.cache_manager:loadCache(self.ui.document.file) or {}
                                        if list_name == "characters" then
                                            cache.characters = list
                                        elseif list_name == "locations" then
                                            cache.locations = list
                                        end
                                        self.cache_manager:saveCache(self.ui.document.file, cache)
                                        
                                        -- Clear normalized lookup caches so the LookupManager rebuilds them
                                        for _, it in ipairs(list) do
                                            it._norm_name = nil
                                            it._norm_aliases = nil
                                        end
                                        
                                        UIManager:show(InfoMessage:new{
                                            text = self.loc:t("merge_success") or "Entries merged successfully.",
                                            timeout = 3
                                        })
                                        
                                        -- Refresh the list menu
                                        if list_name == "characters" then
                                            self:showCharacters()
                                        elseif list_name == "locations" then
                                            self:showLocations()
                                        end
                                    else
                                        UIManager:show(InfoMessage:new{
                                            text = self.loc:t("merge_failed") or "Merge failed.",
                                            timeout = 3
                                        })
                                    end
                                end)
                            end,
                        }
                        UIManager:show(confirm)
                    end
                }})
            end
        end
        
        table.insert(buttons, {{
            text = self.loc:t("merge_back") or "← Back",
            callback = function()
                UIManager:close(secondary_dialog)
                secondary_dialog = nil
                UIManager:show(primary_dialog)
            end
        }})
        
        secondary_dialog = ButtonDialog:new{
            title = self.loc:t("merge_pick_secondary") or "Choose the entry to REMOVE",
            buttons = buttons
        }
        UIManager:show(secondary_dialog)
    end
    
    local buttons = {}
    for _, item in ipairs(list) do
        local primary_item = item
        table.insert(buttons, {{
            text = item.name,
            callback = function()
                UIManager:close(primary_dialog)
                primary_dialog = nil
                pickSecondary(primary_item)
            end
        }})
    end
    
    table.insert(buttons, {{
        text = self.loc:t("close") or "Close",
        callback = function()
            UIManager:close(primary_dialog)
            primary_dialog = nil
        end
    }})
    
    primary_dialog = ButtonDialog:new{
        title = self.loc:t("merge_pick_primary") or "Choose the entry to KEEP",
        buttons = buttons
    }
    UIManager:show(primary_dialog)
end


function M:showAutoUpdateSettings()
    local ButtonDialog = require("ui/widget/buttondialog")
    local info_dialog
    
    local function showSettings()
        if info_dialog then UIManager:close(info_dialog) end
        local is_enabled = self.auto_fetch_enabled
        local current_cooldown = self.ai_helper.settings and self.ai_helper.settings.auto_fetch_cooldown or 300
        
        info_dialog = ButtonDialog:new{
            title = (self.loc:t("menu_auto_update_frequency") or "Auto X-Ray Settings") .. "\n\n" .. (self.loc:t("auto_update_freq_label") or "Background fetching frequency:"),
            buttons = {
                {
                    {
                        text = (not is_enabled and "[✓] " or "[  ] ") .. (self.loc:t("auto_update_disabled") or "Disabled"),
                        align = "left",
                        callback = function()
                            self.auto_fetch_enabled = false
                            self.ai_helper:saveSettings({ auto_fetch_on_chapter = false })
                            UIManager:nextTick(function() showSettings() end)
                        end
                    }
                },
                {
                    {
                        text = (is_enabled and current_cooldown == 0 and "[✓] " or "[  ] ") .. (self.loc:t("auto_update_aggressive") or "Aggressive: checks every new chapter"),
                        align = "left",
                        callback = function()
                            self.auto_fetch_enabled = true
                            self.ai_helper:saveSettings({ auto_fetch_on_chapter = true, auto_fetch_cooldown = 0 })
                            UIManager:nextTick(function() showSettings() end)
                        end
                    }
                },
                {
                    {
                        text = (is_enabled and current_cooldown == 300 and "[✓] " or "[  ] ") .. (self.loc:t("auto_update_balanced") or "Balanced: checks at most every 5 mins"),
                        align = "left",
                        callback = function()
                            self.auto_fetch_enabled = true
                            self.ai_helper:saveSettings({ auto_fetch_on_chapter = true, auto_fetch_cooldown = 300 })
                            UIManager:nextTick(function() showSettings() end)
                        end
                    }
                },
                {
                    {
                        text = (is_enabled and current_cooldown == 900 and "[✓] " or "[  ] ") .. (self.loc:t("auto_update_economical") or "Economical: checks at most every 15 mins"),
                        align = "left",
                        callback = function()
                            self.auto_fetch_enabled = true
                            self.ai_helper:saveSettings({ auto_fetch_on_chapter = true, auto_fetch_cooldown = 900 })
                            UIManager:nextTick(function() showSettings() end)
                        end
                    }
                },
                {
                    {
                        text = (is_enabled and current_cooldown == 1800 and "[✓] " or "[  ] ") .. (self.loc:t("auto_update_sparse") or "Sparse: checks at most every 30 mins"),
                        align = "left",
                        callback = function()
                            self.auto_fetch_enabled = true
                            self.ai_helper:saveSettings({ auto_fetch_on_chapter = true, auto_fetch_cooldown = 1800 })
                            UIManager:nextTick(function() showSettings() end)
                        end
                    }
                },
                {
                    {
                        text = self.loc:t("menu_about") or "About",
                        callback = function()
                            UIManager:show(InfoMessage:new{
                                text = self.loc:t("auto_update_freq_about") or "Auto-update checks for new chapter data in the background as you read.\n\nLIMITS & PERFORMANCE\nFrequent background requests can drain BATTERY LIFE and may hit AI PROVIDER RATE LIMITS.\n\nMODES\n• Disabled: No background requests\n• Aggressive: Checks every time you enter a new chapter\n• Balanced: Checks at most every 5 minutes (recommended)\n• Economical: Checks at most every 15 minutes\n• Sparse: Checks at most every 30 minutes\n\nNote: skipped chapters will be included in the next update.",
                                timeout = 120
                            })
                        end
                    },
                    {
                        text = self.loc:t("close") or "Close",
                        callback = function()
                            UIManager:close(info_dialog)
                        end
                    }
                }
            }
        }
        UIManager:show(info_dialog)
    end
    
    showSettings()
end

function M:showSpoilerSettings()
    local ButtonDialog = require("ui/widget/buttondialog")
    local info_dialog
    
    local function showSettings()
        if info_dialog then UIManager:close(info_dialog) end
        local current_setting = self.ai_helper.settings and self.ai_helper.settings.spoiler_setting or "spoiler_free"
        
        info_dialog = ButtonDialog:new{
            title = self.loc:t("spoiler_preference_title") or "Spoiler Settings",
            text = self.loc:t("spoiler_preference_desc") or "Select your spoiler preference for X-Ray data:",
            buttons = {
                {
                    {
                        text = (current_setting == "spoiler_free" and "[✓] " or "[  ] ") .. (self.loc:t("spoiler_free_menu_option") or "Spoiler-free"),
                        callback = function()
                            self.ai_helper:saveSettings({ spoiler_setting = "spoiler_free" })
                            UIManager:setDirty(nil, "ui")
                            UIManager:nextTick(function() showSettings() end)
                        end
                    },
                    {
                        text = (current_setting == "full_book" and "[✓] " or "[  ] ") .. (self.loc:t("full_book_option") or "Full Book Mode"),
                        callback = function()
                            self.ai_helper:saveSettings({ spoiler_setting = "full_book" })
                            UIManager:setDirty(nil, "ui")
                            UIManager:nextTick(function() showSettings() end)
                        end
                    }
                },
                {
                    {
                        text = self.loc:t("menu_about") or "About",
                        callback = function()
                            UIManager:show(InfoMessage:new{
                                text = self.loc:t("spoiler_free_about") or "Spoiler-free mode limits AI extraction to the pages you have already read (up to your current page), preventing spoilers from future chapters.\n\nFull Book Mode analyzes the entire book, which may contain spoilers.",
                                timeout = 30
                            })
                        end
                    },
                    {
                        text = self.loc:t("close") or "Close",
                        callback = function()
                            UIManager:close(info_dialog)
                        end
                    }
                }
            }
        }
        UIManager:show(info_dialog)
    end
    
    showSettings()
end

function M:showDescriptionLengthSettings()
    local menu_items = {
        {
            text = self.loc:t("menu_characters"),
            callback = function() self:showEntityLengthPresets("char_desc_len", self.loc:t("menu_characters")) end,
        },
        {
            text = self.loc:t("menu_locations"),
            callback = function() self:showEntityLengthPresets("loc_desc_len", self.loc:t("menu_locations")) end,
        },
        {
            text = self.loc:t("menu_timeline"),
            callback = function() self:showEntityLengthPresets("timeline_event_len", self.loc:t("menu_timeline"), true) end,
        },
        {
            text = self.loc:t("menu_historical_figures"),
            callback = function() self:showEntityLengthPresets("hist_fig_bio_len", self.loc:t("menu_historical_figures")) end,
        },
        {
            text = self.loc:t("menu_terms") or "Glossary",
            callback = function() self:showEntityLengthPresets("term_def_len", self.loc:t("menu_terms") or "Glossary") end,
        },
    }

    local menu = Menu:new{
        title = self.loc:t("menu_desc_length_settings"),
        item_table = menu_items,
    }
    UIManager:show(menu)
end

function M:showEntityLengthPresets(setting_key, entity_name, is_timeline)
    local info_dialog

    local function showSettings()
        if info_dialog then UIManager:close(info_dialog) end

        local s = self.ai_helper and self.ai_helper.settings or {}
        local defaults = {
            char_desc_len    = 200,
            loc_desc_len     = 100,
            timeline_event_len = 80,
            hist_fig_bio_len = 100,
        }
        local current_val = s[setting_key] or (is_timeline and 80 or defaults[setting_key] or 100)

        local presets = {
            { name = self.loc:t("desc_len_short"),      val = is_timeline and 50  or (setting_key == "char_desc_len" and 80  or 50)  },
            { name = self.loc:t("desc_len_default"),    val = is_timeline and 80  or (setting_key == "char_desc_len" and 200 or 100) },
            { name = self.loc:t("desc_len_detailed"),   val = is_timeline and 150 or (setting_key == "char_desc_len" and 350 or 200) },
            { name = self.loc:t("desc_len_v_detailed"), val = is_timeline and 200 or (setting_key == "char_desc_len" and 500 or 300) },
        }

        local buttons = {}
        for _, p in ipairs(presets) do
            local label = (current_val == p.val and "[✓] " or "[  ] ") .. p.name
            local pval = p.val
            table.insert(buttons, {{
                text = label,
                align = "left",
                callback = function()
                    if self.ai_helper then
                        local updates = {}
                        updates[setting_key] = pval
                        self.ai_helper:saveSettings(updates)
                    end
                    UIManager:nextTick(function() showSettings() end)
                end,
            }})
        end

        -- About text varies by entity type
        local about_text
        if is_timeline then
            about_text = self.loc:t("desc_len_about_timeline") or
                "TIMELINE — ONE EVENT PER CHAPTER (always)\n\nTimeline always has exactly one entry per chapter. This setting only affects how much detail is included in each summary.\n\n• Short (~50 chars): Brief one-phrase summary.\n• Default (~80 chars): Standard summary.\n• Detailed (~150 chars): Includes context and consequences.\n• Very Detailed (~200 chars): Full narrative description.\n\nThere is no count trade-off for the timeline."
        elseif setting_key == "char_desc_len" then
            about_text = self.loc:t("desc_len_about_chars") or
                "CHARACTER DESCRIPTIONS\n\n• Short (~80 chars): Name, role, and a brief note.\n• Default (~200 chars): Standard analysis.\n• Detailed (~350 chars): Rich character study with traits and motivations.\n• Very Detailed (~500 chars): Deep analysis.\n\nTRADE-OFF\nLonger descriptions → fewer characters returned during initial/full fetches. Subsequent 'Fetch More' runs are unaffected."
        elseif setting_key == "loc_desc_len" then
            about_text = self.loc:t("desc_len_about_locs") or
                "LOCATION DESCRIPTIONS\n\n• Short (~50 chars): Place name and one-line context.\n• Default (~100 chars): Standard description.\n• Detailed (~200 chars): Atmosphere, significance, and events.\n• Very Detailed (~300 chars): Full description.\n\nTRADE-OFF\nLonger descriptions → fewer locations returned during initial/full fetches."
        else
            about_text = self.loc:t("desc_len_about_hist") or
                "HISTORICAL FIGURE BIOGRAPHIES\n\n• Short (~50 chars): Name and primary role.\n• Default (~100 chars): Standard biography.\n• Detailed (~200 chars): Life, significance, and book context.\n• Very Detailed (~300 chars): Comprehensive biography.\n\nTRADE-OFF\nLonger biographies → fewer historical figures returned during initial/full fetches."
        end

        table.insert(buttons, {
            {
                text = self.loc:t("menu_about") or "About",
                callback = function()
                    UIManager:show(InfoMessage:new{
                        text = about_text,
                        timeout = 120,
                    })
                end,
            },
            {
                text = self.loc:t("close") or "Close",
                callback = function()
                    UIManager:close(info_dialog)
                end,
            },
        })

        info_dialog = ButtonDialog:new{
            title = entity_name .. " — " .. (self.loc:t("menu_desc_length_settings") or "Description Length"),
            buttons = buttons,
        }
        UIManager:show(info_dialog)
    end

    showSettings()
end



function M:showAuthorInfo()
    if not self.author_info or not self.author_info.description or self.author_info.description == "" or self.author_info.description == (self.loc:t("msg_no_bio") or "No biography available.") then
        local ButtonDialog = require("ui/widget/buttondialog")
        local ask_dialog
        ask_dialog = ButtonDialog:new{ title = (self.loc:t("menu_fetch_author") or "Fetch Author Info") .. "\n\n" .. (self.loc:t("no_author_data_fetch") or "No author biography available. Fetch now?"), buttons = {{{ text = self.loc:t("cancel"), callback = function() UIManager:close(ask_dialog) end }, { text = self.loc:t("fetch_button") or "Fetch", is_enter_default = true, callback = function() UIManager:close(ask_dialog); UIManager:nextTick(function() self:fetchAuthorInfo() end) end }}} }
        UIManager:show(ask_dialog); return
    end
    local lines = { "NAME: " .. (self.author_info.name or "Unknown"), "BORN: " .. (self.author_info.birthDate or "---"), "DIED: " .. (self.author_info.deathDate or "---"), "", "BIOGRAPHY:", (self.author_info.description or "No biography available.") }
    UIManager:show(InfoMessage:new{ text = table.concat(lines, "\n"), timeout = 30 })
end

function M:showLocations()
    if not self.locations or #self.locations == 0 then 
        UIManager:show(InfoMessage:new{ text = self.loc:t("no_location_data"), timeout = 3 })
        return 
    end
    local items = {
        { text = "⋈ " .. (self.loc:t("merge_duplicates") or "Merge Duplicates..."), callback = function() self:showMergeFlow(self.locations, "locations") end, separator = true },
    }
    for _, loc in ipairs(self.locations) do 
        if type(loc) == "table" then
            local captured_loc = loc
            local name = loc.name or "???"
            if loc.source == "series_prior" then
                name = name .. " " .. (self.loc:t("series_prior_label") or "[Prior]")
            end
            table.insert(items, {
                text = name,
                keep_menu_open = true,
                callback = function()
                    self:showLocationDetails(captured_loc)
                end
            })
        end
    end
    
    if #items == 0 then
        UIManager:show(InfoMessage:new{ text = self.loc:t("no_location_data"), timeout = 3 })
        return
    end
    
    self.loc_menu = Menu:new{
        title = self.loc:t("menu_locations"),
        item_table = items,
        is_borderless = true,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        on_close_callback = function() 
            if self.is_cancelled then return end
            self:showFullXRayMenu() 
        end,
    }
    UIManager:show(self.loc_menu)
end

function M:showAbout()
    local meta = dofile(self.path .. "/_meta.lua")
    local version = meta.version or "?.?.?"
    local description = self.loc:t("plugin_description") or tostring(meta.description or "")

    local body = (meta.fullname or "X-Ray") .. " v" .. version .. "\n\n" .. description

    UIManager:show(ConfirmBox:new{
        text = body,
        icon = "lightbulb",
        ok_text = self.loc:t("updater_check") or "Check for Updates",
        cancel_text = self.loc:t("close") or "Close",
        ok_callback = function()
            local updater = require(plugin_path .. "xray_updater")
            updater.checkForUpdates(self.loc, self.ai_helper.settings.beta_channel_enabled)
        end,
    })
end

function M:clearCache()
    if not self.cache_manager then self.cache_manager = require(plugin_path .. "xray_cachemanager"):new() end
    self.cache_manager:clearCache(self.ui.document.file)
    self.characters = {}; self.locations = {}; self.timeline = {}; self.historical_figures = {}; self.author_info = nil
    UIManager:show(InfoMessage:new{ text = self.loc:t("cache_cleared"), timeout = 3 })
end

function M:clearLogs()
    local XRayLogger = require(plugin_path .. "xray_logger")
    XRayLogger:clear()
    UIManager:show(InfoMessage:new{ text = self.loc:t("logs_cleared") or "Logs cleared!", timeout = 3 })
end

function M:toggleXRayMode()
    local ButtonDialog = require("ui/widget/buttondialog")
    local info_dialog
    
    local function showSettings()
        if info_dialog then UIManager:close(info_dialog) end
        info_dialog = ButtonDialog:new{
            title = self.loc:t("menu_xray_mode") or "X-Ray Mode Settings",
            text = self.loc:t("xray_mode_desc"),
            buttons = {
                {
                    {
                        text = (self.xray_mode_enabled and "[✓] " or "[  ] ") .. (self.loc:t("xray_enabled_label") or "Enabled"),
                        callback = function()
                            self.xray_mode_enabled = true
                            if self.ai_helper then self.ai_helper:saveSettings({ xray_mode_enabled = true }) end
                            UIManager:setDirty(nil, "ui")
                            UIManager:nextTick(function() showSettings() end)
                        end
                    },
                    {
                        text = (not self.xray_mode_enabled and "[✓] " or "[  ] ") .. (self.loc:t("xray_disabled_label") or "Disabled"),
                        callback = function()
                            self.xray_mode_enabled = false
                            if self.ai_helper then self.ai_helper:saveSettings({ xray_mode_enabled = false }) end
                            UIManager:setDirty(nil, "ui")
                            UIManager:nextTick(function() showSettings() end)
                        end
                    }
                },
                {
                    {
                        text = self.loc:t("menu_about") or "About",
                        callback = function()
                            UIManager:show(InfoMessage:new{
                                text = self.loc:t("xray_mode_desc"),
                                timeout = 30
                            })
                        end
                    },
                    {
                        text = self.loc:t("close") or "Close",
                        callback = function()
                            UIManager:close(info_dialog)
                        end
                    }
                }
            }
        }
        UIManager:show(info_dialog)
    end
    
    showSettings()
end

function M:showTimeline()
    if not self.timeline or #self.timeline == 0 then UIManager:show(InfoMessage:new{ text = self.loc:t("no_timeline_data"), timeout = 3 }); return end
    local toc = self.ui.document:getToc()
    self:assignTimelinePages(self.timeline, toc, true)
    self:sortTimelineByTOC(self.timeline)
    
    local has_prior = false
    for _, ev in ipairs(self.timeline) do
        if ev.source == "series_prior" then
            has_prior = true
            break
        end
    end

    if self.series_prior_timeline_collapsed == nil then
        self.series_prior_timeline_collapsed = true
    end

    local items = {}
    if has_prior then
        local arrow = self.series_prior_timeline_collapsed and "► " or "▼ "
        local header_text = arrow .. (self.loc:t("series_prior_books_header") or "── Prior Books ──")
        table.insert(items, {
            text = header_text,
            keep_menu_open = true,
            callback = function()
                self.series_prior_timeline_collapsed = not self.series_prior_timeline_collapsed
                self:showTimeline()
            end
        })
    end

    for _, ev in ipairs(self.timeline) do
        if ev.source == "series_prior" then
            if not self.series_prior_timeline_collapsed then
                table.insert(items, {
                    text = ev.chapter or "",
                    keep_menu_open = true,
                    callback = function()
                        local TextViewer = require("ui/widget/textviewer")
                        local text_viewer = TextViewer:new{
                            title = ev.chapter or "Prior Book Summary",
                            text = ev.event or "",
                            text_type = "book_info",
                        }
                        UIManager:show(text_viewer)
                    end
                })
            end
        else
            table.insert(items, {
                text = (ev.chapter or "") .. ": " .. (ev.event or ""),
                keep_menu_open = true,
                callback = function()
                    local TextViewer = require("ui/widget/textviewer")
                    local text_viewer = TextViewer:new{
                        title = ev.chapter or "Event Summary",
                        text = ev.event or "",
                        text_type = "book_info",
                    }
                    UIManager:show(text_viewer)
                end
            })
        end
    end

    if self.timeline_menu then
        UIManager:close(self.timeline_menu)
        self.timeline_menu = nil
    end

    self.timeline_menu = Menu:new{ 
        title = self.loc:t("menu_timeline"), 
        item_table = items, 
        is_borderless = true, 
        width = Screen:getWidth(), 
        height = Screen:getHeight(),
        on_close_callback = function() 
            if self.is_cancelled then return end
            self:showFullXRayMenu() 
        end,
    }
    UIManager:show(self.timeline_menu)
end

function M:showHistoricalFigureDetails(fig)
    local name = fig.name or "???"
    local bio = fig.biography or (self.loc:t("msg_no_bio") or "No biography available.")
    local body_text = name .. "\n\n" .. bio
    local linked_enabled = self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.linked_entries_enabled ~= false
    local related = linked_enabled and self:findRelatedEntities(bio, name) or {}
    local mentions_enabled = self.ai_helper and self.ai_helper.settings and self.ai_helper.settings.mentions_enabled ~= false
    
    if #related > 0 then
        local buttons = {
            {
                {
                    text = self.loc:t("linked_entries") or "Linked Entries",
                    callback = function()
                        self:showRelatedEntities(related)
                    end,
                }
            },
            {
                {
                    text = self.loc:t("find_mentions") or "Find Mentions",
                    callback = function()
                        if self.active_details_dialog then UIManager:close(self.active_details_dialog); self.active_details_dialog = nil end
                        self:showMentionsForEntity(fig)
                    end,
                },
                {
                    text = self.loc:t("close") or "Close",
                    callback = function()
                        if self.active_details_dialog then UIManager:close(self.active_details_dialog) end
                        self.active_details_dialog = nil
                    end,
                }
            }
        }
        
        if not mentions_enabled then
            table.remove(buttons[2], 1)
        end
        
        self.active_details_dialog = ButtonDialog:new{
            title = body_text,
            buttons = buttons,
        }
    else
        if mentions_enabled then
            self.active_details_dialog = ConfirmBox:new{
                text = body_text,
                icon = "info",
                ok_text = self.loc:t("find_mentions") or "Find Mentions",
                cancel_text = self.loc:t("close") or "Close",
                ok_callback = function()
                    if self.active_details_dialog then UIManager:close(self.active_details_dialog); self.active_details_dialog = nil end
                    self:showMentionsForEntity(fig)
                end,
                cancel_callback = function()
                    self.active_details_dialog = nil
                end,
            }
        else
            self.active_details_dialog = ConfirmBox:new{
                text = body_text,
                icon = "info",
                ok_text = self.loc:t("close") or "Close",
                ok_callback = function() self.active_details_dialog = nil end,
                cancel_callback = function() self.active_details_dialog = nil end,
            }
        end
    end
    UIManager:show(self.active_details_dialog)
end

function M:showHistoricalFigures()
    if not self.historical_figures or #self.historical_figures == 0 then 
        UIManager:show(InfoMessage:new{ text = self.loc:t("no_historical_data"), timeout = 3 })
        return 
    end
    local items = {}
    for _, fig in ipairs(self.historical_figures) do
        table.insert(items, {
            text = (fig.name or "???"),
            keep_menu_open = true,
            callback = function()
                self:showHistoricalFigureDetails(fig)
            end,
        })
    end

    self.hf_menu = Menu:new{
        title = self.loc:t("menu_historical_figures"), 
        item_table = items, 
        is_borderless = true, 
        width = Screen:getWidth(), 
        height = Screen:getHeight(),
        on_close_callback = function() 
            if self.is_cancelled then return end
            self:showFullXRayMenu() 
        end,
    }
    UIManager:show(self.hf_menu)
end

function M:showQuickXRayMenu() self:showFullXRayMenu() end
function M:showFullXRayMenu()
    if self.xray_menu then UIManager:close(self.xray_menu); self.xray_menu = nil end
    self.xray_menu = Menu:new{ 
        title = self.loc:t("menu_xray") or "X-Ray", 
        item_table = self:getSubMenuItems(), 
        is_borderless = true, 
        width = Screen:getWidth(), 
        height = Screen:getHeight() 
    }
    UIManager:show(self.xray_menu) 
end

function M:getAPIKeysMenu()
    local menu_items = {}
    local providers = {
        { id = "gemini", name = "Google Gemini" },
        { id = "chatgpt", name = "OpenAI ChatGPT" },
        { id = "deepseek", name = "DeepSeek" },
        { id = "claude", name = "Anthropic Claude" },
        { id = "custom1", name = self.loc:t("custom_api_name") and string.format(self.loc:t("custom_api_name"), 1) or "Custom API 1 (OpenAI-compatible)" },
        { id = "custom2", name = self.loc:t("custom_api_name") and string.format(self.loc:t("custom_api_name"), 2) or "Custom API 2 (OpenAI-compatible)" },
    }
    for _, p in ipairs(providers) do
        local prov_data = self.ai_helper.providers[p.id]
        if prov_data then
            local active_val = prov_data.api_key or ""
            local status
            if p.id:find("custom") then
                local endpoint = prov_data.endpoint or ""
                local host = endpoint:match("^https?://([^/]+)") or endpoint
                local model = prov_data.model or ""
                if host ~= "" or model ~= "" then
                    status = (host ~= "" and host or "?") .. " | " .. (model ~= "" and model or "?")
                else
                    status = self.loc:t("custom_api_not_configured") or "(not configured — tap to set up)"
                end
            else
                status = (active_val ~= "") and (active_val:sub(1,6) .. "...") or "(None)"
            end
            local source = prov_data.ui_key_active and "[UI]" or "[Config]"
            
            table.insert(menu_items, {
                text = p.name .. " " .. source .. ": " .. status,
                keep_menu_open = true,
                sub_item_table_func = function() return self:getProviderKeySubMenu(p.id, p.name) end
            })
        end
    end
    return menu_items
end

function M:getProviderKeySubMenu(provider, provider_name)
    local config_key = (self.ai_helper and self.ai_helper.config_keys) and self.ai_helper.config_keys[provider] or ""
    local ui_key = (self.ai_helper and self.ai_helper.settings) and self.ai_helper.settings[provider .. "_api_key"] or ""
    
    local menu_items = {
        {
            text = "Use key from config.lua: " .. (#config_key > 0 and (config_key:sub(1,6) .. "...") or "(Not set)"),
            checked_func = function() 
                if not self.ai_helper or not self.ai_helper.providers or not self.ai_helper.providers[provider] then return false end
                return not self.ai_helper.providers[provider].ui_key_active 
            end,
            callback = function()
                self.ai_helper:saveSettings({ [provider .. "_use_ui_key"] = false })
                self.ai_helper:init(self.path)
                UIManager:setDirty(nil, "ui")
            end
        },
        {
            text = "Use UI override key: " .. (#ui_key > 0 and (ui_key:sub(1,6) .. "...") or "(Not set)"),
            checked_func = function() 
                if not self.ai_helper or not self.ai_helper.providers or not self.ai_helper.providers[provider] then return false end
                return self.ai_helper.providers[provider].ui_key_active 
            end,
            callback = function()
                -- If we have a UI key but it's not currently active, let's just activate it
                if #ui_key > 0 and not self.ai_helper.providers[provider].ui_key_active then
                    self.ai_helper:saveSettings({ [provider .. "_use_ui_key"] = true })
                    self.ai_helper:init(self.path)
                    UIManager:setDirty(nil, "ui")
                    return
                end

                if provider:find("custom") then
                    local InputDialog = require("ui/widget/inputdialog")
                    local InfoMessage = require("ui/widget/infomessage")
                    
                    local function promptModel(endpoint, key)
                        local current_model = (self.ai_helper and self.ai_helper.settings) and self.ai_helper.settings[provider .. "_model"] or ""
                        local model_dialog
                        model_dialog = InputDialog:new{
                            title = self.loc:t("custom_api_model_title") and string.format(self.loc:t("custom_api_model_title"), provider:sub(-1)) or ("Custom API " .. provider:sub(-1) .. " — Default Model"),
                            input = current_model,
                            input_hint = self.loc:t("custom_api_model_hint") or "e.g., google/gemini-2.5-flash or openai/gpt-4o",
                            buttons = {
                                {
                                    { text = self.loc:t("cancel"), callback = function() UIManager:close(model_dialog) end },
                                    { text = self.loc:t("save"), is_enter_default = true, callback = function()
                                        local model = model_dialog:getInputText()
                                        UIManager:close(model_dialog)
                                        self.ai_helper:setCustomAPIConfig(provider, key, endpoint, model)
                                        self.ai_helper:init(self.path)
                                        UIManager:show(InfoMessage:new{ text = self.loc:t("custom_api_saved") and string.format(self.loc:t("custom_api_saved"), provider:sub(-1)) or ("Custom API " .. provider:sub(-1) .. " configuration saved."), timeout = 3 })
                                        UIManager:setDirty(nil, "ui")
                                    end }
                                }
                            }
                        }
                        UIManager:show(model_dialog)
                        model_dialog:onShowKeyboard()
                    end

                    local function promptKey(endpoint)
                        local key_dialog
                        key_dialog = InputDialog:new{
                            title = self.loc:t("custom_api_key_title") and string.format(self.loc:t("custom_api_key_title"), provider:sub(-1)) or ("Custom API " .. provider:sub(-1) .. " — API Key"),
                            input = ui_key,
                            buttons = {
                                {
                                    { text = self.loc:t("cancel"), callback = function() UIManager:close(key_dialog) end },
                                    { text = self.loc:t("next") or "Next", is_enter_default = true, callback = function()
                                        local key = key_dialog:getInputText()
                                        UIManager:close(key_dialog)
                                        promptModel(endpoint, key)
                                    end }
                                }
                            }
                        }
                        UIManager:show(key_dialog)
                        key_dialog:onShowKeyboard()
                    end

                    local function promptEndpoint()
                        local current_endpoint = (self.ai_helper and self.ai_helper.settings) and self.ai_helper.settings[provider .. "_endpoint"] or "https://openrouter.ai/api/v1/chat/completions"
                        local endpoint_dialog
                        endpoint_dialog = InputDialog:new{
                            title = self.loc:t("custom_api_endpoint_title") and string.format(self.loc:t("custom_api_endpoint_title"), provider:sub(-1)) or ("Custom API " .. provider:sub(-1) .. " — Endpoint URL"),
                            input = current_endpoint,
                            input_hint = self.loc:t("custom_api_endpoint_hint") or "e.g., https://openrouter.ai/api/v1/chat/completions",
                            buttons = {
                                {
                                    { text = self.loc:t("cancel"), callback = function() UIManager:close(endpoint_dialog) end },
                                    { text = self.loc:t("next") or "Next", is_enter_default = true, callback = function()
                                        local endpoint = endpoint_dialog:getInputText()
                                        UIManager:close(endpoint_dialog)
                                        promptKey(endpoint)
                                    end }
                                }
                            }
                        }
                        UIManager:show(endpoint_dialog)
                        endpoint_dialog:onShowKeyboard()
                    end
                    
                    promptEndpoint()
                    return
                end

                local InputDialog = require("ui/widget/inputdialog")
                local input_dialog
                input_dialog = InputDialog:new{
                    title = provider_name .. " API Key",
                    input = ui_key,
                    buttons = {
                        {
                            { text = self.loc:t("cancel"), callback = function() UIManager:close(input_dialog) end },
                            { text = self.loc:t("save"), is_enter_default = true, callback = function()
                                local key = input_dialog:getInputText()
                                UIManager:close(input_dialog)
                                if key and #key > 0 then
                                    self.ai_helper:saveSettings({ 
                                        [provider .. "_api_key"] = key,
                                        [provider .. "_use_ui_key"] = true
                                    })
                                    self.ai_helper:init(self.path)
                                    UIManager:setDirty(nil, "ui")
                                end
                            end }
                        }
                    }
                }
                UIManager:show(input_dialog)
                input_dialog:onShowKeyboard()
            end
        }
    }

    -- For custom slots: add a toggle to mark the model as a reasoning model.
    -- When enabled, the plugin raises the output token ceiling to 32000 to accommodate
    -- reasoning chains that would otherwise consume the entire output budget.
    if provider:find("custom") then
        table.insert(menu_items, {
            text = self.loc:t("custom_api_is_reasoning") or "Is Reasoning Model (e.g. DeepSeek-R1)",
            keep_menu_open = true,
            checked_func = function()
                return (self.ai_helper and self.ai_helper.settings) and self.ai_helper.settings[provider .. "_is_reasoning"] or false
            end,
            callback = function()
                local current = (self.ai_helper and self.ai_helper.settings) and self.ai_helper.settings[provider .. "_is_reasoning"] or false
                self.ai_helper:saveSettings({ [provider .. "_is_reasoning"] = not current })
                UIManager:setDirty(nil, "ui")
            end
        })
    end

    return menu_items
end

function M:getAIModelSelectionMenu(setting_type)
    local providers = {
        {
            id = "gemini",
            display_name = "Gemini",
            models = {
                { id = "gemini-3.5-flash", cost = "free" },
                { id = "gemini-3.1-flash-lite", cost = "free" },
                { id = "gemini-2.5-flash", cost = "free" },
                { id = "gemini-2.5-flash-lite", cost = "free" },
                { id = "gemini-2.5-pro", cost = "paid" },
            }
        },
        {
            id = "chatgpt",
            display_name = "ChatGPT",
            models = {
                { id = "gpt-5.5", cost = "paid" },
                { id = "gpt-5.4-mini", cost = "paid" },
                { id = "gpt-5.4-nano", cost = "paid" },
            }
        },
        {
            id = "deepseek",
            display_name = "DeepSeek",
            models = {
                { id = "deepseek-chat", cost = "paid" },
                { id = "deepseek-reasoner", cost = "paid" },
            }
        },
        {
            id = "claude",
            display_name = "Claude",
            models = {
                { id = "claude-sonnet-4-6", cost = "paid" },
                { id = "claude-haiku-4-5", cost = "paid" },
            }
        }
    }
    
    local custom1_model = (self.ai_helper and self.ai_helper.settings) and self.ai_helper.settings.custom1_model or nil
    local custom2_model = (self.ai_helper and self.ai_helper.settings) and self.ai_helper.settings.custom2_model or nil
    
    local menu_items = {}
    
    for _, p in ipairs(providers) do
        local provider_id = p.id
        local provider_name = p.display_name
        local provider_models = p.models
        table.insert(menu_items, {
            text = provider_name,
            keep_menu_open = true,
            checked_func = function()
                if not self.ai_helper or not self.ai_helper.settings then return false end
                local current = setting_type == "primary" and self.ai_helper.settings.primary_ai or self.ai_helper.settings.secondary_ai
                if type(current) ~= "table" then return false end
                return current.provider == provider_id
            end,
            sub_item_table_func = function()
                local sub_items = {}
                for _, m in ipairs(provider_models) do
                    local model_id = m.id
                    local model_cost = m.cost
                    table.insert(sub_items, {
                        text = model_id .. " [" .. (model_cost == "free" and self.loc:t("model_free") or self.loc:t("model_paid")) .. "]",
                        checked_func = function()
                            if not self.ai_helper or not self.ai_helper.settings then return false end
                            local current = setting_type == "primary" and self.ai_helper.settings.primary_ai or self.ai_helper.settings.secondary_ai
                            if type(current) ~= "table" then return false end
                            return current.provider == provider_id and current.model == model_id
                        end,
                        callback = function()
                            self.ai_helper:setUnifiedModel(setting_type, provider_id, model_id)
                            UIManager:setDirty(nil, "ui")
                        end
                    })
                end
                return sub_items
            end
        })
    end
    
    table.insert(menu_items, {
        text = "Custom API 1: " .. (custom1_model or "(configure in API Keys)"),
        checked_func = function()
            if not self.ai_helper or not self.ai_helper.settings then return false end
            local current = setting_type == "primary" and self.ai_helper.settings.primary_ai or self.ai_helper.settings.secondary_ai
            if type(current) ~= "table" then return false end
            return current.provider == "custom1" and current.model == (custom1_model or "custom1")
        end,
        callback = function()
            self.ai_helper:setUnifiedModel(setting_type, "custom1", custom1_model or "custom1")
            UIManager:setDirty(nil, "ui")
        end
    })
    table.insert(menu_items, {
        text = "Custom API 2: " .. (custom2_model or "(configure in API Keys)"),
        checked_func = function()
            if not self.ai_helper or not self.ai_helper.settings then return false end
            local current = setting_type == "primary" and self.ai_helper.settings.primary_ai or self.ai_helper.settings.secondary_ai
            if type(current) ~= "table" then return false end
            return current.provider == "custom2" and current.model == (custom2_model or "custom2")
        end,
        callback = function()
            self.ai_helper:setUnifiedModel(setting_type, "custom2", custom2_model or "custom2")
            UIManager:setDirty(nil, "ui")
        end,
        separator = true
    })
    table.insert(menu_items, {
        text = self.loc:t("menu_enter_custom_model") or "Enter custom model...",
        keep_menu_open = true,
        callback = function()
            local InputDialog = require("ui/widget/inputdialog")
            local input_dialog
            local current = (self.ai_helper and self.ai_helper.settings) and (setting_type == "primary" and self.ai_helper.settings.primary_ai or self.ai_helper.settings.secondary_ai) or nil
            input_dialog = InputDialog:new{
                title = (self.loc:t("menu_custom_model_title") or "Custom %s Model"):format(setting_type:gsub("^%l", string.upper)),
                input = current and current.model or "",
                input_hint = "e.g., gemini-2.5-pro",
                buttons = {
                    {
                        {
                            text = self.loc:t("cancel") or "Cancel",
                            callback = function() UIManager:close(input_dialog) end
                        },
                        {
                            text = self.loc:t("save") or "Save",
                            is_enter_default = true,
                            callback = function()
                                local custom_model = input_dialog:getInputText()
                                if custom_model and #custom_model > 0 then
                                    local provider = string.find(custom_model, "gpt") and "chatgpt" or "custom1"
                                    if string.find(custom_model, "deepseek") then provider = "deepseek" end
                                    if string.find(custom_model, "claude") then provider = "claude" end
                                    if string.find(custom_model, "gemini") then provider = "gemini" end
                                    self.ai_helper:setUnifiedModel(setting_type, provider, custom_model)
                                    UIManager:show(InfoMessage:new{ text = setting_type:gsub("^%l", string.upper) .. " AI set to " .. custom_model, timeout = 3 })
                                    UIManager:setDirty(nil, "ui")
                                end
                                UIManager:close(input_dialog)
                            end
                        }
                    }
                }
            }
            UIManager:show(input_dialog)
            input_dialog:onShowKeyboard()
        end
    })
    
    return menu_items
end

function M:findCharacterByName(word)
    if not self.characters or not word then return nil end
    local word_lower = string.lower(word)
    for _, char in ipairs(self.characters) do
        local name_lower = string.lower(char.name or "")
        if name_lower == word_lower or string.find(name_lower, word_lower, 1, true) then
            return char
        end
        -- Also check aliases if primary name doesn't match
        if char.aliases and type(char.aliases) == "table" then
            for _, alias in ipairs(char.aliases) do
                local alias_lower = string.lower(tostring(alias))
                if alias_lower == word_lower or string.find(alias_lower, word_lower, 1, true) then
                    return char
                end
            end
        end
    end
    return nil
end

function M:showCharacterSearch()
    if not self.characters or #self.characters == 0 then UIManager:show(InfoMessage:new{ text = self.loc:t("no_character_data"), timeout = 3 }); return end
    local InputDialog = require("ui/widget/inputdialog")
    local input_dialog
    input_dialog = InputDialog:new{ title = self.loc:t("search_character_title"), input = "", input_hint = self.loc:t("search_hint"), buttons = {{{ text = self.loc:t("cancel"), callback = function() UIManager:close(input_dialog) end }, { text = self.loc:t("search_button"), is_enter_default = true, callback = function() local search_text = input_dialog:getInputText(); UIManager:close(input_dialog); if search_text and #search_text > 0 then local found_char = self:findCharacterByName(search_text); if found_char then self:showCharacterDetails(found_char) else UIManager:show(InfoMessage:new{ text = self.loc:t("character_not_found", search_text), timeout = 3 }) end end end }}} }
    UIManager:show(input_dialog); input_dialog:onShowKeyboard()
end

function M:showConfigSummary()
    local text = (self.loc:t("menu_config_header") or "--- Current Configuration ---") .. "\n\n"
    
    local primary = (self.ai_helper and self.ai_helper.settings) and self.ai_helper.settings.primary_ai or nil
    local secondary = (self.ai_helper and self.ai_helper.settings) and self.ai_helper.settings.secondary_ai or nil
    
    local primary_label = self.loc:t("menu_primary_ai_model") or "Primary AI Model"
    local secondary_label = self.loc:t("menu_secondary_ai_model") or "Secondary AI Model"
    local provider_label = self.loc:t("config_provider") or "  Provider: "
    local model_label = self.loc:t("config_model") or "  Model: "
    local default_label = self.loc:t("config_default_gemini") or "  Default (Gemini)"
    local set_label = self.loc:t("config_status_set") or "SET"
    local not_set_label = self.loc:t("config_status_not_set") or "NOT SET"

    text = text .. primary_label .. ":\n"
    if primary then 
        text = text .. provider_label .. primary.provider .. "\n" .. model_label .. primary.model .. "\n\n" 
    else 
        text = text .. default_label .. "\n\n" 
    end
    
    text = text .. secondary_label .. ":\n"
    if secondary then 
        text = text .. provider_label .. secondary.provider .. "\n" .. model_label .. secondary.model .. "\n\n" 
    else 
        text = text .. default_label .. "\n\n" 
    end
    
    local function add(p, n)
        local c = self.ai_helper.providers[p]
        local key_label = (self.loc:t("config_api_key_label") or "%s API Key: "):format(n)
        text = text .. key_label .. ((c.api_key and #c.api_key > 0) and set_label or not_set_label) .. "\n"
    end
    add("gemini", "Google Gemini"); add("chatgpt", "ChatGPT")
    add("deepseek", "DeepSeek"); add("claude", "Anthropic Claude")
    add("custom1", "Custom API 1"); add("custom2", "Custom API 2")
    
    UIManager:show(InfoMessage:new{ text = text, timeout = 15 })
end

function M:showReasoningEffortSettings()
    local ButtonDialog = require("ui/widget/buttondialog")
    local info_dialog
    
    local function showSettings()
        if info_dialog then UIManager:close(info_dialog) end
        local current = self.ai_helper.settings and self.ai_helper.settings.reasoning_effort or "none"
        
        info_dialog = ButtonDialog:new{
            title = self.loc:t("menu_reasoning_effort") or "AI Model Reasoning Effort",
            text = "Controls internal 'thinking' time for supported reasoning models.",
            buttons = {
                {
                    {
                        text = (current == "none" and "[✓] " or "[  ] ") .. (self.loc:t("reasoning_unset") or "Unset (Default)"),
                        callback = function()
                            self.ai_helper.settings.reasoning_effort = nil
                            self.ai_helper:saveSettings()
                            UIManager:nextTick(function() showSettings() end)
                        end
                    }
                },
                {
                    {
                        text = (current == "low" and "[✓] " or "[  ] ") .. (self.loc:t("reasoning_low") or "Low"),
                        callback = function()
                            self.ai_helper:saveSettings({ reasoning_effort = "low" })
                            UIManager:nextTick(function() showSettings() end)
                        end
                    },
                    {
                        text = (current == "medium" and "[✓] " or "[  ] ") .. (self.loc:t("reasoning_medium") or "Medium"),
                        callback = function()
                            self.ai_helper:saveSettings({ reasoning_effort = "medium" })
                            UIManager:nextTick(function() showSettings() end)
                        end
                    }
                },
                {
                    {
                        text = (current == "high" and "[✓] " or "[  ] ") .. (self.loc:t("reasoning_high") or "High"),
                        callback = function()
                            self.ai_helper:saveSettings({ reasoning_effort = "high" })
                            UIManager:nextTick(function() showSettings() end)
                        end
                    },
                },
                {
                    {
                        text = self.loc:t("about") or "About",
                        callback = function()
                            UIManager:show(InfoMessage:new{
                                text = self.loc:t("reasoning_about") or "Controls 'thinking' depth for reasoning models:\n\n• Unset: No specific instruction sent; model uses its internal defaults.\n• Low: Fast, economical extraction for simple books.\n• Medium: Balanced depth for most narratives.\n• High: Detailed analysis for complex character webs.\n\nApplies to: GPT-5.x, DeepSeek Reasoner, Claude 4.5+ (extended thinking), and Gemini 2.5+.",
                                timeout = 12
                            })
                        end
                    },
                    {
                        text = self.loc:t("close") or "Close",
                        callback = function()
                            UIManager:close(info_dialog)
                        end
                    }
                }
            }
        }
        UIManager:show(info_dialog)
    end
    
    showSettings()
end

function M:showBetaChannelSettings()
    local ButtonDialog = require("ui/widget/buttondialog")
    local info_dialog
    
    local function showSettings()
        if info_dialog then UIManager:close(info_dialog) end
        
        local current_setting = self.ai_helper.settings.beta_channel_enabled == true
        local enabled_text = self.loc:t("beta_enabled") or "Beta Channel Enabled"
        local disabled_text = self.loc:t("beta_disabled") or "Stable Channel (Recommended)"
        
        local buttons = {
            {
                {
                    text = (current_setting and "[✓] " or "[  ] ") .. enabled_text,
                    callback = function()
                        self.ai_helper:saveSettings({ beta_channel_enabled = true })
                        UIManager:nextTick(function() showSettings() end)
                    end
                },
                {
                    text = ((not current_setting) and "[✓] " or "[  ] ") .. disabled_text,
                    callback = function()
                        self.ai_helper:saveSettings({ beta_channel_enabled = false })
                        UIManager:nextTick(function() showSettings() end)
                    end
                }
            },
            {
                {
                    text = self.loc:t("menu_about") or "About",
                    callback = function()
                        UIManager:show(InfoMessage:new{
                            text = self.loc:t("beta_channel_desc") or "The beta channel allows you to receive pre-release versions of the X-Ray plugin. These versions include the latest features and bug fixes but may be less stable than the regular release.",
                            timeout = 30
                        })
                    end
                },
                {
                    text = self.loc:t("close") or "Close",
                    callback = function()
                        UIManager:close(info_dialog)
                    end
                }
            }
        }
        
        info_dialog = ButtonDialog:new{
            title = self.loc:t("menu_beta_channel") or "Beta Channel Settings",
            text = self.loc:t("beta_preference_desc") or "Select your update channel preference:",
            buttons = buttons,
        }
        UIManager:show(info_dialog)
    end
    
    showSettings()
end

function M:checkWeeklyUpdate()
    if not self.ai_helper or not self.ai_helper.settings then return end
    
    local last_check = self.ai_helper.settings.last_update_check or 0
    local now = os.time()
    local week_seconds = 7 * 24 * 60 * 60
    
    if (now - last_check) > week_seconds then
        local NetworkMgr = require("ui/network/manager")
        if NetworkMgr:isOnline() then
            self:log("XRayPlugin: Triggering weekly silent update check")
            self.ai_helper:saveSettings({ last_update_check = now })
            local updater = require(plugin_path .. "xray_updater")
            updater.checkSilentForUpdates(self.loc, self.ai_helper.settings.beta_channel_enabled)
        else
            self:log("XRayPlugin: Skipping weekly update check (offline)")
        end
    end
end

function M:toggleSeriesContextEnabled()
    if not self.ai_helper or not self.ai_helper.settings then return end
    local current = not not self.ai_helper.settings.series_context_enabled
    self.ai_helper.settings.series_context_enabled = not current
    self.ai_helper:saveSettings({ series_context_enabled = not current })
    UIManager:setDirty(nil, "ui")
end

function M:manualFetchSeriesContext()
    local ButtonDialog = require("ui/widget/buttondialog")
    local cancel_ref = { cancelled = false }
    local wait_dialog
    wait_dialog = ButtonDialog:new{
        title = self.loc:t("fetching_series_info") or "Identifying series books…",
        buttons = {{{
            text = self.loc:t("cancel") or "Cancel",
            callback = function()
                cancel_ref.cancelled = true
                self:log("XRayPlugin: Series: User cancelled series fetch before launch.")
                UIManager:close(wait_dialog)
            end
        }}}
    }
    UIManager:show(wait_dialog)
    UIManager:nextTick(function()
        if cancel_ref.cancelled then
            self:log("XRayPlugin: Series: nextTick fired after user already cancelled fetch.")
            return
        end
        self:fetchSeriesContext(false, wait_dialog, cancel_ref)
    end)
end

function M:checkSeriesContext()
    self:log("XRayPlugin: Series: checkSeriesContext starting")
    if not self.ui or not self.ui.document then
        self:log("XRayPlugin: Series: checkSeriesContext: document/ui not available, skipping")
        return
    end

    if not self.ai_helper or not self.ai_helper.settings or not self.ai_helper.settings.series_context_enabled then
        self:log("XRayPlugin: Series: checkSeriesContext: series_context_enabled setting is false/nil, skipping")
        return
    end

    if self.book_data and (self.book_data.series_context_loaded or self.book_data.series_context_dismissed) then
        self:log("XRayPlugin: Series: checkSeriesContext: series context is already loaded or dismissed, skipping")
        return
    end

    local NetworkMgr = require("ui/network/manager")
    if not NetworkMgr:isOnline() then
        self:log("XRayPlugin: Series: checkSeriesContext: device is offline. Scheduling check when online.")
        NetworkMgr:runWhenOnline(function()
            self:log("XRayPlugin: Series: checkSeriesContext: Network is online now. Triggering check in 5 seconds.")
            UIManager:scheduleIn(5, function()
                self:checkSeriesContext()
            end)
        end)
        return
    end

    local props = self.ui.document:getProps() or {}
    local function sanitizeMetadata(val)
        if type(val) == "string" then return val
        elseif type(val) == "table" then return table.concat(val, ", ")
        else return "Unknown" end
    end
    local title = sanitizeMetadata(props.title)
    local author = sanitizeMetadata(props.authors)

    self:log("XRayPlugin: Series: checkSeriesContext: checking book title=" .. tostring(title) .. ", author=" .. tostring(author))

    local series_info = self.series_manager:detectSeries(props, title, author, self.ai_helper)
    if not series_info or not series_info.name or not series_info.index or series_info.index <= 1 then
        self:log("XRayPlugin: Series: checkSeriesContext: No series detected or index is <= 1, skipping")
        return
    end

    self:log("XRayPlugin: Series: checkSeriesContext: Series detected: " .. series_info.name .. ", index=" .. tostring(series_info.index) .. ". Showing prompt dialog.")

    local body_text = string.format(
        self.loc:t("series_context_prompt_text") or "This appears to be Book %d of '%s'. Load a recap of the previous %d book(s)?\n\n(You can disable this in Settings → Series Context)",
        series_info.index,
        series_info.name,
        series_info.index - 1
    )

    local confirm
    confirm = ButtonDialog:new{
        title = (self.loc:t("series_context_prompt_title") or "Series Detected") .. "\n\n" .. body_text,
        buttons = {
            {
                {
                    text = self.loc:t("yes") or "Yes",
                    is_enter_default = true,
                    callback = function()
                        self:log("XRayPlugin: Series: User chose YES on series context prompt.")
                        UIManager:close(confirm)
                        
                        local cancel_ref = { cancelled = false }
                        local wait_dialog
                        wait_dialog = ButtonDialog:new{
                            title = self.loc:t("fetching_series_info") or "Identifying series books…",
                            buttons = {{{
                                text = self.loc:t("cancel") or "Cancel",
                                callback = function()
                                    cancel_ref.cancelled = true
                                    self:log("XRayPlugin: Series: User cancelled series fetch before launch.")
                                    UIManager:close(wait_dialog)
                                end
                            }}}
                        }
                        UIManager:show(wait_dialog)
                        
                        UIManager:nextTick(function()
                            if cancel_ref.cancelled then
                                self:log("XRayPlugin: Series: nextTick fired after user already cancelled fetch.")
                                return
                            end
                            self:fetchSeriesContext(false, wait_dialog, cancel_ref)
                        end)
                    end,
                },
                {
                    text = self.loc:t("later") or "Later",
                    callback = function()
                        self:log("XRayPlugin: Series: User chose LATER on series context prompt.")
                        UIManager:close(confirm)
                        local ask_later_msg = self.loc:t("series_ask_later_msg") or "Series recap postponed. We will ask again when you open/resume this book."
                        UIManager:show(InfoMessage:new{
                            text = ask_later_msg,
                            timeout = 5
                        })
                    end,
                },
                {
                    text = self.loc:t("dont_ask_again") or "Don't ask again",
                    callback = function()
                        self:log("XRayPlugin: Series: User chose DONT_ASK_AGAIN on series context prompt.")
                        UIManager:close(confirm)
                        if not self.cache_manager then
                            self.cache_manager = require(plugin_path .. "xray_cachemanager"):new()
                        end
                        local cache = self.cache_manager:loadCache(self.ui.document.file) or {}
                        cache.series_context_dismissed = true
                        self.cache_manager:saveCache(self.ui.document.file, cache)
                        self.book_data = cache
                        local disabled_msg = self.loc:t("series_disabled_msg") or "Auto-prompt disabled for this book. You can manually fetch recap from X-Ray menu."
                        UIManager:show(InfoMessage:new{
                            text = disabled_msg,
                            timeout = 5
                        })
                    end,
                }
            }
        }
    }
    UIManager:show(confirm)
end

return M
