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
    local icon_size = opts.size or sc(24)
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
    mode = "characters", -- "characters", "terms", "locations", "historical_figures", "timeline", "mentions", "linked_entries"
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
}

function EntityListOverlay:init()
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

    self:prepareItems()
    self:buildUI()
end

local function getFirstAppearancePage(entity)
    if not entity then return 999999 end
    if tonumber(entity.first_page) and tonumber(entity.first_page) > 0 then
        return tonumber(entity.first_page)
    end
    if tonumber(entity.page) and tonumber(entity.page) > 0 then
        return tonumber(entity.page)
    end
    local min_p = 999999
    if entity.mentions and type(entity.mentions) == "table" and #entity.mentions > 0 then
        for _, m in ipairs(entity.mentions) do
            local p = tonumber(m.page)
            if p and p > 0 and p < min_p then
                min_p = p
            end
        end
    end
    if min_p < 999999 then return min_p end
    if entity.history and type(entity.history) == "table" and #entity.history > 0 then
        for _, h in ipairs(entity.history) do
            local p = tonumber(h.page)
            if p and p > 0 and p < min_p then
                min_p = p
            end
        end
    end
    return min_p
end

function EntityListOverlay:prepareItems()
    local raw = self.raw_items or {}
    local entries = {}

    -- Apply search query if present
    local q = (self.search_query and self.search_query ~= "") and self.search_query:lower() or nil
    for idx, it in ipairs(raw) do
        local entity = (self.mode == "linked_entries" and it.item) or it
        local name = (entity.name or entity.chapter or ""):lower()
        local desc = (entity.description or entity.definition or entity.biography or entity.event or entity.snippet or ""):lower()
        if not q or (name:find(q, 1, true) or desc:find(q, 1, true)) then
            table.insert(entries, { item = it, _orig_idx = idx })
        end
    end

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
                local pa = getFirstAppearancePage(ea)
                local pb = getFirstAppearancePage(eb)
                if pa ~= pb then
                    return pa < pb
                end
                local oa = tonumber(ea.sort_order)
                local ob = tonumber(eb.sort_order)
                if oa and ob and oa ~= ob then
                    return oa < ob
                elseif oa and not ob then
                    return true
                elseif ob and not oa then
                    return false
                end
                return a._orig_idx < b._orig_idx
            end)
        else
            -- Default: Frequency of mentions
            table.sort(entries, function(a, b)
                local ea = (self.mode == "linked_entries" and a.item.item) or a.item
                local eb = (self.mode == "linked_entries" and b.item.item) or b.item

                -- 1. Real mention count if mentions have been scanned
                local ma = (ea.mentions and #ea.mentions) or 0
                local mb = (eb.mentions and #eb.mentions) or 0
                if ma ~= mb then
                    return ma > mb
                end

                -- 2. sort_order stamped during AI frequency analysis / cache load (1, 2, 3...)
                local oa = tonumber(ea.sort_order)
                local ob = tonumber(eb.sort_order)
                if oa and ob and oa ~= ob then
                    return oa < ob
                elseif oa and not ob then
                    return true
                elseif ob and not oa then
                    return false
                end

                -- 3. _sort_score if calculated and positive
                local sa = tonumber(ea._sort_score) or 0
                local sb = tonumber(eb._sort_score) or 0
                if sa > 0 or sb > 0 then
                    if sa ~= sb then
                        return sa > sb
                    end
                end

                -- 4. Guaranteed stable fallback to natural list order in raw_items
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
                self.prior_collapsed = not self.prior_collapsed
                if self.plugin then
                    self.plugin.series_prior_timeline_collapsed = self.prior_collapsed
                end
                self.current_page = 1
                self:buildUI()
                UIManager:setDirty(self, "ui")
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
    local key_name = key and (key.key or key.name or key) or ""
    return self:handleEvent({ type = "Key", key = key_name })
end

function EntityListOverlay:onKeyDown(key)
    return self:onKeyPress(key)
end

function EntityListOverlay:handleEvent(ev)
    if ev.type == "Key" or ev.type == "KeyPress" or ev.type == "KeyDown" then
        local key = ev.key or ev.name or ev.sym or ""

        local ok_dev, Device = pcall(require, "device")
        local extra_enter_keys = {}
        local extra_back_keys = {}
        if ok_dev and Device and Device.input and Device.input.group then
            if Device.input.group.Enter then extra_enter_keys[Device.input.group.Enter] = true end
            if Device.input.group.Select then extra_enter_keys[Device.input.group.Select] = true end
            if Device.input.group.Back then extra_back_keys[Device.input.group.Back] = true end
        end

        local UP_KEYS    = { Up=true, k=true, K=true }
        local DOWN_KEYS  = { Down=true, j=true, J=true }
        local LEFT_KEYS  = { Left=true, h=true, H=true }
        local RIGHT_KEYS = { Right=true, l=true, L=true }
        local PAGE_PREV  = { PrevPage=true, PageUp=true, p=true, P=true, ["["]=true }
        local PAGE_NEXT  = { NextPage=true, PageDown=true, n=true, N=true, ["]"]=true }
        local ENTER_KEYS = { Return=true, Enter=true, KP_Enter=true, Select=true, Space=true, Press=true }
        local CLOSE_KEYS = { Escape=true, Back=true, q=true, Q=true }
        for k in pairs(extra_enter_keys) do ENTER_KEYS[k] = true end
        for k in pairs(extra_back_keys)  do CLOSE_KEYS[k] = true end

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
            return self:close()
        elseif PAGE_PREV[key] then
            return self:onPrevPage()
        elseif PAGE_NEXT[key] then
            return self:onNextPage()
        elseif key == "Home" then
            return self:onFirstPage()
        elseif key == "End" then
            return self:onLastPage()
        elseif key == "s" or key == "S" then
            return self:showSortDialog()
        elseif key == "f" or key == "F" or key == "/" then
            return self:showSearchDialog()
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
                        self.prior_collapsed = not self.prior_collapsed
                        if self.plugin then self.plugin.series_prior_timeline_collapsed = self.prior_collapsed end
                        self.current_page = 1
                        self:buildUI()
                        UIManager:setDirty(self, "ui")
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
        elseif self.mode == "mentions" then self.plugin.mentions_menu = nil
        elseif self.mode == "linked_entries" then self.plugin.active_related_menu = nil
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

    local current_sort = self.sort_mode
    local check_freq = (current_sort == "frequency") and "● " or "○ "
    local check_app  = (current_sort == "appearance") and "● " or "○ "
    local check_az   = (current_sort == "alphabetical") and "● " or "○ "

    sort_dialog = ButtonDialog:new{
        modal = true,
        title = _tr("sort_by", "Sort By"),
        buttons = {
            {
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
            },
            {
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
            },
            {
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
            },
            {
                {
                    text = (loc and loc:t("cancel")) or "Cancel",
                    callback = function() UIManager:close(sort_dialog) end,
                }
            }
        }
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

function EntityListOverlay:renderRow(item, content_w, row_h, is_focused, idx)
    local p = self.plugin
    local loc = p and p.loc
    local is_timeline = (self.mode == "timeline")
    local is_mentions = (self.mode == "mentions")
    local is_prior = (item.source == "series_prior")

    if is_timeline and is_prior then
        local raw_ch = item.chapter or ""
        local num_match, name_match = raw_ch:match("^%[?Book%s+(%d+)%s*:%s*(.-)%]?$")
        local title_str = "Prior Book"
        if num_match and name_match and name_match ~= "" then
            title_str = string.format("Book %s: %s", num_match, name_match)
        else
            local num_only = raw_ch:match("^%[?Book%s+(%d+)%]?$")
            if num_only then
                title_str = "Book " .. num_only
            elseif item.source_book then
                title_str = string.format("Book %d: %s", item.source_book, raw_ch:gsub("^%[", ""):gsub("%]$", ""))
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
            desc_str = desc_str:sub(1, 180) .. "..."
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
        desc_str = desc_str:sub(1, 180) .. "..."
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
    end
end

function EntityListOverlay:buildUI()
    local sw = self.sw
    local sh = self.sh
    local p = self.plugin
    local loc = p and p.loc

    -- ── 1. Top Header Bar (Storefront style touch buttons) ────────────────────
    local btn_size = sc(26)
    local btn_w = sc(48)
    local btn_h = sc(48)
    local btn_gap = sc(4)

    local title_text_str = "Characters"
    if self.mode == "terms" then
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
    local total_count = #(self.raw_items or {})
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
        if self.mode ~= "timeline" then
            addHeaderAction("sort", "sliders.svg", function() self:showSortDialog() end)
        end
    end

    -- E. Close button (x.svg from Feather Icons, allow_flash=false)
    addHeaderAction("close", "x.svg", function() self:close() end)

    local header_actions_group = HorizontalGroup:new(action_btns)
    header_actions_group.align = "center"

    local is_filtered = (self.search_query and self.search_query ~= "")
    local num_btns = #self.current_header_actions
    local total_btns_w = num_btns * btn_w + math.max(0, num_btns - 1) * btn_gap
    local row_w = sw - sc(32)
    local title_container_w = row_w - total_btns_w - sc(12)
    local title_max_w = math.max(sc(140), title_container_w)

    local title_w = TextWidget:new{
        text = header_title,
        face = Font:getFace("cfont", is_filtered and 18 or 24),
        bold = true,
        fgcolor = Blitbuffer.COLOR_BLACK,
        max_width = title_max_w,
    }

    local title_left_widget
    if is_filtered then
        local sub_info = "Filter: \"" .. self.search_query .. "\" (" .. tostring(#(self.items or {})) .. " matches)"
        local sub_w = TextWidget:new{
            text = sub_info,
            face = Font:getFace("cfont", 12),
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
    local row_h = sc(64)
    local divider_h = sc(1)
    local items_per_page = math.max(1, math.floor(avail_content_h / (row_h + divider_h)))

    -- Check if we have prior-book events in timeline
    local display_items = {}
    if is_timeline then
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
    for idx, it in ipairs(display_items) do
        table.insert(cur_page_items, it)
        if #cur_page_items == items_per_page or idx == total_display then
            table.insert(pages, cur_page_items)
            cur_page_items = {}
        end
    end
    if #pages == 0 then pages = {{}} end

    self.total_pages = #pages
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
        table.insert(page_content_vg, CenterContainer:new{
            dimen = Geom:new{ w = sw, h = avail_content_h },
            empty_w,
        })
    else
        for idx, it in ipairs(page_items) do
            if it.is_prior_header then
                -- Collapsible Prior Books section row
                local icon_name = it.collapsed and "chevron-right.svg" or "chevron-down.svg"
                local chevron_icon = ImageWidget:new{
                    file = getAssetPath(icon_name),
                    width = sc(18),
                    height = sc(18),
                    scale_factor = 0,
                    is_icon = true,
                    alpha = true,
                }
                local raw_header = (loc and loc:t("series_prior_books_header")) or "Prior Books in Series"
                local clean_header = raw_header:gsub("^%s*[─%-–—]+%s*", ""):gsub("%s*[─%-–—]+%s*$", "")
                if clean_header == "" or clean_header:lower() == "prior books" then
                    clean_header = "Prior Books in Series"
                end
                local header_title = string.format("%s (%d)", clean_header, it.count or 0)
                local prior_txt = TextWidget:new{
                    text = header_title,
                    face = Font:getFace("cfont", 15),
                    bold = true,
                    fgcolor = Blitbuffer.COLOR_BLACK,
                }
                local sec_row = HorizontalGroup:new{
                    align = "center",
                    chevron_icon,
                    HorizontalSpan:new{ width = sc(8) },
                    prior_txt,
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
                    self.prior_collapsed = not self.prior_collapsed
                    if self.plugin then
                        self.plugin.series_prior_timeline_collapsed = self.prior_collapsed
                    end
                    self.current_page = 1
                    self:buildUI()
                    UIManager:setDirty(self, "ui")
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
                local row_widget = self:renderRow(it, sw, row_h, is_focused, idx)
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
    local nav_btn_size = sc(22)
    local nav_btn_w = sc(40)
    local nav_btn_h = sc(38)

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
        face = Font:getFace("cfont", 15),
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
