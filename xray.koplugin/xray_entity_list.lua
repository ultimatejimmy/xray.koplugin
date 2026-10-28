-- xray_entity_list.lua — Full-screen modern entity & timeline list overlay for KOReader X-Ray
-- Implements Storefront-style compact cards, Feather icon header toolbar, pagination, and sorting.

local UIManager       = require("ui/uimanager")
local InputContainer  = require("ui/widget/container/inputcontainer")
local FrameContainer  = require("ui/widget/container/framecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local LeftContainer   = require("ui/widget/container/leftcontainer")
local RightContainer  = require("ui/widget/container/rightcontainer")
local OverlapGroup    = require("ui/widget/overlapgroup")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local VerticalGroup   = require("ui/widget/verticalgroup")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local LineWidget      = require("ui/widget/linewidget")
local TextWidget      = require("ui/widget/textwidget")
local TextBoxWidget   = require("ui/widget/textboxwidget")
local ImageWidget     = require("ui/widget/imagewidget")
local Font            = require("ui/font")
local Geom            = require("ui/geometry")
local GestureRange    = require("ui/gesturerange")
local Blitbuffer      = require("ffi/blitbuffer")
local Device          = require("device")
local Screen          = Device.screen
local ok_ffiu, ffiutil= pcall(require, "ffi/util")
local ok_ds, DataStorage = pcall(require, "datastorage")

local plugin_path = ((...) or ""):match("(.-)[^%.]+$") or ""
local theme = require(plugin_path .. "xray_theme")

local function sc(val)
    return (Screen and Screen.scaleBySize and Screen:scaleBySize(val)) or val
end

local function safe_utf8_truncate(s, max_bytes)
    if not s or #s <= max_bytes then return s or "" end
    local out, i, len = {}, 1, #s
    while i <= len do
        local lead = s:byte(i)
        local width = (lead < 0x80 and 1) or (lead < 0xE0 and 2)
            or (lead < 0xF0 and 3) or (lead < 0xF5 and 4) or 1
        if (i + width - 1) > max_bytes then
            break
        end
        out[#out + 1] = s:sub(i, i + width - 1)
        i = i + width
    end
    return table.concat(out)
end

local _asset_path_cache = {}
local function getAssetPath(filename)
    if _asset_path_cache[filename] then
        return _asset_path_cache[filename]
    end
    local info = debug.getinfo(1, "S")
    local file_dir = (info and info.source and info.source:match("^@?(.*[/\\])")) or ""
    local data_dir = (ok_ds and DataStorage and DataStorage.getDataDir and DataStorage:getDataDir()) or ""
    local settings_dir = (ok_ds and DataStorage and DataStorage.getSettingsDir and DataStorage:getSettingsDir()) or ""

    local candidates = {
        file_dir .. "assets/" .. filename,
        file_dir .. "../assets/" .. filename,
        "plugins/xray.koplugin/assets/" .. filename,
        "./plugins/xray.koplugin/assets/" .. filename,
        data_dir .. "/plugins/xray.koplugin/assets/" .. filename,
        settings_dir .. "/plugins/xray.koplugin/assets/" .. filename,
    }
    for _, path in ipairs(candidates) do
        local f = io.open(path, "r")
        if f then
            f:close()
            if ok_ffiu and ffiutil and ffiutil.realpath then
                local rp = ffiutil.realpath(path)
                if rp then path = rp end
            end
            _asset_path_cache[filename] = path
            return path
        end
    end
    return "plugins/xray.koplugin/assets/" .. filename
end

local function makeTapItem(frame, callback)
    local item = InputContainer:new{ frame }
    item.frame = frame
    function item:getSize()
        return (frame and frame.getSize and frame:getSize()) or { w = frame.width or 0, h = frame.height or 0 }
    end
    function item:paintTo(bb, x, y)
        local fsize = (frame and frame.getSize and frame:getSize()) or { w = frame.width or 0, h = frame.height or 0 }
        self.dimen = Geom:new{ x = x, y = y, w = fsize.w or 0, h = fsize.h or 0 }
        if self.onBeforePaint then
            self:onBeforePaint()
        end
        frame:paintTo(bb, x, y)
    end
    item.ges_events = {
        Tap = {
            GestureRange:new{
                ges = "tap",
                range = function()
                    return item.dimen or Geom:new{ x = -1, y = -1, w = 1, h = 1 }
                end
            }
        }
    }
    item.onTap = function()
        if callback then
            pcall(callback)
        end
        return true
    end
    return item
end

local function createIconButton(opts)
    opts = opts or {}
    local icon_size = opts.size or sc(30)
    local btn_w = opts.width or sc(48)
    local btn_h = opts.height or sc(48)
    local is_focused = opts.is_focused == true
    local icon_widget = ImageWidget:new{
        file = getAssetPath(opts.icon),
        width = icon_size,
        height = icon_size,
        scale_factor = 0,
        is_icon = true,
        alpha = true,
    }
    local frame = FrameContainer:new{
        width = btn_w,
        height = btn_h,
        padding = 0,
        bordersize = is_focused and (theme.border_focus or sc(2)) or (opts.bordersize or 0),
        color = is_focused and (theme.color_focus_border or Blitbuffer.COLOR_BLACK) or (opts.color or Blitbuffer.COLOR_DARK_GRAY),
        background = is_focused and (theme.color_focus_bg or Blitbuffer.Color8(215)) or opts.background,
        radius = opts.radius or sc(6),
        CenterContainer:new{
            dimen = Geom:new{ w = btn_w, h = btn_h },
            icon_widget,
        }
    }
    local item = makeTapItem(frame, opts.callback)
    item.allow_flash = opts.allow_flash ~= false
    return item
end

local EntityListOverlay = InputContainer:extend{
    covers_fullscreen = true,
    modal = true,
    sw = nil,
    sh = nil,
    plugin = nil,
    entity = nil,
    mode = "characters", -- "characters", "terms", "locations", "historical_figures", "timeline", "mentions", "linked_entries", "evolution", "evolution_detail"
    raw_items = nil,
    items = nil,
    current_page = 1,
    total_pages = 1,
    sort_mode = "frequency", -- "frequency", "appearance", "alphabetical"
    search_query = nil,
    focus_zone = nil, -- "header", "cards", "footer"
    header_focus_idx = 1,
    focused_index = 1,
    footer_focus_idx = 1,
    is_touch_device = true,
    prior_collapsed = true,
    filter_key_only = true,
    reveal_future = false,
    detail_idx = 1,
}

function EntityListOverlay:init()
    if self.opts then
        if self.opts.show_all ~= nil then self.reveal_future = (self.opts.show_all == true) end
        if self.opts.filter_key_only ~= nil then self.filter_key_only = (self.opts.filter_key_only == true) end
    end
    self.modal = true
    self.covers_fullscreen = true
    self.sw = Screen:getWidth()
    self.sh = Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.sw, h = self.sh }
    self.stop_events_propagation = true

    local ok_dev, Dev = pcall(require, "device")
    if rawget(self, "is_touch_device") == nil then
        if ok_dev and Dev then
            if type(Dev.isTouchDevice) == "function" then
                local ok2, res = pcall(Dev.isTouchDevice, Dev)
                if ok2 and res ~= nil then self.is_touch_device = (res == true) end
            elseif Dev.isTouchDevice ~= nil then
                self.is_touch_device = (Dev.isTouchDevice == true)
            end
        end
    end

    self.focus_zone = nil
    self.focused_index = nil
    self.story_sections_collapsed = {}

    self.key_events = {
        NextPage = {
            { "NextPage" },
            { "PageDown" },
            { "n" },
            { "N" },
            { "]" },
            { "RPgFwd" },
            { "LPgFwd" },
        },
        PrevPage = {
            { "PrevPage" },
            { "PageUp" },
            { "p" },
            { "P" },
            { "[" },
            { "RPgBack" },
            { "LPgBack" },
        },
    }
    if ok_dev and Dev and Dev.input and Dev.input.group then
        if Dev.input.group.PgFwd then
            table.insert(self.key_events.NextPage, { Dev.input.group.PgFwd })
        end
        if Dev.input.group.PgBack then
            table.insert(self.key_events.PrevPage, { Dev.input.group.PgBack })
        end
    end

    self.ges_events = {
        Tap = {
            GestureRange:new{
                ges = "tap",
                range = function() return self.dimen end,
            },
        },
        Swipe = {
            GestureRange:new{
                ges = "swipe",
                range = function() return self.dimen end,
            },
        },
    }

    if self.plugin and self.plugin.series_prior_timeline_collapsed ~= nil then
        self.prior_collapsed = self.plugin.series_prior_timeline_collapsed
    end

    if self.plugin and self.plugin.entity_sort_mode and self.plugin.entity_sort_mode[self.mode] then
        self.sort_mode = self.plugin.entity_sort_mode[self.mode]
    end

    if self.plugin and self.plugin.isAnthologyMode and self.plugin:isAnthologyMode() then
        if self.plugin.ensureStoryPresenceScanned then
            self.plugin:ensureStoryPresenceScanned()
        end
    end

    self:prepareItems()
    self:buildUI()
end

function EntityListOverlay:getBookFontSize()
    local p = self.plugin
    local size
    if p and p.ui and p.ui.font and p.ui.font.configurable then
        size = p.ui.font.configurable.font_size
    elseif G_reader_settings then
        size = G_reader_settings:readSetting("cre_font_size")
              or G_reader_settings:readSetting("kopt_font_size")
    end
    if not size and p and p.getPopupFontSize then
        size = p:getPopupFontSize()
    end
    size = tonumber(size) or 22

    local font_setting = p and p.ai_helper and p.ai_helper.settings and p.ai_helper.settings.popup_font_size
    local font_offset = 0
    if font_setting == "small" then
        font_offset = -2
    elseif font_setting == "large" then
        font_offset = 3
    elseif font_setting == "xlarge" then
        font_offset = 6
    end
    return math.max(16, size + font_offset)
end

local function getRoleScore(role)
    if not role or type(role) ~= "string" then return 0 end
    local r = role:lower()

    if r:find("protagonist") or r:find("main character") or r:find("lead character") or r:find("hero") then
        return 100
    end
    if r:find("private investigator") or r:find("lead investigator") or r:find("chief investigator") then
        return 100
    end
    if r:find("deuteragonist") or r:find("co%-lead") or r:find("second lead") then
        return 95
    end
    if r:find("detective") then
        return 90
    end
    if r:find("investigat") then
        if r:find("military") or r:find("insurance") or r:find("forensic") then
            return 45
        end
        return 90
    end

    if r:find("partner") then
        local is_personal = r:find("romantic") or r:find("ex%-") or r:find("ex ") or r:find("domestic")
            or r:find("life") or r:find("dating") or r:find("spouse") or r:find("husband")
            or r:find("wife") or r:find("girlfriend") or r:find("boyfriend") or r:find("'s partner")
        if is_personal then
            return 25
        else
            return 85
        end
    end

    if r:find("primary antagonist") or r:find("main antagonist") or r:find("arch%-villain") then
        return 80
    end
    if r:find("antagonist") or r:find("villain") or r:find("killer") or r:find("murderer") or r:find("culprit") then
        return 70
    end
    if r:find("victim") or r:find("client") then
        return 40
    end
    if r:find("suspect") or r:find("person of interest") then
        return 35
    end
    if r:find("secondary") or r:find("supporting") or r:find("informant") or r:find("fiance") or r:find("friend") or r:find("mother") or r:find("father") or r:find("brother") or r:find("sister") then
        return 30
    end
    if r:find("minor") or r:find("background") or r:find("incidental") or r:find("extra") then
        return 5
    end

    return 20
end

local function getEntityRole(entity)
    if not entity then return nil end
    if entity.role and entity.role ~= "" then return entity.role end
    if entity.states and #entity.states > 0 then
        for i = #entity.states, 1, -1 do
            local s = entity.states[i]
            if s and s.role and s.role ~= "" then return s.role end
        end
    end
    return entity.category or entity.occupation
end

local function getChapterCount(entity)
    if not entity then return 0 end
    local chapters = {}
    if entity.states and type(entity.states) == "table" then
        for _, s in ipairs(entity.states) do
            local ch = s.chapter_index or s.chapter_title or s.page_hint
            if ch then chapters[ch] = true end
        end
    end
    if entity.history and type(entity.history) == "table" then
        for _, h in ipairs(entity.history) do
            local ch = h.chapter_index or h.chapter or h.page
            if ch then chapters[ch] = true end
        end
    end
    local count = 0
    for _ in pairs(chapters) do count = count + 1 end
    return count
end

local function calculateImportanceScore(entity)
    local r_score = getRoleScore(getEntityRole(entity))
    local ch_count = getChapterCount(entity)
    local m_count = (entity.mentions and #entity.mentions) or 0
    if m_count > 0 then
        return m_count * 100 + r_score * 10 + ch_count * 20
    else
        return r_score * 10 + ch_count * 20
    end
end

local function getAppearanceOrder(entity, plugin)
    if not entity then return 9999, 999999 end
    local min_chap = nil
    local min_page = nil

    local function consider(chap, page)
        local c = tonumber(chap)
        local p = tonumber(page)
        if p and p > 0 then
            if not min_page or p < min_page then min_page = p end
        end
        if c and c > 0 then
            if not min_chap or c < min_chap then min_chap = c end
        end
    end

    if entity.visible_from then
        consider(entity.visible_from.chapter_index, entity.visible_from.page_hint)
    end
    if entity.states and type(entity.states) == "table" then
        for _, s in ipairs(entity.states) do
            consider(s.chapter_index, s.page_hint)
        end
    end
    consider(nil, entity.first_page)
    consider(nil, entity.page)
    if entity.history and type(entity.history) == "table" then
        for _, h in ipairs(entity.history) do
            local h_chap = h.chapter_index
            if not h_chap and h.chapter and type(h.chapter) == "string" then
                h_chap = h.chapter:match("[Cc]hapter%s+(%d+)")
            end
            consider(h_chap, h.page)
        end
    end
    if entity.mentions and type(entity.mentions) == "table" then
        for _, m in ipairs(entity.mentions) do
            consider(m.chapter_index, m.page)
        end
    end

    -- If we have page but no chapter, try to resolve chapter from plugin
    if min_page and not min_chap and plugin and plugin.getCurrentChapterIndex then
        pcall(function()
            min_chap = plugin:getCurrentChapterIndex(min_page)
        end)
    end

    -- If we have chapter but no page, try to resolve page from toc
    if min_chap and not min_page and plugin and plugin.toc and plugin.toc[min_chap] then
        local tp = tonumber(plugin.toc[min_chap].page)
        if tp and tp > 0 then min_page = tp end
    end

    return min_chap or 9999, min_page or 999999
end

function EntityListOverlay:isSectionCollapsed(section_id)
    if not section_id then return false end
    if self.search_query and self.search_query ~= "" then
        return false
    end
    self.story_sections_collapsed = self.story_sections_collapsed or {}
    if self.story_sections_collapsed[section_id] ~= nil then
        return self.story_sections_collapsed[section_id]
    end
    if section_id == "recurring" or section_id == "current" then
        return false
    end
    return true
end

function EntityListOverlay:toggleSection(section_id)
    if not section_id then return end
    self.story_sections_collapsed = self.story_sections_collapsed or {}
    local cur_state = self:isSectionCollapsed(section_id)
    self.story_sections_collapsed[section_id] = not cur_state
    self._anchor_section_id = section_id
    self:buildUI()
    self._anchor_section_id = nil
    UIManager:setDirty(self, "ui")
end

function EntityListOverlay:togglePriorSection()
    self.prior_collapsed = not self.prior_collapsed
    if self.plugin then
        self.plugin.series_prior_timeline_collapsed = self.prior_collapsed
    end
    self._anchor_prior_header = true
    self:buildUI()
    self._anchor_prior_header = nil
    UIManager:setDirty(self, "ui")
end

function EntityListOverlay:buildStorySections(items)
    local p = self.plugin
    if not p or not items or #items == 0 then return items or {} end

    local is_spoiler_free = (p and p.ai_helper and p.ai_helper.settings and p.ai_helper.settings.spoiler_setting or "spoiler_free") == "spoiler_free"
    local show_all = (self.reveal_future == true) or (not is_spoiler_free) or (p and p.anthology_show_all_stories == true) or (self.search_query and self.search_query ~= "")

    local cur_page = p.getCurrentDocPage and p:getCurrentDocPage()
    local cur_story = p.getCurrentStory and p:getCurrentStory(cur_page)
    local cur_story_id = cur_story and cur_story.story_id

    local all_stories = {}
    if p.ui and p.ui.document then
        local ok, ChapterAnalyzer = pcall(require, plugin_path .. "xray_chapteranalyzer")
        if ok and ChapterAnalyzer then
            p.chapter_analyzer = p.chapter_analyzer or ChapterAnalyzer:new{ plugin = p }
            local custom_depth = p.book_data and p.book_data.story_toc_depth
            local sm = p.chapter_analyzer:getStoryMap(p.ui, custom_depth)
            all_stories = (sm and sm.stories) or {}
        end
    end

    local current_items = {}
    local other_story_items = {}
    local story_seen = {}

    local current_seen = {}
    local other_seen = {}

    for _, s in ipairs(all_stories) do
        other_story_items[s.story_id] = { story = s, items = {} }
        other_seen[s.story_id] = {}
        story_seen[s.story_id] = true
    end

    local unassigned_items = {}
    local unassigned_seen = {}

    for _, it in ipairs(items) do
        local entity = (self.mode == "linked_entries" and it.item) or it
        local name = entity.name or entity.chapter or (entity.item and entity.item.name)
        local norm_name = name and (p and p.canonicalNameKey and select(1, p:canonicalNameKey(name)) or name:lower()) or tostring(it)
        local is_rec = p and p.isEntityRecurring and p:isEntityRecurring(entity)
        local st_id = entity.story_id or (p and p.resolveEntityStory and p:resolveEntityStory(entity))
        local pres = name and p and (p.getStoryPresence and p:getStoryPresence(name) or (p.book_data and p.book_data.story_presence and p.book_data.story_presence[name]))

        local in_current = false
        if cur_story_id and (st_id and tostring(st_id) == tostring(cur_story_id) or (pres and (pres[cur_story_id] or pres[tostring(cur_story_id)]))) then
            in_current = true
        end

        if in_current then
            local existing_idx = current_seen[norm_name]
            if not existing_idx then
                table.insert(current_items, it)
                current_seen[norm_name] = #current_items
            else
                local stored_it = current_items[existing_idx]
                local stored_ent = (self.mode == "linked_entries" and stored_it.item) or stored_it
                local stored_sid = stored_ent.story_id or (p and p.resolveEntityStory and p:resolveEntityStory(stored_ent))
                if st_id and tostring(st_id) == tostring(cur_story_id) and stored_sid and tostring(stored_sid) ~= tostring(cur_story_id) then
                    current_items[existing_idx] = it
                end
            end
        end

        -- If recurring, also include in other story groups where presence is recorded
        if is_rec and pres then
            for s_id, is_pres in pairs(pres) do
                if is_pres and (not cur_story_id or tostring(s_id) ~= tostring(cur_story_id)) then
                    local is_future = not show_all and is_spoiler_free and cur_story and p.isStoryAfterCurrent and p:isStoryAfterCurrent({ story_id = s_id }, cur_story)
                    if not is_future then
                        other_seen[s_id] = other_seen[s_id] or {}
                        if not other_seen[s_id][norm_name] then
                            other_seen[s_id][norm_name] = true
                            if other_story_items[s_id] then
                                table.insert(other_story_items[s_id].items, it)
                            else
                                other_story_items[s_id] = {
                                    story = { story_id = s_id, story_title = "Story " .. tostring(s_id) },
                                    items = { it }
                                }
                            end
                        end
                    end
                end
            end
        end

        if not in_current and (not is_rec or not pres) then
            local is_future = not show_all and is_spoiler_free and cur_story and p.isStoryAfterCurrent and p:isStoryAfterCurrent({ story_id = st_id }, cur_story)
            if not is_future then
                if st_id and other_story_items[st_id] then
                    other_seen[st_id] = other_seen[st_id] or {}
                    if not other_seen[st_id][norm_name] then
                        other_seen[st_id][norm_name] = true
                        table.insert(other_story_items[st_id].items, it)
                    end
                elseif st_id then
                    other_seen[st_id] = other_seen[st_id] or {}
                    if not other_seen[st_id][norm_name] then
                        other_seen[st_id][norm_name] = true
                        other_story_items[st_id] = {
                            story = { story_id = st_id, story_title = entity.story_title or ("Story " .. tostring(st_id)) },
                            items = { it }
                        }
                    end
                else
                    if not unassigned_seen[norm_name] then
                        unassigned_seen[norm_name] = true
                        table.insert(unassigned_items, it)
                    end
                end
            end
        end
    end

    local display_items = {}
    local loc = self.loc or (p and p.loc)

    -- 1. Current story section (expanded by default)
    local cur_title = cur_story and cur_story.story_title or "Current Story"
    local prefix = (loc and loc:t("anthology_this_story_header")) or "This story"
    local cur_header_title = string.format("%s: %s", prefix, cur_title)
    local show_current_empty = (not self.search_query or self.search_query == "") and (cur_story ~= nil)
    if #current_items > 0 or show_current_empty then
        local is_collapsed = self:isSectionCollapsed("current")
        table.insert(display_items, {
            is_section_header = true,
            section_id = "current",
            title = cur_header_title,
            count = #current_items,
            collapsed = is_collapsed,
            collapsible = true,
        })
        if not is_collapsed then
            for _, it in ipairs(current_items) do
                table.insert(display_items, it)
            end
        end
    end

    -- 2. Other stories (folded by default)
    for _, s in ipairs(all_stories) do
        if not cur_story_id or tostring(s.story_id) ~= tostring(cur_story_id) then
            local is_future = not show_all and is_spoiler_free and cur_story and p.isStoryAfterCurrent and p:isStoryAfterCurrent({ story_id = s.story_id }, cur_story)
            if not is_future then
                local grp = other_story_items[s.story_id]
                if grp and #grp.items > 0 then
                    local sec_id = "story_" .. s.story_id
                    local is_collapsed = self:isSectionCollapsed(sec_id)
                    table.insert(display_items, {
                        is_section_header = true,
                        section_id = sec_id,
                        title = s.story_title or ("Story " .. s.story_id),
                        count = #grp.items,
                        collapsed = is_collapsed,
                        collapsible = true,
                    })
                    if not is_collapsed then
                        for _, it in ipairs(grp.items) do
                            table.insert(display_items, it)
                        end
                    end
                end
            end
        end
    end

    -- Any dynamic other_story_items not in all_stories
    for st_id, grp in pairs(other_story_items) do
        if not story_seen[st_id] and (not cur_story_id or tostring(st_id) ~= tostring(cur_story_id)) and #grp.items > 0 then
            local is_future = not show_all and is_spoiler_free and cur_story and p.isStoryAfterCurrent and p:isStoryAfterCurrent({ story_id = st_id }, cur_story)
            if not is_future then
                local sec_id = "story_" .. st_id
                local is_collapsed = self:isSectionCollapsed(sec_id)
                table.insert(display_items, {
                    is_section_header = true,
                    section_id = sec_id,
                    title = grp.story and grp.story.story_title or ("Story " .. st_id),
                    count = #grp.items,
                    collapsed = is_collapsed,
                    collapsible = true,
                })
                if not is_collapsed then
                    for _, it in ipairs(grp.items) do
                        table.insert(display_items, it)
                    end
                end
            end
        end
    end

    -- 3. Unassigned items (fallback)
    if #unassigned_items > 0 then
        local sec_id = "story_other"
        local is_collapsed = self:isSectionCollapsed(sec_id)
        table.insert(display_items, {
            is_section_header = true,
            section_id = sec_id,
            title = (loc and loc:t("anthology_other_entities_header")) or "Other Entities",
            count = #unassigned_items,
            collapsed = is_collapsed,
            collapsible = true,
        })
        if not is_collapsed then
            for _, it in ipairs(unassigned_items) do
                table.insert(display_items, it)
            end
        end
    end

    return display_items
end

function EntityListOverlay:prepareItems()
    local p = self.plugin
    local cur_page = p and p.getCurrentDocPage and p:getCurrentDocPage()
    local cur_chap = p and p.getCurrentChapterIndex and p:getCurrentChapterIndex(cur_page)
    local is_spoiler_free = (p and p.ai_helper and p.ai_helper.settings and p.ai_helper.settings.spoiler_setting or "spoiler_free") == "spoiler_free"

    if self.mode == "evolution" or self.mode == "evolution_detail" then
        local ok, Evolution = pcall(require, plugin_path .. "xray_evolution")
        if ok and Evolution and Evolution.build then
            local resolveChapter = function(page, title, index)
                local idx = index
                local t = title
                if not idx and page and p and p.getCurrentChapterIndex then
                    local looked_up = p:getCurrentChapterIndex(page)
                    if looked_up and looked_up > 0 then idx = looked_up end
                end
                if not idx and t and p and p.toc then
                    for i, ch in ipairs(p.toc) do
                        if ch.title and ch.title:lower() == t:lower() then
                            idx = i
                            break
                        end
                    end
                end
                if idx and not t and p and p.toc and p.toc[idx] then
                    t = p.toc[idx].title
                end
                return idx, t
            end
            local ctx = {
                cur_chap = cur_chap,
                cur_page = cur_page,
                is_full_book = not is_spoiler_free,
                show_all = (self.reveal_future == true) or (not is_spoiler_free),
                resolveChapter = resolveChapter,
            }
            local all_milestones = Evolution.build(self.entity, ctx)
            self.all_milestones = all_milestones
            if self.filter_key_only ~= false then
                self.items = Evolution.filterKey(all_milestones)
            else
                self.items = all_milestones
            end
            self.unfiltered_visible_count = #(self.items or {})
            return
        else
            self.items = {}
            self.unfiltered_visible_count = 0
            return
        end
    end

    local raw = self.raw_items or self.items or {}
    if not self.raw_items then self.raw_items = raw end
    local entries = {}

    -- Apply search query if present
    local q = (self.search_query and self.search_query ~= "") and self.search_query:lower() or nil
    local unfiltered_visible_count = 0
    local is_anthology = p and p.isAnthologyMode and p:isAnthologyMode()
    local cur_story = is_anthology and p.getCurrentStory and p:getCurrentStory(cur_page) or nil
    local show_all = (self.reveal_future == true) or (not is_spoiler_free) or (p and p.anthology_show_all_stories == true) or (self.search_query and self.search_query ~= "")
    for idx, it in ipairs(raw) do
        local entity = (self.mode == "linked_entries" and it.item) or it
        local visible = true
        if self.mode == "mentions" then
            if is_spoiler_free and cur_page then
                local pg = tonumber(it.page)
                if pg and pg > cur_page then
                    visible = false
                end
            end
        elseif self.mode == "timeline" then
            if is_anthology then
                local st_role, in_cur = p.getEntityStoryRole and p:getEntityStoryRole(entity, cur_story and cur_story.story_id)
                if in_cur or st_role == "current" then
                    if is_spoiler_free then
                        if it.chapter_index and cur_chap and it.chapter_index > cur_chap then
                            visible = false
                        elseif it.page and cur_page and tonumber(it.page) and tonumber(it.page) > cur_page then
                            if not (it.chapter_index and cur_chap and it.chapter_index < cur_chap) then
                                visible = false
                            end
                        end
                    end
                elseif not show_all and is_spoiler_free and cur_story and p.isStoryAfterCurrent and p:isStoryAfterCurrent(entity, cur_story) then
                    visible = false
                end
            elseif is_spoiler_free then
                if it.chapter_index and cur_chap and it.chapter_index > cur_chap then
                    visible = false
                elseif it.page and cur_page and tonumber(it.page) and tonumber(it.page) > cur_page then
                    if not (it.chapter_index and cur_chap and it.chapter_index < cur_chap) then
                        visible = false
                    end
                end
            end
        else
            if is_anthology then
                local st_role, in_cur = p.getEntityStoryRole and p:getEntityStoryRole(entity, cur_story and cur_story.story_id)
                if in_cur or st_role == "current" then
                    if is_spoiler_free and p and p.isEntityVisibleAtCurrentPosition then
                        visible = p:isEntityVisibleAtCurrentPosition(entity, cur_chap, cur_page)
                    else
                        visible = true
                    end
                elseif not show_all and is_spoiler_free and cur_story and p.isStoryAfterCurrent and p:isStoryAfterCurrent(entity, cur_story) then
                    visible = false
                else
                    visible = true
                end
            elseif is_spoiler_free and p and p.isEntityVisibleAtCurrentPosition then
                visible = p:isEntityVisibleAtCurrentPosition(entity, cur_chap, cur_page)
            end
        end

        if visible then
            unfiltered_visible_count = unfiltered_visible_count + 1
            local name = (entity.name or entity.chapter or ""):lower()
            local desc = (entity.description or entity.definition or entity.biography or entity.event or entity.snippet or ""):lower()
            if not q or (name:find(q, 1, true) or desc:find(q, 1, true)) then
                table.insert(entries, { item = it, _orig_idx = idx })
            end
        end
    end
    self.unfiltered_visible_count = unfiltered_visible_count

    -- Sorting (timeline and mentions have their own sequence, others use sort modes)
    if self.mode == "mentions" then
        table.sort(entries, function(a, b)
            local pa = tonumber(a.item.page) or 0
            local pb = tonumber(b.item.page) or 0
            if pa == pb then return a._orig_idx < b._orig_idx end
            return pa < pb
        end)
    elseif self.mode ~= "timeline" then
        if self.sort_mode == "alphabetical" then
            table.sort(entries, function(a, b)
                local ea = (self.mode == "linked_entries" and a.item.item) or a.item
                local eb = (self.mode == "linked_entries" and b.item.item) or b.item
                local na = (ea.name or ea.chapter or ""):lower()
                local nb = (eb.name or eb.chapter or ""):lower()
                if na == nb then return a._orig_idx < b._orig_idx end
                return na < nb
            end)
        elseif self.sort_mode == "appearance" then
            table.sort(entries, function(a, b)
                local ea = (self.mode == "linked_entries" and a.item.item) or a.item
                local eb = (self.mode == "linked_entries" and b.item.item) or b.item

                -- Prior-only characters (not in current book) sort after current book characters
                local prior_a = (ea.source == "series_prior" and (not ea.states or #ea.states == 0) and not ea.visible_from)
                local prior_b = (eb.source == "series_prior" and (not eb.states or #eb.states == 0) and not eb.visible_from)
                if prior_a ~= prior_b then
                    return not prior_a
                end

                local ca, pa = getAppearanceOrder(ea, self.plugin)
                local cb, pb = getAppearanceOrder(eb, self.plugin)
                if ca ~= cb then
                    return ca < cb
                end
                if pa ~= pb then
                    return pa < pb
                end

                -- Tie breaker for characters introduced in the same chapter: importance score
                local sa = calculateImportanceScore(ea)
                local sb = calculateImportanceScore(eb)
                if sa ~= sb then
                    return sa > sb
                end

                return a._orig_idx < b._orig_idx
            end)
        else
            -- Default: Frequency of mentions / Importance
            table.sort(entries, function(a, b)
                local ea = (self.mode == "linked_entries" and a.item.item) or a.item
                local eb = (self.mode == "linked_entries" and b.item.item) or b.item

                -- 1. Prior-only characters (not in current book) sort after current book characters
                local prior_a = (ea.source == "series_prior" and (not ea.states or #ea.states == 0) and not ea.visible_from)
                local prior_b = (eb.source == "series_prior" and (not eb.states or #eb.states == 0) and not eb.visible_from)
                if prior_a ~= prior_b then
                    return not prior_a
                end

                -- 2. Real mention count if mentions have been scanned
                local ma = (ea.mentions and #ea.mentions) or 0
                local mb = (eb.mentions and #eb.mentions) or 0
                if ma ~= mb then
                    return ma > mb
                end

                -- 3. Composite importance score (Role weight + Chapter presence)
                local sa = calculateImportanceScore(ea)
                local sb = calculateImportanceScore(eb)
                if sa ~= sb then
                    return sa > sb
                end

                -- 4. sort_order if both have valid numeric sort_order (1, 2, 3...)
                local oa = tonumber(ea.sort_order)
                local ob = tonumber(eb.sort_order)
                local valid_oa = oa and oa > 0 and oa < 10000
                local valid_ob = ob and ob > 0 and ob < 10000
                if valid_oa and valid_ob and oa ~= ob then
                    return oa < ob
                end

                -- 5. Earlier appearance order
                local ca, pa = getAppearanceOrder(ea, self.plugin)
                local cb, pb = getAppearanceOrder(eb, self.plugin)
                if ca ~= cb then
                    return ca < cb
                end
                if pa ~= pb then
                    return pa < pb
                end

                -- 6. Guaranteed stable fallback to natural list order in raw_items
                return a._orig_idx < b._orig_idx
            end)
        end
    end

    local filtered = {}
    for _, entry in ipairs(entries) do
        table.insert(filtered, entry.item)
    end
    self.items = filtered
end

function EntityListOverlay:onShow()
    UIManager:setDirty(self, "ui")
    return true
end

function EntityListOverlay:onTap(arg, ges)
    if self.is_touch_device and self.focus_zone then
        self.focus_zone = nil
        self.focused_index = nil
        self:buildUI()
        UIManager:setDirty(self, "ui")
    end
    return true
end

function EntityListOverlay:onSwipe(arg, ges)
    if ges.direction == "west" or ges.direction == "left" then
        return self:onNextPage()
    elseif ges.direction == "east" or ges.direction == "right" then
        return self:onPrevPage()
    end
end

function EntityListOverlay:onNextPage()
    if self.current_page < self.total_pages then
        self.current_page = self.current_page + 1
        self.focused_index = 1
        self:buildUI()
        UIManager:setDirty(self, "ui")
    end
    return true
end

function EntityListOverlay:onPrevPage()
    if self.current_page > 1 then
        self.current_page = self.current_page - 1
        self.focused_index = 1
        self:buildUI()
        UIManager:setDirty(self, "ui")
    end
    return true
end

function EntityListOverlay:onFirstPage()
    if self.current_page > 1 then
        self.current_page = 1
        self.focused_index = 1
        self:buildUI()
        UIManager:setDirty(self, "ui")
    end
    return true
end

function EntityListOverlay:onLastPage()
    if self.current_page < self.total_pages then
        self.current_page = self.total_pages
        self.focused_index = 1
        self:buildUI()
        UIManager:setDirty(self, "ui")
    end
    return true
end

function EntityListOverlay:onJumpPage()
    if self.total_pages <= 1 then return true end
    local SpinWidget = require("ui/widget/spinwidget")
    UIManager:show(SpinWidget:new{
        modal = true,
        title_text = "Go to page",
        value = self.current_page,
        value_min = 1,
        value_max = self.total_pages,
        ok_text = "Go",
        callback = function(spin)
            if spin and spin.value and spin.value ~= self.current_page then
                self.current_page = spin.value
                self.focused_index = 1
                self:buildUI()
                UIManager:setDirty(self, "ui")
            end
        end,
    })
    return true
end

function EntityListOverlay:onFocusDown()
    if not self.focus_zone then
        self.focus_zone = "cards"
        self.focused_index = 1
    elseif self.focus_zone == "header" then
        self.focus_zone = "cards"
        self.focused_index = 1
    elseif self.focus_zone == "cards" then
        local count = (self.current_page_items and #self.current_page_items) or 0
        if (self.focused_index or 1) < count then
            self.focused_index = (self.focused_index or 1) + 1
        else
            self.focus_zone = "footer"
            self.footer_focus_idx = 2
        end
    elseif self.focus_zone == "footer" then
        self.focus_zone = "header"
        self.header_focus_idx = 1
    end
    self:buildUI()
    UIManager:setDirty(self, "ui")
    return true
end

function EntityListOverlay:onFocusUp()
    local count = (self.current_page_items and #self.current_page_items) or 1
    if not self.focus_zone then
        self.focus_zone = "cards"
        self.focused_index = math.max(1, count)
    elseif self.focus_zone == "footer" then
        self.focus_zone = "cards"
        self.focused_index = math.max(1, count)
    elseif self.focus_zone == "cards" then
        if (self.focused_index or 1) > 1 then
            self.focused_index = (self.focused_index or 1) - 1
        else
            self.focus_zone = "header"
            self.header_focus_idx = 1
        end
    elseif self.focus_zone == "header" then
        self.focus_zone = "footer"
        self.footer_focus_idx = 2
    end
    self:buildUI()
    UIManager:setDirty(self, "ui")
    return true
end

function EntityListOverlay:onFocusLeft()
    if not self.focus_zone then
        self.focus_zone = "cards"
        self.focused_index = 1
        self:buildUI()
        UIManager:setDirty(self, "ui")
        return true
    end
    if self.focus_zone == "header" then
        local count = (self.current_header_actions and #self.current_header_actions) or 1
        self.header_focus_idx = (self.header_focus_idx > 1) and (self.header_focus_idx - 1) or count
        self:buildUI()
        UIManager:setDirty(self, "ui")
        return true
    elseif self.focus_zone == "footer" then
        self.footer_focus_idx = (self.footer_focus_idx > 1) and (self.footer_focus_idx - 1) or 3
        self:buildUI()
        UIManager:setDirty(self, "ui")
        return true
    elseif self.focus_zone == "cards" then
        return self:onPrevPage()
    end
    return false
end

function EntityListOverlay:onFocusRight()
    if not self.focus_zone then
        self.focus_zone = "cards"
        self.focused_index = 1
        self:buildUI()
        UIManager:setDirty(self, "ui")
        return true
    end
    if self.focus_zone == "header" then
        local count = (self.current_header_actions and #self.current_header_actions) or 1
        self.header_focus_idx = (self.header_focus_idx < count) and (self.header_focus_idx + 1) or 1
        self:buildUI()
        UIManager:setDirty(self, "ui")
        return true
    elseif self.focus_zone == "footer" then
        self.footer_focus_idx = (self.footer_focus_idx < 3) and (self.footer_focus_idx + 1) or 1
        self:buildUI()
        UIManager:setDirty(self, "ui")
        return true
    elseif self.focus_zone == "cards" then
        return self:onNextPage()
    end
    return false
end

function EntityListOverlay:onOpenFocused()
    if not self.focus_zone then
        self.focus_zone = "cards"
        self.focused_index = 1
        self:buildUI()
        UIManager:setDirty(self, "ui")
        return true
    end
    if self.focus_zone == "cards" then
        local item = self.current_page_items and self.current_page_items[self.focused_index or 1]
        if item then
            if item.is_prior_header then
                self:togglePriorSection()
            elseif item.is_section_header and item.section_id then
                self:toggleSection(item.section_id)
            elseif item.is_current_header then
                -- Static section header, no action
            else
                self:onItemSelect(item)
            end
        end
        return true
    elseif self.focus_zone == "header" then
        local action = self.current_header_actions and self.current_header_actions[self.header_focus_idx or 1]
        if action and action.callback then
            action.callback()
        end
        return true
    elseif self.focus_zone == "footer" then
        if self.footer_focus_idx == 1 then
            return self:onPrevPage()
        elseif self.footer_focus_idx == 2 then
            return self:onJumpPage()
        elseif self.footer_focus_idx == 3 then
            return self:onNextPage()
        end
        return true
    end
    return false
end

function EntityListOverlay:onKeyPress(key)
    local key_name = key and (key.key or key.name or (type(key) == "string" and key)) or ""
    return self:handleEvent({ type = "Key", key = key_name })
end

function EntityListOverlay:onKeyDown(key)
    return self:onKeyPress(key)
end

function EntityListOverlay:onKeyRepeat(key)
    return self:onKeyPress(key)
end

function EntityListOverlay:handleEvent(ev)
    if not ev then return false end

    if ev.type == "NextPage" or ev.type == "GotoNextPage" then
        return self:onNextPage()
    elseif ev.type == "PrevPage" or ev.type == "GotoPrevPage" then
        return self:onPrevPage()
    end

    if ev.type == "Key" or ev.type == "KeyPress" or ev.type == "KeyDown" then
        local key = ev.key or ev.name or ev.sym or ""
        if type(key) == "table" then
            key = key.key or key.name or ""
        end

        local ok_dev, Device = pcall(require, "device")
        local extra_enter_keys = {}
        local extra_back_keys = {}
        local extra_next_keys = {}
        local extra_prev_keys = {}
        if ok_dev and Device and Device.input and Device.input.group then
            if Device.input.group.Enter then extra_enter_keys[Device.input.group.Enter] = true end
            if Device.input.group.Select then extra_enter_keys[Device.input.group.Select] = true end
            if Device.input.group.Back then extra_back_keys[Device.input.group.Back] = true end
            if Device.input.group.PgFwd then
                for _, k in ipairs(Device.input.group.PgFwd) do extra_next_keys[k] = true end
            end
            if Device.input.group.PgBack then
                for _, k in ipairs(Device.input.group.PgBack) do extra_prev_keys[k] = true end
            end
        end

        local UP_KEYS    = { Up=true, k=true, K=true }
        local DOWN_KEYS  = { Down=true, j=true, J=true }
        local LEFT_KEYS  = { Left=true, h=true, H=true }
        local RIGHT_KEYS = { Right=true, l=true, L=true }
        local PAGE_PREV  = { PrevPage=true, PageUp=true, p=true, P=true, ["["]=true, LPgBack=true, RPgBack=true }
        local PAGE_NEXT  = { NextPage=true, PageDown=true, n=true, N=true, ["]"]=true, LPgFwd=true, RPgFwd=true }
        local ENTER_KEYS = { Return=true, Enter=true, KP_Enter=true, Select=true, Space=true, Press=true }
        local CLOSE_KEYS = { Escape=true, Back=true, q=true, Q=true }
        for k in pairs(extra_enter_keys) do ENTER_KEYS[k] = true end
        for k in pairs(extra_back_keys)  do CLOSE_KEYS[k] = true end
        for k in pairs(extra_next_keys)  do PAGE_NEXT[k]  = true end
        for k in pairs(extra_prev_keys)  do PAGE_PREV[k]  = true end

        if UP_KEYS[key] then
            return self:onFocusUp()
        elseif DOWN_KEYS[key] then
            return self:onFocusDown()
        elseif LEFT_KEYS[key] then
            return self:onFocusLeft()
        elseif RIGHT_KEYS[key] then
            return self:onFocusRight()
        elseif ENTER_KEYS[key] then
            return self:onOpenFocused()
        elseif CLOSE_KEYS[key] then
            if self.mode == "evolution_detail" then
                self.mode = "evolution"
                self:buildUI()
                UIManager:setDirty(self, "ui")
                return true
            end
            return self:close()
        elseif PAGE_PREV[key] then
            return self:onPrevPage()
        elseif PAGE_NEXT[key] then
            return self:onNextPage()
        elseif key == "Home" then
            return self:onFirstPage()
        elseif key == "End" then
            return self:onLastPage()
        elseif (key == "s" or key == "S") and (self.mode ~= "timeline" or (self.plugin and self.plugin.isAnthologyMode and self.plugin:isAnthologyMode())) and self.mode ~= "evolution" and self.mode ~= "evolution_detail" then
            return self:showSortDialog()
        elseif (key == "f" or key == "F" or key == "/") and self.mode ~= "evolution" and self.mode ~= "evolution_detail" then
            return self:showSearchDialog()
        elseif (key == "t" or key == "T") and self.mode == "evolution" then
            return self:showEvolutionFilterDialog()
        elseif (key == "m" or key == "M") and (self.mode == "characters" or self.mode == "locations") then
            return self:showMergeDialog()
        elseif (key == "+" or key == "=" or key == "a" or key == "A") and (self.mode == "characters" or self.mode == "terms") then
            if self.mode == "characters" and self.plugin then self.plugin:fetchMoreCharacters(); return true
            elseif self.mode == "terms" and self.plugin then self.plugin:fetchMoreTerms(); return true end
        else
            local num = tonumber(key)
            if num and num >= 1 and num <= 9 then
                local it = self.current_page_items and self.current_page_items[num]
                if it then
                    self.focus_zone = "cards"
                    self.focused_index = num
                    if it.is_prior_header then
                        self:togglePriorSection()
                    elseif it.is_section_header and it.section_id then
                        self:toggleSection(it.section_id)
                    elseif it.is_current_header then
                        -- Static section header, no action
                    else
                        self:onItemSelect(it)
                    end
                    return true
                end
            end
        end
    end
    return InputContainer.handleEvent(self, ev)
end

function EntityListOverlay:close()
    if self.plugin then
        if self.mode == "characters" then self.plugin.char_menu = nil
        elseif self.mode == "terms" then self.plugin.terms_menu = nil
        elseif self.mode == "locations" then self.plugin.loc_menu = nil
        elseif self.mode == "historical_figures" then self.plugin.hf_menu = nil
        elseif self.mode == "timeline" then self.plugin.timeline_menu = nil
        elseif self.mode == "mentions" then
            if self.plugin.active_mention_scan and self.plugin.active_mention_scan.cancel_handle then
                self.plugin.active_mention_scan.cancel_handle:cancel()
                self.plugin.active_mention_scan = nil
            end
            self.plugin.mentions_menu = nil
        elseif self.mode == "linked_entries" then self.plugin.active_related_menu = nil
        elseif self.mode == "evolution" or self.mode == "evolution_detail" then self.plugin.active_evolution_menu = nil
        end
    end
    UIManager:close(self, "ui")
    if self.on_close_callback then
        self.on_close_callback()
    end
end

function EntityListOverlay:showMergeDialog()
    local p = self.plugin
    if not p then return end
    local ButtonDialog = require("ui/widget/buttondialog")
    local loc = p.loc
    local items_to_merge = (self.mode == "characters") and p.characters or p.locations or {}
    local entity_type = self.mode
    local entity_label = (self.mode == "characters") and ((loc and loc:t("entity_label_characters")) or "characters") or ((loc and loc:t("entity_label_locations")) or "locations")

    local merge_dialog
    merge_dialog = ButtonDialog:new{
        modal = true,
        title = (loc and loc:t("merge_duplicates")) or "Merge Duplicates",
        buttons = {
            {
                {
                    text = "✦ " .. ((loc and loc:t("ai_scan")) or "AI Scan"),
                    callback = function()
                        UIManager:close(merge_dialog)
                        p:showAIFindDuplicatesFlow(items_to_merge, entity_type, entity_label)
                    end,
                },
                {
                    text = (loc and loc:t("manual_pick")) or "Manual Pick",
                    callback = function()
                        UIManager:close(merge_dialog)
                        p:showMergeFlow(items_to_merge, entity_type)
                    end,
                },
            },
            {
                {
                    text = (loc and loc:t("cancel")) or "Cancel",
                    callback = function() UIManager:close(merge_dialog) end,
                }
            }
        }
    }
    UIManager:show(merge_dialog)
end

function EntityListOverlay:showSortDialog()
    local ButtonDialog = require("ui/widget/buttondialog")
    local sort_dialog
    local p = self.plugin
    local loc = p and p.loc

    local function _tr(key, default)
        if not loc or not loc.t then return default end
        local res = loc:t(key)
        if not res or res == key then return default end
        return res
    end

    local buttons = {}
    local is_anthology = p and p.isAnthologyMode and p:isAnthologyMode()
    local is_timeline = (self.mode == "timeline")

    if not is_timeline then
        local current_sort = self.sort_mode
        local check_freq = (current_sort == "frequency") and "● " or "○ "
        local check_app  = (current_sort == "appearance") and "● " or "○ "
        local check_az   = (current_sort == "alphabetical") and "● " or "○ "

        table.insert(buttons, {
            {
                text = check_freq .. _tr("sort_frequency", "Frequency of Mentions (Default)"),
                align = "left",
                callback = function()
                    UIManager:close(sort_dialog)
                    self.sort_mode = "frequency"
                    if self.plugin then
                        self.plugin.entity_sort_mode = self.plugin.entity_sort_mode or {}
                        self.plugin.entity_sort_mode[self.mode] = self.sort_mode
                    end
                    self.current_page = 1
                    self:prepareItems()
                    self:buildUI()
                    UIManager:setDirty(self, "ui")
                end,
            },
        })
        table.insert(buttons, {
            {
                text = check_app .. _tr("sort_appearance", "Order of Appearance"),
                align = "left",
                callback = function()
                    UIManager:close(sort_dialog)
                    self.sort_mode = "appearance"
                    if self.plugin then
                        self.plugin.entity_sort_mode = self.plugin.entity_sort_mode or {}
                        self.plugin.entity_sort_mode[self.mode] = self.sort_mode
                    end
                    self.current_page = 1
                    self:prepareItems()
                    self:buildUI()
                    UIManager:setDirty(self, "ui")
                end,
            },
        })
        table.insert(buttons, {
            {
                text = check_az .. _tr("sort_alphabetical", "Alphabetical (A–Z)"),
                align = "left",
                callback = function()
                    UIManager:close(sort_dialog)
                    self.sort_mode = "alphabetical"
                    if self.plugin then
                        self.plugin.entity_sort_mode = self.plugin.entity_sort_mode or {}
                        self.plugin.entity_sort_mode[self.mode] = self.sort_mode
                    end
                    self.current_page = 1
                    self:prepareItems()
                    self:buildUI()
                    UIManager:setDirty(self, "ui")
                end,
            },
        })
    end

    if is_anthology then
        local cur_story = p.getCurrentStory and p:getCurrentStory()
        local cur_title = cur_story and cur_story.story_title
        local cur_label = cur_title and string.format("%s: %s", _tr("story_scope_current", "Current Story"), cur_title) or _tr("story_scope_current", "Current Story")
        local show_all = p.anthology_show_all_stories == true
        local check_cur = (not show_all) and "● " or "○ "
        local check_all = show_all and "● " or "○ "

        table.insert(buttons, {
            {
                text = check_cur .. cur_label,
                align = "left",
                callback = function()
                    UIManager:close(sort_dialog)
                    p.anthology_show_all_stories = false
                    self.current_page = 1
                    self:prepareItems()
                    self:buildUI()
                    UIManager:setDirty(self, "ui")
                end,
            },
        })
        table.insert(buttons, {
            {
                text = check_all .. _tr("story_scope_all", "All Stories"),
                align = "left",
                callback = function()
                    UIManager:close(sort_dialog)
                    p.anthology_show_all_stories = true
                    self.current_page = 1
                    self:prepareItems()
                    self:buildUI()
                    UIManager:setDirty(self, "ui")
                end,
            },
        })
    end

    table.insert(buttons, {
        {
            text = (loc and loc:t("cancel")) or "Cancel",
            callback = function() UIManager:close(sort_dialog) end,
        }
    })

    local dialog_title = is_timeline and _tr("story_scope_label", "Story Scope") or (is_anthology and (_tr("sort_and_scope", "Sort/Story Scope")) or _tr("sort_by", "Sort By"))
    sort_dialog = ButtonDialog:new{
        modal = true,
        title = dialog_title,
        buttons = buttons
    }
    UIManager:show(sort_dialog)
end

function EntityListOverlay:showSearchDialog()
    local InputDialog = require("ui/widget/inputdialog")
    local p = self.plugin
    local loc = p and p.loc
    local input_dlg
    input_dlg = InputDialog:new{
        modal = true,
        title = (loc and loc:t("search")) or "Search",
        input = self.search_query or "",
        input_hint = (loc and loc:t("search_hint")) or "Filter items...",
        buttons = {
            {
                {
                    text = (loc and loc:t("clear")) or "Clear",
                    callback = function()
                        UIManager:close(input_dlg)
                        self.search_query = nil
                        self.current_page = 1
                        self:prepareItems()
                        self:buildUI()
                        UIManager:setDirty(self, "ui")
                    end,
                },
                {
                    text = (loc and loc:t("cancel")) or "Cancel",
                    callback = function() UIManager:close(input_dlg) end,
                },
                {
                    text = (loc and loc:t("search")) or "Search",
                    is_enter_default = true,
                    callback = function()
                        local val = input_dlg:getInputText()
                        UIManager:close(input_dlg)
                        self.search_query = (val and val:match("^%s*(.-)%s*$") ~= "") and val:match("^%s*(.-)%s*$") or nil
                        self.current_page = 1
                        self:prepareItems()
                        self:buildUI()
                        UIManager:setDirty(self, "ui")
                    end,
                }
            }
        }
    }
    UIManager:show(input_dlg)
end

function EntityListOverlay:showEvolutionFilterDialog()
    local ButtonDialog = require("ui/widget/buttondialog")
    local filter_dialog
    local p = self.plugin
    local loc = p and p.loc

    local function _tr(key, default)
        if not loc or not loc.t then return default end
        local res = loc:t(key)
        if not res or res == key then return default end
        return res
    end

    local is_key = (self.filter_key_only ~= false)
    local check_key = is_key and "● " or "○ "
    local check_all = not is_key and "● " or "○ "

    filter_dialog = ButtonDialog:new{
        modal = true,
        title = _tr("evolution_filter_title", "Filter Milestones"),
        buttons = {
            {
                {
                    text = check_key .. _tr("evolution_filter_key", "Key Changes (Default)"),
                    align = "left",
                    callback = function()
                        UIManager:close(filter_dialog)
                        self.filter_key_only = true
                        self.current_page = 1
                        self:prepareItems()
                        self:buildUI()
                        UIManager:setDirty(self, "ui")
                    end,
                },
            },
            {
                {
                    text = check_all .. _tr("evolution_filter_all", "All Snapshots (Testing)"),
                    align = "left",
                    callback = function()
                        UIManager:close(filter_dialog)
                        self.filter_key_only = false
                        self.current_page = 1
                        self:prepareItems()
                        self:buildUI()
                        UIManager:setDirty(self, "ui")
                    end,
                },
            },
            {
                {
                    text = _tr("cancel", "Cancel"),
                    callback = function() UIManager:close(filter_dialog) end,
                }
            }
        }
    }
    UIManager:show(filter_dialog)
end

function EntityListOverlay:toggleEvolutionRevealFuture()
    self.reveal_future = not self.reveal_future
    self:prepareItems()
    self:buildUI()
    UIManager:setDirty(self, "ui")

    local p = self.plugin
    local cur_page = p and p.getCurrentDocPage and p:getCurrentDocPage()
    local cur_chap = p and p.getCurrentChapterIndex and p:getCurrentChapterIndex(cur_page)
    local total_m = #(self.all_milestones or {})
    local has_any_locked = false
    if self.all_milestones then
        for _, m in ipairs(self.all_milestones) do
            if m.chapter_index and cur_chap and m.chapter_index > cur_chap then
                has_any_locked = true
                break
            elseif m.page and cur_page and m.page > cur_page then
                has_any_locked = true
                break
            end
        end
    end

    local InfoMessage = require("ui/widget/infomessage")
    local ch_str = cur_chap and ("Ch. " .. tostring(cur_chap)) or ""
    local pg_str = cur_page and ("p. " .. tostring(cur_page)) or ""
    local pos_str = (ch_str ~= "" and pg_str ~= "") and (ch_str .. ", " .. pg_str) or (ch_str ~= "" and ch_str) or pg_str
    if pos_str ~= "" then pos_str = " (" .. pos_str .. ")" end

    local msg
    if self.reveal_future then
        if has_any_locked then
            msg = "Revealed future milestones (spoiler protection disabled)."
        else
            msg = string.format("Future milestones revealed (all %d milestones are already within current reading position%s).", total_m, pos_str)
        end
    else
        if has_any_locked then
            msg = "Future milestones hidden (spoiler protection active)."
        else
            msg = string.format("Spoiler protection active (all %d milestones are already within current reading position%s).", total_m, pos_str)
        end
    end
    UIManager:show(InfoMessage:new{ text = msg, timeout = 3 })
end

function EntityListOverlay:renderRow(item, content_w, row_h, is_focused, idx)
    local p = self.plugin
    local loc = p and p.loc
    local is_timeline = (self.mode == "timeline")
    local is_mentions = (self.mode == "mentions")
    local is_prior = (item.source == "series_prior")

    if is_timeline and is_prior then
        local raw_ch = item.chapter or ""
        local num_match, name_match = raw_ch:match("^%[?Book%s+(%d+%.?%d*)%s*:%s*(.-)%]?$")
        local title_str = "Prior Book"
        if num_match and name_match and name_match ~= "" then
            title_str = string.format("Book %s: %s", num_match, name_match)
        else
            local num_only = raw_ch:match("^%[?Book%s+(%d+%.?%d*)%]?$")
            if num_only then
                title_str = "Book " .. num_only
            elseif item.source_book then
                title_str = string.format("Book %s: %s", tostring(item.source_book), raw_ch:gsub("^%[", ""):gsub("%]$", ""))
            else
                title_str = (raw_ch ~= "") and raw_ch:gsub("^%[", ""):gsub("%]$", "") or "Prior Book"
            end
        end

        local pad_left = sc(28)
        local pad_right = sc(16)
        local inner_w = content_w - pad_left - pad_right

        local recap_pill = FrameContainer:new{
            padding = 0,
            padding_left = sc(6),
            padding_right = sc(6),
            padding_top = sc(1),
            padding_bottom = sc(1),
            bordersize = 0,
            radius = sc(3),
            background = Blitbuffer.Color8(220),
            TextWidget:new{
                text = "Recap",
                face = Font:getFace("cfont", 11),
                bold = true,
                fgcolor = Blitbuffer.Color8(60),
            },
        }

        local title_widget = TextWidget:new{
            text = title_str,
            face = Font:getFace("cfont", 18),
            bold = true,
            fgcolor = Blitbuffer.COLOR_BLACK,
            max_width = inner_w - sc(70),
        }

        local title_row = HorizontalGroup:new{
            align = "center",
            title_widget,
            HorizontalSpan:new{ width = sc(8) },
            recap_pill,
        }

        local desc_str = item.event or ""
        desc_str = desc_str:gsub("%s+", " "):match("^%s*(.-)%s*$") or ""
        if #desc_str > 185 then
            desc_str = safe_utf8_truncate(desc_str, 180) .. "..."
        end

        local desc_widget = nil
        if desc_str ~= "" and desc_str ~= "---" then
            desc_widget = TextWidget:new{
                text = desc_str,
                face = Font:getFace("cfont", 14),
                fgcolor = Blitbuffer.Color8(50),
                max_width = inner_w,
            }
        end

        local card_items = {
            VerticalSpan:new{ width = sc(3) },
            title_row,
        }
        if desc_widget then
            table.insert(card_items, VerticalSpan:new{ width = sc(1) })
            table.insert(card_items, desc_widget)
        end
        table.insert(card_items, VerticalSpan:new{ width = sc(3) })

        local main_vg = VerticalGroup:new(card_items)
        main_vg.align = "left"

        local is_card_focused = is_focused and (self.focus_zone == "cards")
        local main_vg_h = (main_vg.getSize and main_vg:getSize().h) or math.max(sc(24), row_h - sc(14))

        local row_frame = FrameContainer:new{
            padding = 0,
            bordersize = is_card_focused and sc(2) or 0,
            color = Blitbuffer.COLOR_BLACK,
            background = is_card_focused and Blitbuffer.Color8(220) or Blitbuffer.Color8(246),
            width = content_w,
            height = row_h,
            CenterContainer:new{
                dimen = Geom:new{ w = content_w, h = row_h },
                LeftContainer:new{
                    dimen = Geom:new{ w = inner_w, h = main_vg_h },
                    main_vg,
                },
            },
        }

        local row_item = InputContainer:new{
            dimen = Geom:new{ w = content_w, h = row_h },
            row_frame,
        }
        row_item.overlay = self

        function row_item:getSize()
            return self.dimen
        end

        function row_item:paintTo(bb, x, y)
            self.dimen = Geom:new{ x = x, y = y, w = content_w, h = row_h }
            local ov = self.overlay
            local focused = (ov and ov.focus_zone == "cards" and ov.focused_index == idx)
            row_frame.bordersize = focused and sc(2) or 0
            row_frame.color = Blitbuffer.COLOR_BLACK
            row_frame.background = focused and Blitbuffer.Color8(220) or Blitbuffer.Color8(246)
            if self[1] then self[1]:paintTo(bb, x, y) end
        end

        row_item.ges_events = {
            Tap = {
                GestureRange:new{
                    ges = "tap",
                    range = function() return row_item.dimen end,
                }
            }
        }

        row_item.onTap = function()
            local ov = self
            ov.focus_zone = nil
            ov.focused_index = nil
            if ov.onItemSelect then
                ov:onItemSelect(item)
            end
            return true
        end

        return row_item
    end

    local pad_h = sc(16)
    local inner_w = content_w - (pad_h * 2)

    local is_linked = (self.mode == "linked_entries")
    local actual_item = (is_linked and item.item) or item
    local item_type = (is_linked and item.type) or nil
    local is_prior_item = (actual_item and (actual_item.source == "series_prior" or actual_item.is_series or actual_item.from_series))

    -- 1. Primary line (Bold Name/Title, mimicking the Dialog title)
    local title_str = ""
    local prior_pill = nil
    local type_pill = nil
    if is_timeline then
        title_str = item.chapter or "Event"
        if item.page and tonumber(item.page) then
            title_str = title_str .. " (p. " .. tostring(item.page) .. ")"
        end
    elseif is_mentions then
        title_str = "p. " .. tostring(item.page or "")
        if item.chapter and item.chapter ~= "" then
            title_str = title_str .. " — " .. item.chapter
        end
    elseif is_linked then
        title_str = actual_item.name or "???"

        local type_lbl = "Entity"
        if item_type == "character" then
            type_lbl = (loc and loc:t("entity_type_character")) or "Character"
        elseif item_type == "location" then
            type_lbl = (loc and loc:t("entity_type_location")) or "Location"
        elseif item_type == "historical" or item_type == "historical_figures" then
            type_lbl = (loc and loc:t("entity_type_historical")) or "Historical Figure"
        elseif item_type == "term" or item_type == "terms" then
            type_lbl = (loc and loc:t("entity_type_term")) or "Term"
        elseif type(item_type) == "string" and #item_type > 0 then
            type_lbl = item_type:sub(1,1):upper() .. item_type:sub(2)
        end

        type_pill = FrameContainer:new{
            background = Blitbuffer.Color8(235),
            bordersize = sc(1),
            color = Blitbuffer.Color8(180),
            radius = sc(3),
            padding_top = sc(1),
            padding_bottom = sc(1),
            padding_left = sc(6),
            padding_right = sc(6),
            TextWidget:new{
                text = type_lbl,
                face = Font:getFace("cfont", 11),
                bold = true,
                fgcolor = Blitbuffer.Color8(60),
            },
        }

        if is_prior_item then
            local prior_lbl = (loc and loc:t("series_prior_label")) or "Series"
            prior_lbl = prior_lbl:gsub("^%[", ""):gsub("%]$", "")
            if prior_lbl == "" or prior_lbl:lower() == "prior" then
                prior_lbl = "Series"
            end
            prior_pill = FrameContainer:new{
                background = Blitbuffer.Color8(230),
                bordersize = sc(1),
                color = Blitbuffer.Color8(180),
                radius = sc(3),
                padding_top = sc(1),
                padding_bottom = sc(1),
                padding_left = sc(6),
                padding_right = sc(6),
                TextWidget:new{
                    text = prior_lbl,
                    face = Font:getFace("cfont", 11),
                    bold = true,
                    fgcolor = Blitbuffer.Color8(60),
                },
            }
        end
    else
        title_str = actual_item.name or "???"
        if is_prior_item then
            local prior_lbl = (loc and loc:t("series_prior_label")) or "Series"
            prior_lbl = prior_lbl:gsub("^%[", ""):gsub("%]$", "")
            if prior_lbl == "" or prior_lbl:lower() == "prior" then
                prior_lbl = "Series"
            end
            prior_pill = FrameContainer:new{
                background = Blitbuffer.Color8(230),
                bordersize = sc(1),
                color = Blitbuffer.Color8(180),
                radius = sc(3),
                padding_top = sc(1),
                padding_bottom = sc(1),
                padding_left = sc(6),
                padding_right = sc(6),
                TextWidget:new{
                    text = prior_lbl,
                    face = Font:getFace("cfont", 11),
                    bold = true,
                    fgcolor = Blitbuffer.Color8(60),
                },
            }
        end
    end

    local pills = {}
    if type_pill then table.insert(pills, type_pill) end
    if prior_pill then table.insert(pills, prior_pill) end

    if p and p.isAnthologyMode and p:isAnthologyMode() and actual_item and p.isEntityRecurring and p:isEntityRecurring(actual_item) then
        local rec_pill = FrameContainer:new{
            background = Blitbuffer.Color8(235),
            bordersize = sc(1),
            color = Blitbuffer.Color8(180),
            radius = sc(3),
            padding_top = sc(1),
            padding_bottom = sc(1),
            padding_left = sc(6),
            padding_right = sc(6),
            TextWidget:new{
                text = (loc and loc:t("story_recurring_pill")) or "Recurring",
                face = Font:getFace("cfont", 11),
                bold = true,
                fgcolor = Blitbuffer.Color8(60),
            },
        }
        table.insert(pills, rec_pill)
    end

    if p and p.isAnthologyMode and p:isAnthologyMode() and p.anthology_show_all_stories and actual_item then
        if not actual_item.story_title and p.resolveEntityStory then
            p:resolveEntityStory(actual_item)
        end
        if actual_item.story_title and actual_item.story_title ~= "" then
            local story_pill = FrameContainer:new{
                background = Blitbuffer.Color8(235),
                bordersize = sc(1),
                color = Blitbuffer.Color8(180),
                radius = sc(3),
                padding_top = sc(1),
                padding_bottom = sc(1),
                padding_left = sc(6),
                padding_right = sc(6),
                TextWidget:new{
                    text = actual_item.story_title,
                    face = Font:getFace("cfont", 11),
                    bold = true,
                    fgcolor = Blitbuffer.Color8(60),
                    max_width = sc(140),
                },
            }
            table.insert(pills, story_pill)
        end
    end

    local pills_w = 0
    for _, pill in ipairs(pills) do
        local ps = (pill.getSize and pill:getSize().w) or sc(60)
        pills_w = pills_w + ps + sc(6)
    end

    local title_widget = TextWidget:new{
        text = title_str,
        face = Font:getFace("cfont", 22),
        bold = true,
        fgcolor = Blitbuffer.COLOR_BLACK,
        max_width = (#pills > 0) and (inner_w - pills_w) or inner_w,
    }

    local title_row_widget
    if #pills > 0 then
        local row_elements = { title_widget }
        for _, pill in ipairs(pills) do
            table.insert(row_elements, HorizontalSpan:new{ width = sc(6) })
            table.insert(row_elements, pill)
        end
        title_row_widget = HorizontalGroup:new(row_elements)
        title_row_widget.align = "center"
    else
        title_row_widget = title_widget
    end

    -- 2. Description (Dark, readable single-line text)
    local desc_str = ""
    if is_timeline then
        desc_str = item.event or ""
    elseif is_mentions then
        desc_str = item.snippet or ""
    elseif is_linked then
        if item_type == "term" then
            desc_str = actual_item.definition or actual_item.description or ""
        elseif item_type == "historical" then
            desc_str = actual_item.biography or actual_item.description or ""
        else
            if p and p.resolveDescriptionForPage then
                desc_str = p:resolveDescriptionForPage(actual_item) or ""
            else
                desc_str = actual_item.description or actual_item.biography or ""
            end
        end
    elseif self.mode == "terms" then
        desc_str = item.definition or item.description or ""
    else
        if p and p.resolveDescriptionForPage then
            desc_str = p:resolveDescriptionForPage(item) or ""
        else
            desc_str = item.description or item.biography or ""
        end
    end
    desc_str = desc_str:gsub("%s+", " "):match("^%s*(.-)%s*$") or ""
    if #desc_str > 185 then
        desc_str = safe_utf8_truncate(desc_str, 180) .. "..."
    end

    local desc_widget = nil
    if desc_str ~= "" and desc_str ~= "---" then
        desc_widget = TextWidget:new{
            text = desc_str,
            face = Font:getFace("cfont", 15),
            fgcolor = Blitbuffer.Color8(40),
            max_width = inner_w,
        }
    end

    local text_items = {
        VerticalSpan:new{ width = sc(3) },
        title_row_widget,
    }
    if desc_widget then
        table.insert(text_items, VerticalSpan:new{ width = sc(1) })
        table.insert(text_items, desc_widget)
    end
    table.insert(text_items, VerticalSpan:new{ width = sc(3) })

    local main_vg = VerticalGroup:new(text_items)
    main_vg.align = "left"

    local is_card_focused = is_focused and (self.focus_zone == "cards")
    local main_vg_h = (main_vg.getSize and main_vg:getSize().h) or math.max(sc(24), row_h - sc(14))
    local row_frame = FrameContainer:new{
        padding = 0,
        bordersize = is_card_focused and sc(2) or 0,
        color = Blitbuffer.COLOR_BLACK,
        background = is_card_focused and Blitbuffer.Color8(210) or Blitbuffer.COLOR_WHITE,
        radius = is_card_focused and sc(4) or 0,
        width = content_w,
        height = row_h,
        CenterContainer:new{
            dimen = Geom:new{ w = content_w, h = row_h },
            LeftContainer:new{
                dimen = Geom:new{ w = inner_w, h = main_vg_h },
                main_vg,
            },
        }
    }

    local row_item = InputContainer:new{
        dimen = Geom:new{ w = content_w, h = row_h },
        row_frame,
    }
    row_item.overlay = self

    function row_item:getSize()
        return self.dimen
    end

    function row_item:paintTo(bb, x, y)
        self.dimen = Geom:new{ x = x, y = y, w = content_w, h = row_h }
        local ov = self.overlay
        local focused = (ov and ov.focus_zone == "cards" and ov.focused_index == idx)
        row_frame.bordersize = focused and sc(2) or 0
        row_frame.color = Blitbuffer.COLOR_BLACK
        row_frame.background = focused and Blitbuffer.Color8(210) or Blitbuffer.COLOR_WHITE
        row_frame.radius = focused and sc(4) or 0
        if self[1] then self[1]:paintTo(bb, x, y) end
    end

    row_item.ges_events = {
        Tap = {
            GestureRange:new{
                ges = "tap",
                range = function() return row_item.dimen end,
            }
        }
    }

    row_item.onTap = function()
        local ov = self
        ov.focus_zone = nil
        ov.focused_index = nil
        if ov.onItemSelect then
            ov:onItemSelect(item)
        end
        return true
    end

    return row_item
end

function EntityListOverlay:onItemSelect(item)
    local p = self.plugin
    if not p then return end
    if self.mode == "characters" then
        p:showCharacterDetails(item, { source = "menu" })
    elseif self.mode == "terms" then
        p:showTermDetails(item, { source = "menu" })
    elseif self.mode == "locations" then
        p:showLocationDetails(item, { source = "menu" })
    elseif self.mode == "historical_figures" then
        p:showHistoricalFigureDetails(item, { source = "menu" })
    elseif self.mode == "timeline" then
        p:showTimelineEventDetails(item, { source = "menu" })
    elseif self.mode == "linked_entries" then
        local actual_item = item.item or item
        local item_type = item.type
        local opts = self.opts or { source = "menu" }
        if item_type == "character" then
            p:showCharacterDetails(actual_item, opts)
        elseif item_type == "location" then
            p:showLocationDetails(actual_item, opts)
        elseif item_type == "historical" then
            p:showHistoricalFigureDetails(actual_item, opts)
        elseif item_type == "term" then
            p:showTermDetails(actual_item, opts)
        end
    elseif self.mode == "mentions" then
        local return_pg = p.return_page_origin
        if not return_pg and p then
            if p.getCurrentPage then
                local ok, val = pcall(function() return p:getCurrentPage() end)
                if ok and val then return_pg = val end
            end
            if not return_pg and p.ui then
                if p.ui.getCurrentPage then
                    local ok, val = pcall(function() return p.ui:getCurrentPage() end)
                    if ok and val then return_pg = val end
                elseif p.ui.paging and p.ui.paging.getCurrentPage then
                    local ok, val = pcall(function() return p.ui.paging:getCurrentPage() end)
                    if ok and val then return_pg = val end
                elseif p.ui.document and p.ui.document.getCurrentPage then
                    local ok, val = pcall(function() return p.ui.document:getCurrentPage() end)
                    if ok and val then return_pg = val end
                end
            end
            return_pg = return_pg or p.last_pageno or 1
        end
        p.return_page_origin = return_pg
        p.pending_return_banner = {
            return_page = return_pg,
            entity = self.entity,
            mentions = self.raw_items or {}
        }
        self:close()
        p:closeAllMenus()
        local Event = require("ui/event")
        UIManager:nextTick(function()
            if p.ui and p.ui.handleEvent then
                p.ui:handleEvent(Event:new("GotoPage", item.page))
            elseif p.ui and p.ui.document and p.ui.document.gotoPage then
                p.ui.document:gotoPage(item.page)
            end
        end)
    elseif self.mode == "evolution" then
        if item.is_locked then
            local InfoMessage = require("ui/widget/infomessage")
            UIManager:show(InfoMessage:new{
                text = "Locked by spoiler protection. Keep reading to unlock this milestone.",
                timeout = 3,
            })
            return
        end
        self.mode = "evolution_detail"
        self.current_page = item.idx or 1
        self:buildUI()
        UIManager:setDirty(self, "ui")
    end
end

local function createPillWidget(text, is_solid, is_accent, font_size)
    local bg = Blitbuffer.Color8(235)
    local fg = Blitbuffer.Color8(60)
    local border_color = Blitbuffer.Color8(180)
    if is_solid then
        bg = Blitbuffer.COLOR_BLACK
        fg = Blitbuffer.COLOR_WHITE
        border_color = Blitbuffer.COLOR_BLACK
    elseif is_accent then
        bg = Blitbuffer.Color8(220)
        fg = Blitbuffer.Color8(30)
        border_color = Blitbuffer.Color8(140)
    end
    local fs = font_size or 13
    return FrameContainer:new{
        background = bg,
        bordersize = sc(1),
        color = border_color,
        radius = sc(3),
        padding_top = sc(2),
        padding_bottom = sc(2),
        padding_left = sc(7),
        padding_right = sc(7),
        TextWidget:new{
            text = text,
            face = Font:getFace("cfont", fs),
            bold = true,
            fgcolor = fg,
        },
    }
end

function EntityListOverlay:renderEvolutionCard(item, content_w, card_h, is_focused, idx)
    local inner_w = content_w - sc(32)
    local is_card_focused = is_focused and (self.focus_zone == "cards")
    local book_fs = self:getBookFontSize()

    local card_ch_fs = math.max(15, math.min(17, book_fs - 5))
    local card_page_fs = math.max(12, math.min(14, book_fs - 9))
    local card_body_fs = math.max(13, math.min(15, book_fs - 8))
    local card_pill_fs = 11

    if item.is_locked then
        local lock_icon = ImageWidget:new{
            file = getAssetPath("lock.svg"),
            width = sc(16),
            height = sc(16),
            scale_factor = 0,
            is_icon = true,
            alpha = true,
        }
        local ch_str = item.chapter_title or (item.chapter_index and ("Ch. " .. tostring(item.chapter_index))) or ("Milestone " .. tostring(item.idx))
        local locked_str = string.format("%s · Hidden by spoiler protection", ch_str)
        local locked_w = TextWidget:new{
            text = locked_str,
            face = Font:getFace("cfont", card_ch_fs),
            bold = true,
            fgcolor = Blitbuffer.Color8(120),
            max_width = inner_w - sc(30),
        }
        local locked_row = HorizontalGroup:new{
            align = "center",
            lock_icon,
            HorizontalSpan:new{ width = sc(8) },
            locked_w,
        }
        local card_frame = FrameContainer:new{
            padding = 0,
            bordersize = is_card_focused and sc(2) or 0,
            color = Blitbuffer.COLOR_BLACK,
            background = is_card_focused and Blitbuffer.Color8(220) or Blitbuffer.Color8(248),
            radius = sc(4),
            width = content_w,
            height = card_h,
            CenterContainer:new{
                dimen = Geom:new{ w = content_w, h = card_h },
                LeftContainer:new{
                    dimen = Geom:new{ w = inner_w, h = card_h - sc(14) },
                    locked_row,
                },
            }
        }
        local card_item = makeTapItem(card_frame, function()
            self.focus_zone = nil
            self.focused_index = nil
            self:onItemSelect(item)
        end)
        card_item.dimen = Geom:new{ w = content_w, h = card_h }
        return card_item
    end

    -- 1. Chapter label formatting (deduplicate redundant "Ch. X · Chapter X")
    local ch_label
    local t = item.chapter_title
    local idx = item.chapter_index
    if idx and t and t ~= "" then
        local t_lower = t:lower():gsub("%s+", " "):match("^%s*(.-)%s*$") or ""
        local is_generic_ch = (t_lower == "chapter " .. tostring(idx))
            or (t_lower == "ch. " .. tostring(idx))
            or (t_lower == "ch " .. tostring(idx))
            or (t_lower == tostring(idx))
        if is_generic_ch then
            ch_label = string.format("Chapter %d", idx)
        else
            ch_label = string.format("Ch. %d · %s", idx, t)
        end
    elseif t and t ~= "" then
        ch_label = t
    elseif idx then
        ch_label = string.format("Chapter %d", idx)
    else
        ch_label = string.format("Milestone %d", item.idx)
    end

    local page_str = item.page and string.format("p. %d", item.page) or ""
    local page_w = TextWidget:new{
        text = page_str,
        face = Font:getFace("cfont", card_page_fs),
        bold = true,
        fgcolor = Blitbuffer.Color8(100),
    }
    local page_w_sz = (page_w.getSize and page_w:getSize())
    local page_size_w = (page_str ~= "") and (((page_w_sz and page_w_sz.w) or sc(36)) + sc(12)) or 0

    -- 2. Pills
    local pills = {}
    if item.idx == 1 then
        table.insert(pills, createPillWidget("FIRST SEEN", false, false, card_pill_fs))
    end
    if item.is_current then
        table.insert(pills, createPillWidget("CURRENT", true, false, card_pill_fs))
    end
    if item.role_from and item.role_from ~= "" and item.role and item.role ~= "" then
        table.insert(pills, createPillWidget(string.format("Role: %s → %s", item.role_from, item.role), false, true, card_pill_fs))
    end
    if item.status_from and item.status_from ~= "" and item.status and item.status ~= "" then
        table.insert(pills, createPillWidget(string.format("Status: %s → %s", item.status_from, item.status), false, true, card_pill_fs))
    end
    if item.kind == "key" and item.idx > 1 then
        table.insert(pills, createPillWidget("NEW DETAILS", false, false, card_pill_fs))
    elseif item.kind == "reworded" then
        table.insert(pills, createPillWidget("REWORDED", false, false, card_pill_fs))
    end

    local ch_w = TextWidget:new{
        text = ch_label,
        face = Font:getFace("cfont", card_ch_fs),
        bold = true,
        fgcolor = Blitbuffer.COLOR_BLACK,
    }
    local ch_sz = ch_w.getSize and ch_w:getSize()
    local ch_sz_w = (ch_sz and ch_sz.w) or (#ch_label * 9)

    local pills_w = 0
    for _, p_w in ipairs(pills) do
        local ps_sz = p_w.getSize and p_w:getSize()
        local ps = (ps_sz and ps_sz.w) or sc(60)
        pills_w = pills_w + ps + sc(6)
    end

    local pills_fit_inline = (#pills > 0) and ((ch_sz_w + pills_w + page_size_w) <= (inner_w - sc(8)))
    local left_elements = { ch_w }
    if pills_fit_inline then
        for _, p_w in ipairs(pills) do
            table.insert(left_elements, HorizontalSpan:new{ width = sc(6) })
            table.insert(left_elements, p_w)
        end
    end
    local left_group = HorizontalGroup:new(left_elements)
    left_group.align = "center"

    local top_row = OverlapGroup:new{
        dimen = Geom:new{ w = inner_w, h = sc(22) },
        LeftContainer:new{
            dimen = Geom:new{ w = inner_w - page_size_w, h = sc(22) },
            left_group,
        },
        RightContainer:new{
            dimen = Geom:new{ w = inner_w, h = sc(22) },
            page_w,
        },
    }

    -- 3. Body text (Change headline > Narrative description > New keywords)
    local body_str = ""
    if item.change and item.change ~= "" and item.change ~= "---" then
        body_str = item.change
    elseif item.description and item.description ~= "" and item.description ~= "---" then
        body_str = item.description
    elseif item.new_terms and #item.new_terms > 0 then
        body_str = "New: " .. table.concat(item.new_terms, " · ")
    end
    body_str = body_str:gsub("%s+", " "):match("^%s*(.-)%s*$") or ""
    if #body_str > 180 then
        body_str = safe_utf8_truncate(body_str, 175) .. "..."
    end

    local body_w = TextWidget:new{
        text = body_str,
        face = Font:getFace("cfont", card_body_fs),
        fgcolor = Blitbuffer.Color8(40),
        max_width = inner_w,
    }

    local card_vg_items = {
        top_row,
    }
    if #pills > 0 and not pills_fit_inline then
        local p_elements = {}
        for pi, p_w in ipairs(pills) do
            if pi > 1 then table.insert(p_elements, HorizontalSpan:new{ width = sc(6) }) end
            table.insert(p_elements, p_w)
        end
        local p_group = HorizontalGroup:new(p_elements)
        table.insert(card_vg_items, VerticalSpan:new{ width = sc(4) })
        table.insert(card_vg_items, p_group)
    end
    if body_str ~= "" then
        table.insert(card_vg_items, VerticalSpan:new{ width = sc(6) })
        table.insert(card_vg_items, body_w)
    end

    local card_vg = VerticalGroup:new(card_vg_items)
    card_vg.align = "left"

    local card_frame = FrameContainer:new{
        padding = 0,
        bordersize = is_card_focused and sc(2) or 0,
        color = Blitbuffer.COLOR_BLACK,
        background = is_card_focused and Blitbuffer.Color8(210) or Blitbuffer.Color8(248),
        radius = sc(4),
        width = content_w,
        height = card_h,
        CenterContainer:new{
            dimen = Geom:new{ w = content_w, h = card_h },
            LeftContainer:new{
                dimen = Geom:new{ w = inner_w, h = card_h - sc(14) },
                card_vg,
            },
        }
    }

    local card_item = makeTapItem(card_frame, function()
        self.focus_zone = nil
        self.focused_index = nil
        self:onItemSelect(item)
    end)
    card_item.dimen = Geom:new{ w = content_w, h = card_h }
    return card_item
end

function EntityListOverlay:buildEvolutionDetailUI()
    local sw = self.sw
    local sh = self.sh
    self.items_per_page = 1
    self.total_pages = #(self.items or {})
    if self.total_pages < 1 then self.total_pages = 1 end
    if self.current_page > self.total_pages then self.current_page = self.total_pages end
    if self.current_page < 1 then self.current_page = 1 end

    local cur_idx = self.current_page
    local cur_item = self.items and self.items[cur_idx]
    if not cur_item then
        self.mode = "evolution"
        self:buildUI()
        return
    end

    local inner_w = sw - sc(32)

    -- Header Bar
    local back_btn = createIconButton{
        icon = "chevron-left.svg",
        size = sc(30),
        width = sc(44),
        height = sc(44),
        allow_flash = false,
        callback = function()
            self.mode = "evolution"
            self:buildUI()
            UIManager:setDirty(self, "ui")
        end,
    }

    local book_fs = self:getBookFontSize()
    local name_fs = math.max(18, math.min(21, book_fs - 3))
    local info_fs = math.max(13, math.min(15, book_fs - 8))
    local section_hdr_fs = math.max(13, math.min(15, book_fs - 8))
    local body_fs = math.max(16, book_fs)
    local change_fs = math.max(15, book_fs - 2)
    local ev_fs = math.max(14, book_fs - 3)
    local pill_fs = 11
    local footer_fs = math.max(13, math.min(15, book_fs - 8))

    local name_str = (self.entity and self.entity.name) or "Entity"
    local name_w = TextWidget:new{
        text = name_str,
        face = Font:getFace("cfont", name_fs),
        bold = true,
        fgcolor = Blitbuffer.COLOR_BLACK,
        max_width = inner_w - sc(200),
    }

    local left_header = HorizontalGroup:new{
        align = "center",
        back_btn,
        HorizontalSpan:new{ width = sc(4) },
        name_w,
    }

    local ch_info_str
    if cur_item.chapter_index and cur_item.page then
        ch_info_str = string.format("Ch. %d · p. %d", cur_item.chapter_index, cur_item.page)
    elseif cur_item.chapter_title and cur_item.page then
        ch_info_str = string.format("%s · p. %d", cur_item.chapter_title, cur_item.page)
    elseif cur_item.chapter_index then
        ch_info_str = string.format("Ch. %d", cur_item.chapter_index)
    elseif cur_item.page then
        ch_info_str = string.format("p. %d", cur_item.page)
    else
        ch_info_str = string.format("Milestone %d", cur_idx)
    end

    local ch_info_w = TextWidget:new{
        text = ch_info_str,
        face = Font:getFace("cfont", info_fs),
        bold = true,
        fgcolor = Blitbuffer.Color8(90),
    }

    local close_btn = createIconButton{
        icon = "x.svg",
        size = sc(32),
        width = sc(48),
        height = sc(48),
        allow_flash = false,
        callback = function() self:close() end,
    }

    local right_elements = { ch_info_w, HorizontalSpan:new{ width = sc(6) }, close_btn }
    local right_header = HorizontalGroup:new(right_elements)
    right_header.align = "center"

    local header_row = OverlapGroup:new{
        dimen = Geom:new{ w = inner_w, h = sc(48) },
        LeftContainer:new{
            dimen = Geom:new{ w = inner_w - sc(120), h = sc(48) },
            left_header,
        },
        RightContainer:new{
            dimen = Geom:new{ w = inner_w, h = sc(48) },
            right_header,
        },
    }

    local header_frame = FrameContainer:new{
        padding_left = sc(16),
        padding_right = sc(16),
        padding_top = sc(10),
        padding_bottom = sc(4),
        bordersize = 0,
        width = sw,
        VerticalGroup:new{
            align = "left",
            header_row,
            VerticalSpan:new{ width = sc(4) },
            LineWidget:new{
                background = Blitbuffer.COLOR_DARK_GRAY,
                dimen = Geom:new{ w = inner_w, h = sc(1) },
            },
        }
    }

    -- Content items
    local content_items = {}

    if cur_item.is_locked then
        table.insert(content_items, VerticalSpan:new{ width = sc(20) })
        local lock_icon = ImageWidget:new{
            file = getAssetPath("lock.svg"),
            width = sc(32),
            height = sc(32),
            scale_factor = 0,
            is_icon = true,
            alpha = true,
        }
        table.insert(content_items, CenterContainer:new{
            dimen = Geom:new{ w = inner_w, h = sc(40) },
            lock_icon,
        })
        table.insert(content_items, VerticalSpan:new{ width = sc(12) })
        local locked_msg = TextBoxWidget:new{
            text = "This milestone is hidden by spoiler protection because it occurs beyond your current reading position.\n\nTap below to reveal future milestones for testing.",
            face = Font:getFace("cfont", math.max(16, book_fs - 2)),
            width = inner_w,
            alignment = "center",
            fgcolor = Blitbuffer.Color8(70),
        }
        table.insert(content_items, locked_msg)
    else
        -- Pills row
        local pills = {}
        if cur_item.idx == 1 then
            table.insert(pills, createPillWidget("FIRST SEEN", false, false, pill_fs))
        end
        if cur_item.is_current then
            table.insert(pills, createPillWidget("CURRENT", true, false, pill_fs))
        end
        if cur_item.role_from and cur_item.role_from ~= "" and cur_item.role and cur_item.role ~= "" then
            table.insert(pills, createPillWidget(string.format("Role: %s → %s", cur_item.role_from, cur_item.role), false, true, pill_fs))
        end
        if cur_item.status_from and cur_item.status_from ~= "" and cur_item.status and cur_item.status ~= "" then
            table.insert(pills, createPillWidget(string.format("Status: %s → %s", cur_item.status_from, cur_item.status), false, true, pill_fs))
        end
        if cur_item.kind == "key" and cur_item.idx > 1 then
            table.insert(pills, createPillWidget("NEW DETAILS", false, false, pill_fs))
        elseif cur_item.kind == "reworded" then
            table.insert(pills, createPillWidget("REWORDED", false, false, pill_fs))
        end

        if #pills > 0 then
            local p_elements = {}
            for pi, p_w in ipairs(pills) do
                if pi > 1 then table.insert(p_elements, HorizontalSpan:new{ width = sc(6) }) end
                table.insert(p_elements, p_w)
            end
            table.insert(content_items, HorizontalGroup:new(p_elements))
            table.insert(content_items, VerticalSpan:new{ width = sc(8) })
        end

        -- 1. WHAT CHANGED Section
        local change_lines = {}
        if cur_item.role_from and cur_item.role_from ~= "" and cur_item.role and cur_item.role ~= "" then
            table.insert(change_lines, string.format("• Role: %s → %s", cur_item.role_from, cur_item.role))
        end
        if cur_item.status_from and cur_item.status_from ~= "" and cur_item.status and cur_item.status ~= "" then
            table.insert(change_lines, string.format("• Status: %s → %s", cur_item.status_from, cur_item.status))
        end
        if cur_item.change and cur_item.change ~= "" and cur_item.change ~= "---" then
            table.insert(change_lines, "• " .. cur_item.change)
        end
        if cur_item.new_sentences and #cur_item.new_sentences > 0 then
            for _, s in ipairs(cur_item.new_sentences) do
                table.insert(change_lines, "+ " .. s)
            end
        end
        if #change_lines == 0 then
            if cur_item.kind == "reworded" then
                table.insert(change_lines, "Reworded only: no new facts recorded since the previous milestone.")
            elseif cur_idx == 1 then
                table.insert(change_lines, "Initial character introduction.")
            end
        end

        table.insert(content_items, TextWidget:new{
            text = "WHAT CHANGED",
            face = Font:getFace("cfont", section_hdr_fs),
            bold = true,
            fgcolor = Blitbuffer.Color8(90),
        })
        table.insert(content_items, VerticalSpan:new{ width = sc(2) })
        table.insert(content_items, LineWidget:new{
            background = Blitbuffer.Color8(200),
            dimen = Geom:new{ w = inner_w, h = sc(1) },
        })
        table.insert(content_items, VerticalSpan:new{ width = sc(4) })
        local change_box = TextBoxWidget:new{
            text = table.concat(change_lines, "\n"),
            face = Font:getFace("cfont", change_fs),
            width = inner_w,
            alignment = "left",
            fgcolor = Blitbuffer.COLOR_BLACK,
        }
        table.insert(content_items, change_box)
        table.insert(content_items, VerticalSpan:new{ width = sc(12) })

        -- 2. AT THIS POINT Section
        table.insert(content_items, TextWidget:new{
            text = "AT THIS POINT",
            face = Font:getFace("cfont", section_hdr_fs),
            bold = true,
            fgcolor = Blitbuffer.Color8(90),
        })
        table.insert(content_items, VerticalSpan:new{ width = sc(2) })
        table.insert(content_items, LineWidget:new{
            background = Blitbuffer.Color8(200),
            dimen = Geom:new{ w = inner_w, h = sc(1) },
        })
        table.insert(content_items, VerticalSpan:new{ width = sc(4) })

        local desc_text = cur_item.description or ""
        local max_chars = 900
        local is_truncated = false
        if #desc_text > max_chars then
            desc_text = safe_utf8_truncate(desc_text, max_chars) .. "..."
            is_truncated = true
        end

        local desc_fs = (#desc_text > 550) and math.max(16, book_fs - 2) or body_fs
        local desc_box = TextBoxWidget:new{
            text = desc_text,
            face = Font:getFace("cfont", desc_fs),
            width = inner_w,
            alignment = "left",
            fgcolor = Blitbuffer.COLOR_BLACK,
        }
        table.insert(content_items, desc_box)

        if is_truncated then
            table.insert(content_items, VerticalSpan:new{ width = sc(4) })
            local read_more_frame = FrameContainer:new{
                padding = sc(4),
                padding_left = sc(10),
                padding_right = sc(10),
                bordersize = sc(1),
                color = Blitbuffer.COLOR_BLACK,
                background = Blitbuffer.Color8(235),
                radius = sc(3),
                TextWidget:new{
                    text = "Read Full Description...",
                    face = Font:getFace("cfont", math.max(14, book_fs - 4)),
                    bold = true,
                    fgcolor = Blitbuffer.COLOR_BLACK,
                }
            }
            local read_more_btn = makeTapItem(read_more_frame, function()
                local TextViewer = require("ui/widget/textviewer")
                UIManager:show(TextViewer:new{
                    modal = true,
                    title = name_str .. " - " .. ch_info_str,
                    text = cur_item.description or "",
                })
            end)
            table.insert(content_items, read_more_btn)
        end

        -- 3. EVIDENCE Section (if present)
        if cur_item.evidence and cur_item.evidence ~= "" and cur_item.evidence ~= "---" then
            table.insert(content_items, VerticalSpan:new{ width = sc(12) })
            table.insert(content_items, TextWidget:new{
                text = "EVIDENCE",
                face = Font:getFace("cfont", section_hdr_fs),
                bold = true,
                fgcolor = Blitbuffer.Color8(90),
            })
            table.insert(content_items, VerticalSpan:new{ width = sc(2) })
            table.insert(content_items, LineWidget:new{
                background = Blitbuffer.Color8(200),
                dimen = Geom:new{ w = inner_w, h = sc(1) },
            })
            table.insert(content_items, VerticalSpan:new{ width = sc(4) })
            local ev_clean = cur_item.evidence:gsub('^"(.*)"$', '%1')
            local ev_box = TextBoxWidget:new{
                text = "“" .. ev_clean .. "”",
                face = Font:getFace("cfont", ev_fs),
                width = inner_w,
                alignment = "left",
                fgcolor = Blitbuffer.Color8(60),
            }
            table.insert(content_items, ev_box)
        end
    end

    local detail_vg = VerticalGroup:new(content_items)
    detail_vg.align = "left"

    local content_frame = FrameContainer:new{
        padding_left = sc(16),
        padding_right = sc(16),
        padding_top = sc(8),
        bordersize = 0,
        width = sw,
        detail_vg,
    }

    -- Footer Bar (Milestone X of Y)
    local footer_h = sc(48)
    local prev_btn = createIconButton{
        icon = "chevron-left.svg",
        size = sc(30),
        width = sc(44),
        height = sc(42),
        allow_flash = false,
        callback = function()
            if self.is_touch_device then self.focus_zone = nil end
            self:onPrevPage()
        end,
    }

    local milestone_label = TextWidget:new{
        text = string.format("Milestone %d of %d", self.current_page, math.max(1, self.total_pages)),
        face = Font:getFace("cfont", footer_fs),
        bold = true,
        fgcolor = Blitbuffer.COLOR_BLACK,
    }

    local milestone_frame = FrameContainer:new{
        padding_top = sc(4),
        padding_bottom = sc(4),
        padding_left = sc(10),
        padding_right = sc(10),
        bordersize = 0,
        radius = sc(4),
        milestone_label,
    }

    local milestone_item = makeTapItem(milestone_frame, function()
        if self.is_touch_device then self.focus_zone = nil end
        self:onJumpPage()
    end)

    local next_btn = createIconButton{
        icon = "chevron-right.svg",
        size = sc(30),
        width = sc(44),
        height = sc(42),
        allow_flash = false,
        callback = function()
            if self.is_touch_device then self.focus_zone = nil end
            self:onNextPage()
        end,
    }

    local footer_group = HorizontalGroup:new{
        align = "center",
        prev_btn,
        HorizontalSpan:new{ width = sc(16) },
        milestone_item,
        HorizontalSpan:new{ width = sc(16) },
        next_btn,
    }

    local footer_frame = FrameContainer:new{
        padding_top = 0,
        padding_bottom = 0,
        bordersize = 0,
        width = sw,
        height = footer_h,
        VerticalGroup:new{
            align = "left",
            CenterContainer:new{
                dimen = Geom:new{ w = sw, h = sc(1) },
                LineWidget:new{
                    background = Blitbuffer.Color8(180),
                    dimen = Geom:new{ w = sw - sc(32), h = sc(1) },
                },
            },
            CenterContainer:new{
                dimen = Geom:new{ w = sw, h = footer_h - sc(1) },
                footer_group,
            },
        }
    }

    local main_surface = FrameContainer:new{
        padding = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        width = sw,
        height = sh,
        VerticalGroup:new{
            align = "left",
            header_frame,
            content_frame,
        }
    }

    local bottom_pinned_footer = BottomContainer:new{
        dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh },
        footer_frame,
    }

    self[1] = OverlapGroup:new{
        dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh },
        main_surface,
        bottom_pinned_footer,
    }
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
end

function EntityListOverlay:buildUI()
    if self.mode == "evolution_detail" then
        self:buildEvolutionDetailUI()
        return
    end

    local sw = self.sw
    local sh = self.sh
    local p = self.plugin
    local loc = p and p.loc

    -- ── 1. Top Header Bar (Storefront style touch buttons) ────────────────────
    local btn_size = sc(32)
    local btn_w = sc(48)
    local btn_h = sc(48)
    local btn_gap = sc(4)

    local title_text_str = "Characters"
    if self.mode == "evolution" then
        local ent_name = (self.entity and self.entity.name) or "Entity"
        local title_tmpl = (loc and loc:t("evolution_title")) or "Story Arc: %s"
        if title_tmpl == "evolution_title" then title_tmpl = "Story Arc: %s" end
        title_text_str = title_tmpl:format(ent_name)
    elseif self.mode == "terms" then
        title_text_str = (loc and loc:t("menu_terms")) or "Glossary"
    elseif self.mode == "locations" then
        title_text_str = (loc and loc:t("menu_locations")) or "Locations"
    elseif self.mode == "historical_figures" then
        title_text_str = (loc and loc:t("menu_historical_figures")) or "Historical Figures"
    elseif self.mode == "timeline" then
        title_text_str = (loc and loc:t("menu_timeline")) or "Timeline"
    elseif self.mode == "mentions" then
        local ent_name = (self.entity and self.entity.name) or "Entity"
        local title_tmpl = (loc and loc:t("mentions_title")) or "Mentions: %s"
        if title_tmpl == "mentions_title" then title_tmpl = "Mentions: %s" end
        title_text_str = title_tmpl:format(ent_name)
    elseif self.mode == "linked_entries" then
        local ent_name = (self.entity and (self.entity.name or self.entity.chapter)) or nil
        if ent_name and ent_name ~= "" then
            local title_tmpl = (loc and loc:t("linked_with_title")) or "Linked with: %s"
            if title_tmpl == "linked_with_title" then title_tmpl = "Linked with: %s" end
            title_text_str = title_tmpl:format(ent_name)
        else
            title_text_str = (loc and loc:t("linked_entries")) or "Linked Entries"
        end
    else
        title_text_str = (loc and loc:t("menu_characters")) or "Characters"
    end

    local is_scanning = (self.mode == "mentions") and p and p.active_mention_scan and p.active_mention_scan.entity_name == (self.entity and self.entity.name)
    local total_count = self.unfiltered_visible_count or #(self.items or {})
    local header_title
    if is_scanning then
        header_title = title_text_str .. " (Scanning... " .. tostring(p.active_mention_scan.chapter_idx or 0) .. "/" .. tostring(p.active_mention_scan.total_chapters or 0) .. ")"
    else
        header_title = title_text_str .. " (" .. tostring(total_count) .. ")"
    end
    self.title = header_title

    -- Header actions (Feather icon buttons, touch targets)
    self.current_header_actions = {}
    local action_btns = {}

    local function addHeaderAction(id, icon, callback)
        table.insert(self.current_header_actions, { id = id, callback = callback })
        local btn_idx = #self.current_header_actions
        local is_focused = (self.focus_zone == "header" and self.header_focus_idx == btn_idx)
        if btn_idx > 1 then
            table.insert(action_btns, HorizontalSpan:new{ width = btn_gap })
        end
        table.insert(action_btns, createIconButton{
            icon = icon,
            size = btn_size,
            width = btn_w,
            height = btn_h,
            is_focused = is_focused,
            allow_flash = (id ~= "close"),
            callback = function()
                if self.is_touch_device then self.focus_zone = nil end
                callback()
            end,
        })
    end

    if self.mode == "evolution" then
        -- Filter button (Key vs All snapshots)
        addHeaderAction("filter", "filter.svg", function() self:showEvolutionFilterDialog() end)
    else
        -- A. Search button
        addHeaderAction("search", "search.svg", function() self:showSearchDialog() end)

        if self.mode == "mentions" then
            -- Refresh mentions button
            addHeaderAction("refresh", "rotate-cw.svg", function()
                if p then
                    if p.active_mention_scan and p.active_mention_scan.cancel_handle then
                        p.active_mention_scan.cancel_handle:cancel()
                    end
                    p.active_mention_scan = nil
                    if self.entity then
                        self.entity.mentions = {}
                        self.entity.last_mention_page = nil
                        p:showMentionsForEntity(self.entity)
                    end
                end
            end)
        else
            -- B. Merge Duplicates button (characters and locations only)
            if self.mode == "characters" or self.mode == "locations" then
                addHeaderAction("merge", "git-merge.svg", function() self:showMergeDialog() end)
            end

            -- C. Fetch More button (Characters & Terms; Timeline specifically omits it per user requirement)
            if self.mode == "characters" or self.mode == "terms" then
                addHeaderAction("fetch", "plus.svg", function()
                    if self.mode == "characters" then
                        p:fetchMoreCharacters()
                    elseif self.mode == "terms" then
                        p:fetchMoreTerms()
                    end
                end)
            end

            -- D. Sort button (Sliders icon from Feather Icons)
            if self.mode ~= "timeline" or (p and p.isAnthologyMode and p:isAnthologyMode()) then
                addHeaderAction("sort", "sliders.svg", function() self:showSortDialog() end)
            end
        end
    end

    -- Close button (x.svg from Feather Icons, allow_flash=false)
    addHeaderAction("close", "x.svg", function() self:close() end)

    local header_actions_group = HorizontalGroup:new(action_btns)
    header_actions_group.align = "center"

    local is_filtered = (self.search_query and self.search_query ~= "")
    local num_btns = #self.current_header_actions
    local total_btns_w = num_btns * btn_w + math.max(0, num_btns - 1) * btn_gap
    local row_w = sw - sc(32)
    local title_container_w = row_w - total_btns_w - sc(12)
    local title_max_w = math.max(sc(140), title_container_w)

    local book_fs = self:getBookFontSize()
    local title_w = TextWidget:new{
        text = header_title,
        face = Font:getFace("cfont", is_filtered and math.max(16, math.min(18, book_fs - 5)) or math.max(18, math.min(21, book_fs - 3))),
        bold = true,
        fgcolor = Blitbuffer.COLOR_BLACK,
        max_width = title_max_w,
    }

    local title_left_widget
    if is_filtered then
        local sub_info = "Filter: \"" .. self.search_query .. "\" (" .. tostring(#(self.items or {})) .. " matches)"
        local sub_w = TextWidget:new{
            text = sub_info,
            face = Font:getFace("cfont", math.max(12, math.min(13, book_fs - 9))),
            fgcolor = Blitbuffer.Color8(85),
            max_width = title_max_w,
        }
        title_left_widget = VerticalGroup:new{
            align = "left",
            title_w,
            VerticalSpan:new{ width = sc(2) },
            sub_w,
        }
    else
        title_left_widget = title_w
    end

    local header_row = OverlapGroup:new{
        dimen = Geom:new{ w = row_w, h = sc(52) },
        LeftContainer:new{
            dimen = Geom:new{ w = title_container_w, h = sc(52) },
            title_left_widget,
        },
        RightContainer:new{
            dimen = Geom:new{ w = row_w, h = sc(52) },
            header_actions_group,
        },
    }

    local header_frame = FrameContainer:new{
        padding_left = sc(16),
        padding_right = sc(16),
        padding_top = sc(12),
        padding_bottom = sc(6),
        bordersize = 0,
        width = sw,
        VerticalGroup:new{
            align = "left",
            header_row,
            VerticalSpan:new{ width = sc(6) },
            LineWidget:new{
                background = Blitbuffer.COLOR_DARK_GRAY,
                dimen = Geom:new{ w = sw - sc(32), h = sc(1) },
            },
        }
    }

    -- ── 2. Content Height Budgeting & Pagination ──────────────────────────────
    local header_h = header_frame:getSize().h
    local footer_h = sc(48)
    local avail_content_h = sh - header_h - footer_h

    local is_timeline = (self.mode == "timeline")
    local is_mentions = (self.mode == "mentions")
    local is_evolution = (self.mode == "evolution")
    local row_h = is_evolution and sc(72) or sc(64)
    local divider_h = sc(1)
    local items_per_page = math.max(1, math.floor(avail_content_h / (row_h + divider_h)))

    -- Check if we have anthology sections or prior-book events in timeline
    local display_items = {}
    local is_anthology = p and p.isAnthologyMode and p:isAnthologyMode()
    if is_anthology and not is_mentions and not is_evolution then
        display_items = self:buildStorySections(self.items or {})
    elseif is_timeline then
        local has_prior = false
        local prior_count = 0
        for _, it in ipairs(self.items or {}) do
            if it.source == "series_prior" then
                has_prior = true
                prior_count = prior_count + 1
            end
        end
        if has_prior then
            table.insert(display_items, {
                is_prior_header = true,
                collapsed = self.prior_collapsed,
                count = prior_count,
            })
        end
        for _, it in ipairs(self.items or {}) do
            if it.source == "series_prior" then
                if not self.prior_collapsed then
                    table.insert(display_items, it)
                end
            end
        end
        if has_prior and not self.prior_collapsed then
            local has_current = false
            for _, it in ipairs(self.items or {}) do
                if it.source ~= "series_prior" then
                    has_current = true
                    break
                end
            end
            if has_current then
                local doc_props = (self.ui and self.ui.document and self.ui.document.getProps and self.ui.document:getProps())
                    or (self.plugin and self.plugin.ui and self.plugin.ui.document and self.plugin.ui.document.getProps and self.plugin.ui.document:getProps())
                local cur_book_title = (self.plugin and self.plugin.book_data and (self.plugin.book_data.book_title or self.plugin.book_data.title))
                    or (doc_props and doc_props.title)
                local cur_header_title = (cur_book_title and cur_book_title ~= "") and ("Current Book: " .. cur_book_title) or "Current Book Timeline"
                table.insert(display_items, {
                    is_current_header = true,
                    title = cur_header_title,
                })
            end
        end
        for _, it in ipairs(self.items or {}) do
            if it.source ~= "series_prior" then
                table.insert(display_items, it)
            end
        end
    else
        display_items = self.items or {}
    end

    local total_display = #display_items
    local pages = {}
    local cur_page_items = {}
    local cur_page_h = 0
    local section_header_h = sc(38) + sc(1)
    local card_h = row_h + divider_h

    for idx, it in ipairs(display_items) do
        local is_sec = it.is_section_header or it.is_prior_header or it.is_current_header
        local it_h = is_sec and section_header_h or card_h

        -- Prevent orphan headers: if a section header cannot fit with at least 1 card beneath it, move it to next page
        local is_orphan = is_sec and (#cur_page_items > 0) and (cur_page_h + it_h + card_h > avail_content_h)

        if #cur_page_items > 0 and (is_orphan or (cur_page_h + it_h > avail_content_h)) then
            table.insert(pages, cur_page_items)
            cur_page_items = {}
            cur_page_h = 0
        end

        table.insert(cur_page_items, it)
        cur_page_h = cur_page_h + it_h
    end

    if #cur_page_items > 0 then
        table.insert(pages, cur_page_items)
    end
    if #pages == 0 then pages = {{}} end

    self.total_pages = #pages

    if self._anchor_section_id then
        for p_idx, p_items in ipairs(pages) do
            local found = false
            for item_idx, item in ipairs(p_items) do
                if item.is_section_header and item.section_id == self._anchor_section_id then
                    self.current_page = p_idx
                    self.focused_index = item_idx
                    found = true
                    break
                end
            end
            if found then break end
        end
    elseif self._anchor_prior_header then
        for p_idx, p_items in ipairs(pages) do
            local found = false
            for item_idx, item in ipairs(p_items) do
                if item.is_prior_header then
                    self.current_page = p_idx
                    self.focused_index = item_idx
                    found = true
                    break
                end
            end
            if found then break end
        end
    end

    if self.current_page > self.total_pages then self.current_page = self.total_pages end
    if self.current_page < 1 then self.current_page = 1 end

    local page_items = pages[self.current_page] or {}
    self.current_page_items = page_items

    local page_content_vg = VerticalGroup:new{ align = "left" }

    if total_display == 0 then
        local empty_str = (loc and loc:t("no_items")) or "No items found"
        if self.mode == "mentions" then
            if is_scanning then
                local scan_tmpl = (loc and loc:t("mentions_scanning")) or "Scanning... %1 of %2 chapters"
                if scan_tmpl == "mentions_scanning" then scan_tmpl = "Scanning... %1 of %2 chapters" end
                empty_str = scan_tmpl:gsub("%%1", tostring(p.active_mention_scan.chapter_idx or 0)):gsub("%%2", tostring(p.active_mention_scan.total_chapters or 0))
            else
                local none_tmpl = (loc and loc:t("mentions_none")) or "No mentions found for '%s' yet."
                if none_tmpl == "mentions_none" then none_tmpl = "No mentions found for '%s' yet." end
                empty_str = none_tmpl:format((self.entity and self.entity.name) or "this entity")
            end
        elseif self.mode == "linked_entries" then
            local ent_name = (self.entity and (self.entity.name or self.entity.chapter)) or nil
            if ent_name and ent_name ~= "" then
                local none_tmpl = (loc and loc:t("linked_none")) or "No linked entries found for '%s'."
                if none_tmpl == "linked_none" then none_tmpl = "No linked entries found for '%s'." end
                empty_str = none_tmpl:format(ent_name)
            else
                empty_str = (loc and loc:t("no_linked_entries")) or "No linked entries found"
            end
        elseif self.search_query and self.search_query ~= "" then
            empty_str = "No items matching \"" .. self.search_query .. "\""
        end
        local empty_w = TextWidget:new{
            text = empty_str,
            face = Font:getFace("cfont", 16),
            fgcolor = Blitbuffer.COLOR_DARK_GRAY,
        }
        if self.mode == "mentions" and is_scanning then
            local cancel_btn_frame = FrameContainer:new{
                padding = sc(8),
                padding_left = sc(20),
                padding_right = sc(20),
                bordersize = sc(1),
                color = Blitbuffer.COLOR_BLACK,
                background = Blitbuffer.Color8(235),
                radius = sc(4),
                TextWidget:new{
                    text = (loc and loc:t("cancel_scan")) or (loc and loc:t("cancel")) or "Cancel Scan",
                    face = Font:getFace("cfont", 16),
                    fgcolor = Blitbuffer.COLOR_BLACK,
                    bold = true,
                }
            }
            local cancel_btn = makeTapItem(cancel_btn_frame, function()
                if p and p.active_mention_scan and p.active_mention_scan.cancel_handle then
                    p.active_mention_scan.cancel_handle:cancel()
                end
                if p then p.active_mention_scan = nil end
                self:prepareItems()
                self:buildUI()
                UIManager:setDirty(self, "ui")
            end)
            local center_vg = VerticalGroup:new{
                align = "center",
                empty_w,
                VerticalSpan:new{ width = sc(16) },
                cancel_btn,
            }
            table.insert(page_content_vg, CenterContainer:new{
                dimen = Geom:new{ w = sw, h = avail_content_h },
                center_vg,
            })
        else
            table.insert(page_content_vg, CenterContainer:new{
                dimen = Geom:new{ w = sw, h = avail_content_h },
                empty_w,
            })
        end
    else
        for idx, it in ipairs(page_items) do
            if it.is_prior_header or it.is_section_header then
                -- Collapsible section row (Prior Books or Anthology Story Groups)
                local icon_name = it.collapsed and "chevron-right.svg" or "chevron-down.svg"
                local chevron_icon = ImageWidget:new{
                    file = getAssetPath(icon_name),
                    width = sc(18),
                    height = sc(18),
                    scale_factor = 0,
                    is_icon = true,
                    alpha = true,
                }
                local header_title
                if it.is_prior_header then
                    local raw_header = (loc and loc:t("series_prior_books_header")) or "Prior Books in Series"
                    local clean_header = raw_header:gsub("^%s*[─%-–—]+%s*", ""):gsub("%s*[─%-–—]+%s*$", "")
                    if clean_header == "" or clean_header:lower() == "prior books" then
                        clean_header = "Prior Books in Series"
                    end
                    header_title = string.format("%s (%d)", clean_header, it.count or 0)
                else
                    header_title = string.format("%s (%d)", it.title or "Section", it.count or 0)
                end
                local sec_txt = TextWidget:new{
                    text = header_title,
                    face = Font:getFace("cfont", 15),
                    bold = true,
                    fgcolor = Blitbuffer.COLOR_BLACK,
                }
                local sec_row = HorizontalGroup:new{
                    align = "center",
                    chevron_icon,
                    HorizontalSpan:new{ width = sc(8) },
                    sec_txt,
                }
                local is_sec_focused = (self.focus_zone == "cards" and idx == self.focused_index)
                local sec_frame = FrameContainer:new{
                    padding = 0,
                    padding_left = sc(16),
                    padding_right = sc(16),
                    bordersize = is_sec_focused and sc(2) or 0,
                    color = Blitbuffer.COLOR_BLACK,
                    background = is_sec_focused and Blitbuffer.Color8(220) or Blitbuffer.Color8(240),
                    width = sw,
                    height = sc(38),
                    LeftContainer:new{
                        dimen = Geom:new{ w = sw - sc(32), h = sc(38) },
                        sec_row,
                    },
                }
                local sec_item = makeTapItem(sec_frame, function()
                    if self.is_touch_device then self.focus_zone = nil end
                    if it.is_prior_header then
                        self:togglePriorSection()
                    elseif it.is_section_header and it.section_id then
                        self:toggleSection(it.section_id)
                    end
                end)
                sec_item.onBeforePaint = function()
                    local focused = (self.focus_zone == "cards" and idx == self.focused_index)
                    sec_frame.bordersize = focused and sc(2) or 0
                    sec_frame.color = Blitbuffer.COLOR_BLACK
                    sec_frame.background = focused and Blitbuffer.Color8(220) or Blitbuffer.Color8(240)
                end
                table.insert(page_content_vg, sec_item)
                if idx < #page_items then
                    table.insert(page_content_vg, CenterContainer:new{
                        dimen = Geom:new{ w = sw, h = sc(1) },
                        LineWidget:new{
                            background = Blitbuffer.Color8(180),
                            dimen = Geom:new{ w = sw - sc(32), h = sc(1) },
                        },
                    })
                end
            elseif it.is_current_header then
                local cur_txt = TextWidget:new{
                    text = it.title or "Current Book Timeline",
                    face = Font:getFace("cfont", 15),
                    bold = true,
                    fgcolor = Blitbuffer.COLOR_BLACK,
                    max_width = sw - sc(32),
                }
                local is_cur_focused = (self.focus_zone == "cards" and idx == self.focused_index)
                local cur_frame = FrameContainer:new{
                    padding = 0,
                    padding_left = sc(16),
                    padding_right = sc(16),
                    bordersize = is_cur_focused and sc(2) or 0,
                    color = Blitbuffer.COLOR_BLACK,
                    background = is_cur_focused and Blitbuffer.Color8(220) or Blitbuffer.Color8(240),
                    width = sw,
                    height = sc(36),
                    LeftContainer:new{
                        dimen = Geom:new{ w = sw - sc(32), h = sc(36) },
                        cur_txt,
                    },
                }
                local cur_item = makeTapItem(cur_frame, function()
                    -- Static transition header
                end)
                cur_item.onBeforePaint = function()
                    local focused = (self.focus_zone == "cards" and idx == self.focused_index)
                    cur_frame.bordersize = focused and sc(2) or 0
                    cur_frame.color = Blitbuffer.COLOR_BLACK
                    cur_frame.background = focused and Blitbuffer.Color8(220) or Blitbuffer.Color8(240)
                end
                table.insert(page_content_vg, cur_item)
                if idx < #page_items then
                    table.insert(page_content_vg, CenterContainer:new{
                        dimen = Geom:new{ w = sw, h = sc(1) },
                        LineWidget:new{
                            background = Blitbuffer.Color8(180),
                            dimen = Geom:new{ w = sw - sc(32), h = sc(1) },
                        },
                    })
                end
            else
                local is_focused = (self.focus_zone == "cards" and idx == self.focused_index)
                local row_widget
                if self.mode == "evolution" then
                    row_widget = self:renderEvolutionCard(it, sw, row_h, is_focused, idx)
                else
                    row_widget = self:renderRow(it, sw, row_h, is_focused, idx)
                end
                table.insert(page_content_vg, row_widget)
                if idx < #page_items then
                    table.insert(page_content_vg, CenterContainer:new{
                        dimen = Geom:new{ w = sw, h = sc(1) },
                        LineWidget:new{
                            background = Blitbuffer.Color8(180),
                            dimen = Geom:new{ w = sw - sc(32), h = sc(1) },
                        },
                    })
                end
            end
        end
    end

    local list_frame = FrameContainer:new{
        padding = 0,
        bordersize = 0,
        width = sw,
        page_content_vg,
    }

    -- ── 3. Footer Bar with Storefront Pagination ──────────────────────────────
    local nav_btn_size = sc(30)
    local nav_btn_w = sc(44)
    local nav_btn_h = sc(42)

    local is_prev_focused = (self.focus_zone == "footer" and self.footer_focus_idx == 1)
    local is_page_focused = (self.focus_zone == "footer" and self.footer_focus_idx == 2)
    local is_next_focused = (self.focus_zone == "footer" and self.footer_focus_idx == 3)

    local prev_btn = createIconButton{
        icon = "chevron-left.svg",
        size = nav_btn_size,
        width = nav_btn_w,
        height = nav_btn_h,
        is_focused = is_prev_focused,
        allow_flash = false,
        callback = function()
            if self.is_touch_device then self.focus_zone = nil end
            self:onPrevPage()
        end,
    }

    local page_label = TextWidget:new{
        text = string.format("Page %d of %d", self.current_page, math.max(1, self.total_pages)),
        face = Font:getFace("cfont", math.max(13, math.min(15, book_fs - 8))),
        bold = true,
        fgcolor = Blitbuffer.COLOR_BLACK,
    }

    local page_frame = FrameContainer:new{
        padding_top = sc(4),
        padding_bottom = sc(4),
        padding_left = sc(10),
        padding_right = sc(10),
        bordersize = 0,
        background = is_page_focused and Blitbuffer.Color8(240) or nil,
        radius = sc(4),
        page_label,
    }

    local page_item = makeTapItem(page_frame, function()
        if self.is_touch_device then self.focus_zone = nil end
        self:onJumpPage()
    end)

    local next_btn = createIconButton{
        icon = "chevron-right.svg",
        size = nav_btn_size,
        width = nav_btn_w,
        height = nav_btn_h,
        is_focused = is_next_focused,
        allow_flash = false,
        callback = function()
            if self.is_touch_device then self.focus_zone = nil end
            self:onNextPage()
        end,
    }

    local footer_group = HorizontalGroup:new{
        align = "center",
        prev_btn,
        HorizontalSpan:new{ width = sc(16) },
        page_item,
        HorizontalSpan:new{ width = sc(16) },
        next_btn,
    }

    local footer_divider = CenterContainer:new{
        dimen = Geom:new{ w = sw, h = sc(1) },
        LineWidget:new{
            background = Blitbuffer.Color8(180),
            dimen = Geom:new{ w = sw - sc(32), h = sc(1) },
        },
    }

    local footer_frame = FrameContainer:new{
        padding_top = 0,
        padding_bottom = 0,
        bordersize = 0,
        width = sw,
        height = footer_h,
        VerticalGroup:new{
            align = "left",
            footer_divider,
            CenterContainer:new{
                dimen = Geom:new{ w = sw, h = footer_h - sc(1) },
                footer_group,
            },
        }
    }

    -- ── Overall Fullscreen Assembly ───────────────────────────────────────────
    local main_surface = FrameContainer:new{
        padding = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        width = sw,
        height = sh,
        VerticalGroup:new{
            align = "left",
            header_frame,
            list_frame,
        }
    }

    local bottom_pinned_footer = BottomContainer:new{
        dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh },
        footer_frame,
    }

    self[1] = OverlapGroup:new{
        dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh },
        main_surface,
        bottom_pinned_footer,
    }
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
end

return EntityListOverlay
