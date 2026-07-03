-- xray_unitscanner.lua - Page scanning, underline rendering, and tooltip UI
local UIManager = require("ui/uimanager")
local Screen = require("device").screen
local Blitbuffer = require("ffi/blitbuffer")
local InfoMessage = require("ui/widget/infomessage")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local TextBoxWidget = require("ui/widget/textboxwidget")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local RenderText = require("ui/rendertext")

local plugin_path = ((...) or ""):match("(.-)[^%.]+$") or ""
local xray_units = require(plugin_path .. "xray_units")
local XRayLogger = require(plugin_path .. "xray_logger")

local function log(msg)
    XRayLogger:log("UnitScanner: " .. tostring(msg))
end

local M = {}

-- Returns current page number safely
local function _getCurrentPage(plugin)
    if plugin.last_pageno then return plugin.last_pageno end
    if plugin.ui and plugin.ui.paging and plugin.ui.paging.getCurrentPage then
        local ok, pg = pcall(function() return plugin.ui.paging:getCurrentPage() end)
        if ok then return pg end
    end
    if plugin.ui and plugin.ui.pageno then
        return plugin.ui.pageno
    end
    return 1
end

-- Clear underlines overlay
function M:clearUnitUnderlines()
    self.unit_conversion_boxes = nil
    self.unit_xp_matches = nil
    if self.ui and self.ui.view and self.ui.view.dialog then
        UIManager:setDirty(self.ui.view.dialog, "ui")
    end
end

-- Paint overlay underlines using monkey-patched view.paintTo
function M:mountUnderlineOverlay()
    log("mountUnderlineOverlay called")
    if self._paintTo_wrapped then
        log("mountUnderlineOverlay: already wrapped")
        return
    end
    local plugin = self
    local view = self.ui and self.ui.view
    if not view then
        log("mountUnderlineOverlay: no self.ui.view found")
        return
    end
    local orig = view.paintTo
    view.paintTo = function(view_self, bb, x, y)
        orig(view_self, bb, x, y) -- draw reader page first
        local ok, err = pcall(function() plugin:_drawUnitUnderlines(bb) end)
        if not ok then
            log("draw error: " .. tostring(err))
            logger.warn("XRayPlugin: draw error: " .. tostring(err))
        end
    end
    self._paintTo_wrapped = true
    log("mountUnderlineOverlay: successfully wrapped view.paintTo")
end

local function _getCacheSig(self)
    local doc = self.ui and self.ui.document
    if not doc then return "" end
    local page = _getCurrentPage(self)
    local pos = ""
    if doc.getCurrentPos then
        pcall(function() pos = doc:getCurrentPos() end)
    end
    local hash = ""
    if doc.getDocumentRenderingHash then
        pcall(function() hash = doc:getDocumentRenderingHash() end)
    end
    local sw = Screen:getWidth()
    local sh = Screen:getHeight()
    return table.concat({ tostring(page), tostring(pos), tostring(hash), tostring(sw), tostring(sh) }, "|")
end

function M:_resolveHighlightBoxes()
    local sig = _getCacheSig(self)
    if self._box_cache_sig == sig and self.unit_conversion_boxes then
        return
    end
    
    self._box_cache_sig = sig
    local doc = self.ui and self.ui.document
    if not doc or not self.unit_xp_matches or #self.unit_xp_matches == 0 then
        self.unit_conversion_boxes = {}
        return
    end
    
    local resolved = {}
    for _, match in ipairs(self.unit_xp_matches) do
        local ok, boxes = pcall(doc.getScreenBoxesFromPositions, doc, match.start_xp, match.end_xp, true)
        if ok and boxes then
            for _, box in ipairs(boxes) do
                table.insert(resolved, {
                    x = box.x,
                    y = box.y,
                    w = box.w,
                    h = box.h,
                    original = match.original,
                    converted = match.converted,
                    category = match.category
                })
            end
        end
    end
    self.unit_conversion_boxes = resolved
    log("Resolved " .. tostring(#resolved) .. " visual conversion boxes on screen")
end

function M:_drawUnitUnderlines(bb)
    self:_resolveHighlightBoxes()
    if not self.unit_conversion_boxes or #self.unit_conversion_boxes == 0 then return end
    
    local settings = self.ai_helper and self.ai_helper.settings or {}
    local underline_style = settings.unit_underline_style or "wavy"
    if underline_style == "invisible" then return end
    
    local thickness = tonumber(settings.unit_underline_thickness) or 2
    local intensity = settings.unit_underline_intensity or "light"

    local color_val = Blitbuffer.Color8(150)
    if intensity == "light" then
        color_val = Blitbuffer.Color8(200)
    elseif intensity == "dark" then
        color_val = Blitbuffer.Color8(30)
    end

    for _, box in ipairs(self.unit_conversion_boxes) do
        if box.x and box.y and box.w and box.h then
            local y_line = box.y + box.h - thickness - 2
            if underline_style == "wavy" then
                for offset = 0, box.w - 1, 4 do
                    local wave_y = y_line + (math.floor(offset / 4) % 2 == 0 and 0 or 1)
                    local segment_w = math.min(4, box.w - offset)
                    bb:paintRect(box.x + offset, wave_y, segment_w, thickness, color_val)
                end
            else
                bb:paintRect(box.x, y_line, box.w, thickness, color_val)
            end
        end
    end
end


local function extend_span_start(doc, unit_start, num_val)
    if not doc or not unit_start or not num_val then return unit_start end
    local cand = unit_start
    local best_cand = unit_start
    for i = 1, 8 do
        local ok, prev = pcall(function()
            return doc:getPrevVisibleWordStart(cand)
        end)
        if not ok or not prev or prev == cand then break end
        cand = prev
        local ok2, t = pcall(function()
            return doc:getTextFromXPointers(cand, unit_start)
        end)
        if ok2 and t then
            t = t:gsub("^%s+", ""):gsub("%s+$", ""):lower()
            local clean_t = t:gsub("[%-,]$", "")
            local v = xray_units.parseNumberText(clean_t)
            if v and math.abs(v - num_val) < 0.001 then
                best_cand = cand
            else
                local head = clean_t:match("^([a-z%d%.,%-]+)")
                if head then
                    local hv = xray_units.parseNumberText(head)
                    if hv and math.abs(hv - num_val) < 0.001 then
                        best_cand = cand
                    end
                end
            end
        end
    end
    return best_cand
end

-- Scan the entire book and cache matches
function M:scanBookForUnits()
    if not self.ui or not self.ui.document then return end
    
    local settings = self.ai_helper and self.ai_helper.settings or {}
    if settings.unit_converter_enabled ~= true or settings.unit_underline_enabled == false then
        self:clearUnitUnderlines()
        return
    end

    log("scanBookForUnits: starting whole book scan")
    
    local direction = settings.unit_conversion_direction or "auto"
    log("scanBookForUnits: direction=" .. tostring(direction))
    
    local enabled_cats = {
        length = settings.unit_cat_length ~= false,
        weight = settings.unit_cat_weight ~= false,
        temp = settings.unit_cat_temp ~= false,
        volume = settings.unit_cat_volume ~= false,
        speed = settings.unit_cat_speed ~= false,
        area = settings.unit_cat_area ~= false,
    }

    local lang = self.loc and self.loc:getLanguage() or "en"
    local aliases = xray_units.getScanAliases(direction, enabled_cats, lang)
    if #aliases == 0 then
        self:clearUnitUnderlines()
        return
    end

    -- Escape and join aliases into a regex pattern
    local escaped_aliases = {}
    for _, alias in ipairs(aliases) do
        local esc = alias:gsub("[%-%+%.%?%*%^%$%(%)%[%]%%]", "%%%1")
        esc = esc:gsub("%s+", "\\s+")
        table.insert(escaped_aliases, esc)
    end
    -- Sort descending by length to prevent shadowing issues (e.g. "m" matching before "mm")
    table.sort(escaped_aliases, function(a, b)
        return #a > #b
    end)
    
    local pat = "\\b(" .. table.concat(escaped_aliases, "|") .. ")\\b"
    log("scanBookForUnits: regex pattern=[" .. pat .. "]")
    
    local doc = self.ui.document
    local ok, hits = pcall(function()
        -- Note: findAllText regex flag is true, contextWords=5, maxResults=5000, returnXPointers=true
        return doc:findAllText(pat, true, 5, 5000, true)
    end)
    
    if not ok or not hits then
        log("scanBookForUnits: findAllText failed: " .. tostring(hits))
        self:clearUnitUnderlines()
        return
    end

    log("scanBookForUnits: findAllText returned " .. tostring(#hits) .. " hits")

    local xp_matches = {}
    local lang = self.loc and self.loc:getLanguage() or "en"

    for _, hit in ipairs(hits) do
        local is_range = false
        local val, num_str
        local val1, val2
        local is_vague = false
        
        -- 1. Check for vague quantifiers (e.g. "a few hundred yards")
        local vague = xray_units.detectVagueQuantifier(hit.prev_text)
        if vague then
            val1 = vague.low
            val2 = vague.high
            is_range = true
            is_vague = true
            num_str = vague.quantifier .. " " .. vague.multiplier
        else
            -- 2. Try prefix_word or prev_text tail
            local p = (hit.prev_text or ""):gsub("%s+$", "")
            
            -- Try digit range
            -- Try digit range
            local r1, r2 = p:match("([0-9%.%,]+)%s*[%-–toor]+%s*([0-9%.%,]+)$")
            if not r1 then
                r1, r2 = p:match("([0-9%.%,]+)%s*,%s+([0-9%.%,]+)$")
            end
            if r1 and r2 then
                val1 = xray_units.parseNumberText(r1)
                val2 = xray_units.parseNumberText(r2)
                if val1 and val2 then
                    is_range = true
                    num_str = p:match("([0-9%.%,]+%s*[%-–toor,]+%s*[0-9%.%,]+)$") or (r1 .. "-" .. r2)
                end
            else
                -- Try written word range
                local w1, w2 = p:match("([a-z%d%-]+)%s*[,]?%s*(?:to|or|%-|and)%s*([a-z%d%-]+)$")
                if not w1 then
                    w1, w2 = p:match("([a-z%d%-]+)%s*,%s+([a-z%d%-]+)$")
                end
                if w1 and w2 then
                    local phrase_words = {}
                    for w in p:gmatch("[a-z%d%-%.%,]+") do
                        table.insert(phrase_words, w)
                    end
                    -- A range requires two distinct parsed parts separated by a connector.
                    -- If the whole thing parses as a single compound (like "twenty three"), it's not a range.
                    local is_compound = false
                    local combined_val = xray_units.parseNumberText(w1 .. " " .. w2)
                    if combined_val and not p:find("%s+to%s") and not p:find("%s+or%s") and not p:find("%s+and%s") and not p:find(",") then
                        is_compound = true
                    end
                    
                    if not is_compound then
                        val1 = xray_units.parseNumberText(w1)
                        val2 = xray_units.parseNumberText(w2)
                        if val1 and val2 then
                            is_range = true
                            num_str = p:match("([a-z%d%-]+%s*[,]?%s*(?:to|or|%-|and|,)%s*[a-z%d%-]+)$") or (w1 .. " to " .. w2)
                        end
                    end
                end
            end
            
            if not is_range then
                -- Single number or written compound (greedy backward accumulation)
                local words = {}
                for w in p:gmatch("[a-z%d%-%.%,]+") do
                    table.insert(words, w)
                end
                
                local valid_words = {}
                local i_w = #words
                while i_w >= 1 do
                    local w = words[i_w]
                    local clean_w = w:gsub("[%-,]$", "")
                    if clean_w == "a" and i_w > 1 and words[i_w-1]:gsub("[%-,]$", "") == "half" then
                        table.insert(valid_words, 1, "half a")
                        i_w = i_w - 2
                    elseif clean_w == "and" or xray_units.parseNumberText(clean_w) then
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
                    local best_val = xray_units.parseNumberText(phrase)
                    if best_val then
                        val = best_val
                        num_str = phrase
                    end
                end
            end
        end
        
        if val or is_range then
            local matched_unit = (hit.matched_text or ""):lower():gsub("\194\160", " "):gsub("%s+", " ")
            local u = xray_units.UNIT_LOOKUP and xray_units.UNIT_LOOKUP[matched_unit]
            if not u then
                for _, unit_def in ipairs(xray_units.UNITS or {}) do
                    for _, alias in ipairs(unit_def.aliases) do
                        if alias:lower() == matched_unit then
                            u = unit_def
                            break
                        end
                    end
                    if u then break end
                end
            end
            
            if u and enabled_cats[u.category] then
                local conv_str
                if is_range then
                    local conv_raw1 = xray_units.convert(val1, u.category, u.name, u.std_target)
                    local conv_val1, conv_unit = xray_units.applySmartScaling(conv_raw1, u.category, u.std_target)
                    local conv_raw2 = xray_units.convert(val2, u.category, u.name, u.std_target)
                    local conv_val2 = xray_units.applySmartScaling(conv_raw2, u.category, u.std_target)
                    
                    if conv_unit == "c" then conv_unit = "°C"
                    elseif conv_unit == "f" then conv_unit = "°F" end
                    
                    conv_str = (is_vague and "≈" or "") .. xray_units.formatNumber(conv_val1, lang) .. "–" .. xray_units.formatNumber(conv_val2, lang) .. " " .. xray_units.pluralizeUnit(conv_val2, conv_unit)
                else
                    local sign = ""
                    if u.category == "temp" then
                        local before_num = (hit.prev_text or ""):match("([^%d]*)$") or ""
                        if before_num:match("%-") or before_num:match("−") then
                            val = -val
                            sign = "-"
                        end
                    end
                    
                    local conv_raw = xray_units.convert(val, u.category, u.name, u.std_target)
                    local conv_val, conv_unit = xray_units.applySmartScaling(conv_raw, u.category, u.std_target)
                    
                    if conv_unit == "c" then conv_unit = "°C"
                    elseif conv_unit == "f" then conv_unit = "°F" end

                    conv_str = xray_units.formatNumber(conv_val, lang) .. " " .. xray_units.pluralizeUnit(conv_val, conv_unit)
                end
                
                -- Underline spans from beginning of match (the number) to end of match
                local span_start = extend_span_start(doc, hit.start, is_range and val1 or val)
                local original_text = num_str .. " " .. (hit.matched_text or "")
                local ok_t, real_text = pcall(function()
                    return doc:getTextFromXPointers(span_start, hit["end"])
                end)
                if ok_t and real_text then
                    original_text = real_text:gsub("^%s+", ""):gsub("%s+$", "")
                end
                
                table.insert(xp_matches, {
                    start_xp = span_start,
                    ["end_xp"] = hit["end"],
                    original = original_text,
                    converted = conv_str,
                    category = u.category
                })
            end
        end
    end

    self.unit_xp_matches = xp_matches
    log("scanBookForUnits: successfully parsed " .. tostring(#xp_matches) .. " unit matches")
    if #xp_matches == 0 and #hits > 0 then
        for j = 1, math.min(20, #hits) do
            local hit = hits[j]
            log("  hit " .. j .. ": matched_text=[" .. tostring(hit.matched_text) .. "] prefix_word=[" .. tostring(hit.matched_word_prefix) .. "] prev_text=[" .. tostring(hit.prev_text) .. "]")
        end
    end
    
    if self.ui and self.ui.view and self.ui.view.dialog then
        UIManager:setDirty(self.ui.view.dialog, "ui")
    end
end

-- Find matched unit box at touch coordinate
function M:findUnitBoxAtPoint(x, y)
    if not self.unit_conversion_boxes then return nil end
    local tolerance = 12
    for _, box in ipairs(self.unit_conversion_boxes) do
        if x >= box.x - tolerance and x <= box.x + box.w + tolerance and
           y >= box.y - tolerance and y <= box.y + box.h + tolerance then
            return box
        end
    end
    return nil
end

local function _getPopupFontSize(plugin)
    local size
    if plugin and plugin.ui and plugin.ui.font and plugin.ui.font.configurable then
        size = plugin.ui.font.configurable.font_size
    elseif G_reader_settings then
        size = G_reader_settings:readSetting("cre_font_size")
              or G_reader_settings:readSetting("kopt_font_size")
    end
    if size then return size end
    if Screen.scaleBySize then
        return Screen:scaleBySize(22)
    end
    return 22
end

local function getFontSafe(preferred_family, size)
    if preferred_family and preferred_family ~= "" then
        local ok, credoc = pcall(require, "document/credocument")
        if ok and credoc and credoc.engineInit then
            local ok2, cre = pcall(credoc.engineInit, credoc)
            if ok2 and cre and cre.getFontFaceFilenameAndFaceIndex then
                local filename, faceindex = cre.getFontFaceFilenameAndFaceIndex(preferred_family)
                if not filename then
                    filename, faceindex = cre.getFontFaceFilenameAndFaceIndex(preferred_family, nil, true)
                end
                if filename then
                    local face_ok, face = pcall(Font.getFace, Font, filename, size, faceindex)
                    if face_ok and face then return face end
                end
            end
        end
    end
    return Font:getFace("cfont", size)
end

local Widget = require("ui/widget/widget")
local _PointerArrow = Widget:extend{
    width        = 0,
    height       = 0,
    direction    = "up",   -- "up": apex on top, base on bottom; "down": reverse
    apex_offset  = 0,      -- apex x position, relative to the widget's left edge
    border_size  = 1,
    border_color = Blitbuffer.COLOR_DARK_GRAY,
    fill_color   = Blitbuffer.COLOR_WHITE,
}

function _PointerArrow:getSize()
    return Geom:new{ w = self.width, h = self.height }
end

function _PointerArrow:paintTo(bb, x, y)
    local w, h  = self.width, self.height
    local apex  = self.apex_offset
    local bw    = self.border_size
    for row = 0, h - 1 do
        local frac = (self.direction == "up") and ((row + 1) / h) or ((h - row) / h)
        local half  = (w * frac) / 2
        local left  = math.floor(apex - half + 0.5)
        local right = math.ceil(apex + half - 0.5)
        bb:paintRect(x + left, y + row, math.max(1, right - left + 1), 1, self.border_color)

        local inner_half = half - bw
        if inner_half > 0 then
            local ileft  = math.floor(apex - inner_half + 0.5)
            local iright = math.ceil(apex + inner_half - 0.5)
            if iright >= ileft then
                bb:paintRect(x + ileft, y + row, iright - ileft + 1, 1, self.fill_color)
            end
        end
    end
end

-- Tooltip Dialog Widget with Dual Dismissal
local UnitTooltip = InputContainer:extend{
    conversion = nil,
    plugin = nil,
    timeout = 4,
    timer_handle = nil,
    _closed = false,
}

function UnitTooltip:init()
    local sw = Screen:getWidth()
    local sh = Screen:getHeight()
    local sc = function(n) return Screen:scaleBySize(n) end
    
    local c = self.conversion
    local text = c.converted
    
    local fs = _getPopupFontSize(self.plugin)
    local doc_family
    if self.plugin and self.plugin.ui and self.plugin.ui.font then
        doc_family = self.plugin.ui.font.font_face
    end
    if not doc_family and G_reader_settings then
        doc_family = G_reader_settings:readSetting("cre_font_family")
    end
    local face = getFontSafe(doc_family, fs)
    
    local pad_h = 28
    local pad_v = math.floor(fs * 0.55)
    
    local text_size = RenderText:sizeUtf8Text(0, 9999, face, text, false, false)
    local text_w = text_size.x
    local card_w = text_w + pad_h * 2
    
    local TextWidget = require("ui/widget/textwidget")
    local tb = TextWidget:new{
        text = text,
        face = face,
    }
    
    local card = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = sc(2),
        color = Blitbuffer.COLOR_DARK_GRAY,
        radius = 0,
        padding_top = pad_v,
        padding_bottom = pad_v,
        padding_left = pad_h,
        padding_right = pad_h,
        width = card_w,
        tb
    }
    
    local card_size = card:getSize()
    local card_w = card_size.w
    local card_h = card_size.h
    
    local margin = sc(10)
    local box = c
    local ref_x = box.x + box.w / 2
    local ref_bottom = box.y + box.h
    local ref_top = box.y
    
    local arrow_w = sc(16)
    local arrow_h = sc(8)
    local border_px = sc(2)

    local popup_x = math.max(0, math.min(sw - card_w, math.floor(ref_x - card_w / 2)))
    local popup_y
    local popup_below_word
    
    if ref_bottom + margin + card_h <= sh then
        popup_y = ref_bottom + margin
        popup_below_word = true
    else
        popup_y = ref_top - margin - card_h - arrow_h + border_px
        popup_below_word = false
    end

    if popup_below_word then
        popup_y = math.max(arrow_h - border_px, math.min(sh - card_h, popup_y))
    else
        popup_y = math.max(0, math.min(sh - card_h - arrow_h + border_px, popup_y))
    end
    card.overlap_offset = { popup_x, popup_y }
    
    local apex_min = popup_x + arrow_w / 2 + sc(4)
    local apex_max = popup_x + card_w - arrow_w / 2 - sc(4)
    local apex_x
    if apex_min <= apex_max then
        apex_x = math.max(apex_min, math.min(apex_max, ref_x))
    else
        apex_x = popup_x + card_w / 2
    end
    
    local arrow_x = math.floor(apex_x - arrow_w / 2)
    local arrow_y
    local arrow_dir
    if popup_below_word then
        arrow_dir = "up"
        arrow_y = popup_y - arrow_h + border_px
    else
        arrow_dir = "down"
        arrow_y = popup_y + card_h - border_px
    end
    
    local arrow = _PointerArrow:new{
        width = arrow_w,
        height = arrow_h,
        direction = arrow_dir,
        apex_offset = arrow_w / 2,
        border_size = border_px,
        border_color = Blitbuffer.COLOR_DARK_GRAY,
        fill_color = Blitbuffer.COLOR_WHITE,
    }
    arrow.overlap_offset = { arrow_x, arrow_y }
    
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    self.ges_events = {
        TapOutside = {
            GestureRange:new{
                ges = "tap",
                range = Geom:new{ x = 0, y = 0, w = sw, h = sh }
            }
        }
    }
    
    local OverlapGroup = require("ui/widget/overlapgroup")
    self[1] = OverlapGroup:new{
        dimen = Geom:new{ w = sw, h = sh },
        card,
        arrow,
    }
end

function UnitTooltip:onTapOutside()
    self:dismiss()
    return true
end

function UnitTooltip:onClose()
    self:dismiss()
    return true
end

function UnitTooltip:dismiss()
    if self.timer_handle then
        pcall(function() self.timer_handle:cancel() end)
        self.timer_handle = nil
    end
    if not self._closed then
        self._closed = true
        UIManager:close(self)
    end
end

function UnitTooltip:onShow()
    if self.timeout and self.timeout > 0 then
        local this = self
        self.timer_handle = UIManager:scheduleIn(self.timeout, function()
            if not this._closed then
                this:dismiss()
            end
        end)
    end
    UIManager:setDirty(self, "ui")
    return true
end

-- Show tooltip at tapped coordinate
function M:showUnitTooltip(box)
    if not box then return end
    
    local settings = self.ai_helper and self.ai_helper.settings or {}
    local timeout = tonumber(settings.unit_tooltip_timeout) or 4
    
    local tooltip = UnitTooltip:new{
        conversion = box,
        plugin = self,
        timeout = timeout
    }
    UIManager:show(tooltip)
end

-- Mount tap handler via monkey patching self.ui.highlight.onTap
function M:mountTapHandler()
    if self._tapHandler_wrapped then return end
    local plugin = self
    local hl = self.ui and self.ui.highlight
    if not hl then return end
    local orig_tap = hl.onTap
    hl.onTap = function(hl_self, _, ges)
        if ges and plugin:_handleUnitTap(ges) then return true end
        if orig_tap then return orig_tap(hl_self, _, ges) end
    end
    self._tapHandler_wrapped = true
end

function M:_handleUnitTap(ges)
    local settings = self.ai_helper and self.ai_helper.settings or {}
    if settings.unit_converter_enabled ~= true then return false end
    
    if not self.unit_conversion_boxes or #self.unit_conversion_boxes == 0 then
        return false
    end
    local tx, ty = ges.pos.x, ges.pos.y
    for _, box in ipairs(self.unit_conversion_boxes) do
        if tx >= box.x and tx <= box.x + box.w
        and ty >= box.y - 6 and ty <= box.y + box.h + 6 then
            self:showUnitTooltip(box)
            return true
        end
    end
    return false
end

M._PointerArrow = _PointerArrow
return M
