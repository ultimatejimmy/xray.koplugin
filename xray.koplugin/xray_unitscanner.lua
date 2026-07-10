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

local RANGE_SEPS = {
    "-",
    "\226\128\145", -- Non-breaking hyphen U+2011 (‑)
    "\226\128\146", -- Figure dash U+2012 (‒)
    "\226\128\147", -- En dash U+2013 (–)
    "\226\128\148", -- Em dash U+2014 (—)
    "\226\128\149", -- Horizontal bar U+2015 (―)
    "\226\136\146", -- Minus sign U+2212 (−)
    "\239\185\163", -- Small hyphen-minus U+FE63 (﹣)
    "\239\188\141", -- Fullwidth hyphen-minus U+FF0D (－)
    "~",
    "/",
    "\227\128\156", -- Wave dash U+301C (〜)
}

local function build_trie(words)
    local trie = {}
    for _, word in ipairs(words) do
        local node = trie
        for char in word:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
            node[char] = node[char] or {}
            node = node[char]
        end
        node["$"] = true
    end
    return trie
end

local function trie_to_regex(node)
    local branches = {}
    local chars = {}
    local has_end = false
    
    for k, v in pairs(node) do
        if k == "$" then
            has_end = true
        else
            table.insert(chars, k)
        end
    end
    
    table.sort(chars)
    
    for _, k in ipairs(chars) do
        local child_regex = trie_to_regex(node[k])
        
        local esc_k = k
        if k == " " then
            esc_k = "\\s+"
        elseif k == "\2" then
            esc_k = "\\b"
        elseif k:find("^[%-%+%.%?%*%^%$%(%)%[%]%%%\\]$") then
            esc_k = "\\" .. k
        end
        
        if child_regex == "" then
            table.insert(branches, esc_k)
        else
            table.insert(branches, esc_k .. child_regex)
        end
    end
    
    if #branches == 0 then
        return ""
    end
    
    local regex = ""
    if #branches == 1 then
        regex = branches[1]
    else
        regex = "(" .. table.concat(branches, "|") .. ")"
    end
    
    if has_end then
        if #branches > 0 then
            regex = "(" .. regex .. ")?"
        end
    end
    
    return regex
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

local _wavy_svg_template
local _wavy_tile_cache = {}

local function _load_wavy_template(plugin_path)
    if _wavy_svg_template then return _wavy_svg_template end
    local path = plugin_path .. "/assets/wavy-underline.svg"
    local fh = io.open(path, "r")
    if not fh then return nil end
    _wavy_svg_template = fh:read("*a")
    fh:close()
    return _wavy_svg_template
end

local function _wavy_tile(plugin_path, raw_width, grey)
    local key = raw_width .. "_" .. grey
    local cached = _wavy_tile_cache[key]
    if cached ~= nil then return cached end

    local template = _load_wavy_template(plugin_path)
    if not template then
        _wavy_tile_cache[key] = false
        return false
    end

    local hex  = string.format("#%02x%02x%02x", grey, grey, grey)
    local svg  = template:gsub('stroke="black"', 'stroke="' .. hex .. '"')
    svg = svg:gsub('stroke="' .. hex .. '"', 'stroke="' .. hex .. '" stroke-width="' .. raw_width .. '"')

    local DataStorage = require("datastorage")
    local sidecar_dir = DataStorage:getDataDir() .. "/xray"
    os.execute("mkdir -p " .. sidecar_dir)
    local svg_path = sidecar_dir .. "/wavy_" .. key .. ".svg"
    local fh = io.open(svg_path, "w")
    if fh then fh:write(svg); fh:close() end

    local svg_w = 8
    local svg_h = 4
    local tile_w = Screen:scaleBySize(svg_w)
    local tile_h = math.max(1, math.floor(tile_w * svg_h / svg_w + 0.5))
    local RenderImage = require("ui/renderimage")
    local ok, tile = pcall(function()
        return RenderImage:renderSVGImageFile(svg_path, tile_w, tile_h)
    end)
    if not ok or not tile then
        _wavy_tile_cache[key] = false
        return false
    end
    _wavy_tile_cache[key] = tile
    return tile
end

local _circle_tile_cache = {}

local function _circle_tile(diameter, grey)
    local key = diameter .. "_" .. grey
    local cached = _circle_tile_cache[key]
    if cached ~= nil then return cached end

    local hex = string.format("#%02x%02x%02x", grey, grey, grey)
    local r = diameter / 2
    local svg = string.format('<svg width="%d" height="%d" viewBox="0 0 %d %d" xmlns="http://www.w3.org/2000/svg"><circle cx="%f" cy="%f" r="%f" fill="%s"/></svg>',
        diameter, diameter, diameter, diameter, r, r, r, hex)

    local DataStorage = require("datastorage")
    local sidecar_dir = DataStorage:getDataDir() .. "/xray"
    os.execute("mkdir -p " .. sidecar_dir)
    local svg_path = sidecar_dir .. "/circle_" .. key .. ".svg"
    local fh = io.open(svg_path, "w")
    if fh then
        fh:write(svg)
        fh:close()
    end

    local RenderImage = require("ui/renderimage")
    local ok, tile = pcall(function()
        return RenderImage:renderSVGImageFile(svg_path, diameter, diameter)
    end)
    if not ok or not tile then
        _circle_tile_cache[key] = false
        return false
    end
    _circle_tile_cache[key] = tile
    return tile
end

local function paintFilledCircle(bb, x0, y0, diameter, color)
    if diameter <= 1 then
        bb:paintRect(x0, y0, 1, 1, color)
        return
    elseif diameter == 2 then
        bb:paintRect(x0, y0, 2, 2, color)
        return
    end
    local c = (diameter - 1) / 2
    local r = diameter / 2
    local r_sq = r * r
    for dy = 0, diameter - 1 do
        local dist_y = dy - c
        local dist_y_sq = dist_y * dist_y
        local start_x = nil
        local end_x = nil
        for dx = 0, diameter - 1 do
            local dist_x = dx - c
            if dist_x * dist_x + dist_y_sq <= r_sq then
                if not start_x then
                    start_x = dx
                end
                end_x = dx
            end
        end
        if start_x and end_x then
            bb:paintRect(x0 + start_x, y0 + dy, end_x - start_x + 1, 1, color)
        end
    end
end

local function _draw_underline(bb, box, style, grey, thickness, raw_thickness, plugin_path)
    local y  = box.y + box.h - thickness
    local x0 = box.x
    local x1 = box.x + box.w
    local color_val = Blitbuffer.Color8(grey)

    if style == "invisible" then
        return
    elseif style == "wavy" then
        local tile = _wavy_tile(plugin_path, raw_thickness, grey)
        if tile then
            local tw, th = tile:getWidth(), tile:getHeight()
            local ypos = box.y + box.h - math.floor((th + thickness) / 2 + 0.5)
            local x = x0
            while x < x1 do
                local w = math.min(tw, x1 - x)
                bb:alphablitFrom(tile, x, ypos, 0, 0, w, th)
                x = x + tw
            end
            return
        end
    end

    if style == "solid" then
        bb:paintRect(x0, y, box.w, thickness, color_val)
    elseif style == "double" then
        local line_h = math.max(1, math.floor(thickness / 2 + 0.5))
        local gap = math.max(1, math.floor(thickness / 2))
        bb:paintRect(x0, y - gap, box.w, line_h, color_val)
        bb:paintRect(x0, y + line_h, box.w, line_h, color_val)
    elseif style == "dotted" then
        local dot_w = thickness
        local gap_w = thickness
        local x = x0
        local tile = _circle_tile(dot_w, grey)
        if tile then
            local tw, th = tile:getWidth(), tile:getHeight()
            while x < x1 do
                local w = math.min(tw, x1 - x)
                bb:alphablitFrom(tile, x, y, 0, 0, w, th)
                x = x + tw + gap_w
            end
        else
            while x < x1 do
                paintFilledCircle(bb, x, y, dot_w, color_val)
                x = x + dot_w + gap_w
            end
        end
    elseif style == "dashed" then
        local dash_w = Screen:scaleBySize(6)
        local gap_w = Screen:scaleBySize(3)
        local x = x0
        while x < x1 do
            local w = math.min(dash_w, x1 - x)
            bb:paintRect(x, y, w, thickness, color_val)
            x = x + dash_w + gap_w
        end
    end
end

local function _checkSettingsChanged(self)
    local settings = self.ai_helper and self.ai_helper.settings or {}
    
    local enabled = settings.unit_converter_enabled ~= false
    local underline_enabled = settings.unit_underline_enabled ~= false
    local direction = settings.unit_conversion_direction or "auto"
    local dim_units = G_reader_settings and G_reader_settings:readSetting("dimension_units") or "mm"
    
    local cat_l = settings.unit_cat_length ~= false
    local cat_w = settings.unit_cat_weight ~= false
    local cat_t = settings.unit_cat_temp ~= false
    local cat_v = settings.unit_cat_volume ~= false
    local cat_s = settings.unit_cat_speed ~= false
    local cat_a = settings.unit_cat_area ~= false

    if self.last_settings_state == nil then
        self.last_settings_state = {
            enabled = enabled,
            underline_enabled = underline_enabled,
            direction = direction,
            dim_units = dim_units,
            cat_l = cat_l,
            cat_w = cat_w,
            cat_t = cat_t,
            cat_v = cat_v,
            cat_s = cat_s,
            cat_a = cat_a,
        }
        return false
    end

    local state = self.last_settings_state
    local changed = (state.enabled ~= enabled) or
                    (state.underline_enabled ~= underline_enabled) or
                    (state.direction ~= direction) or
                    (state.dim_units ~= dim_units) or
                    (state.cat_l ~= cat_l) or
                    (state.cat_w ~= cat_w) or
                    (state.cat_t ~= cat_t) or
                    (state.cat_v ~= cat_v) or
                    (state.cat_s ~= cat_s) or
                    (state.cat_a ~= cat_a)

    if changed then
        self.last_settings_state = {
            enabled = enabled,
            underline_enabled = underline_enabled,
            direction = direction,
            dim_units = dim_units,
            cat_l = cat_l,
            cat_w = cat_w,
            cat_t = cat_t,
            cat_v = cat_v,
            cat_s = cat_s,
            cat_a = cat_a,
        }
    end

    return changed
end

function M:_drawUnitUnderlines(bb)
    if _checkSettingsChanged(self) then
        log("Settings changed, refreshing unit scan")
        self:scanBookForUnits()
        self._box_cache_sig = nil
    end

    self:_resolveHighlightBoxes()
    if not self.unit_conversion_boxes or #self.unit_conversion_boxes == 0 then return end
    
    local settings = self.ai_helper and self.ai_helper.settings or {}
    local underline_style = settings.unit_underline_style or "wavy"
    if underline_style == "invisible" then return end
    
    local raw_thickness = tonumber(settings.unit_underline_thickness) or 2
    local thickness = Screen:scaleBySize(raw_thickness)
    local intensity = settings.unit_underline_intensity or "light"

    local grey = 150
    if intensity == "light" then
        grey = 200
    elseif intensity == "dark" then
        grey = 30
    end

    for _, box in ipairs(self.unit_conversion_boxes) do
        if box.x and box.y and box.w and box.h then
            _draw_underline(bb, box, underline_style, grey, thickness, raw_thickness, self.path)
        end
    end
end


local function extend_span_start(doc, unit_start, num_val)
    if not doc or not unit_start or not num_val then return unit_start end
    local cand = unit_start
    local best_cand = unit_start
    for i = 1, 4 do
        local ok, prev = pcall(function()
            return doc:getPrevVisibleWordStart(cand)
        end)
        if not ok or not prev or prev == cand then break end
        cand = prev
        local ok2, t = pcall(function()
            return doc:getTextFromXPointers(cand, unit_start)
        end)
        if ok2 and t then
            if t:find("[\r\n]") or t:find("%.%s") or t:find("%!%s") or t:find("%?%s") then break end
            t = t:gsub("^%s+", ""):gsub("%s+$", ""):lower()
            local clean_t = t
            for _, sep in ipairs(RANGE_SEPS) do
                clean_t = clean_t:gsub(sep .. "%s*$", "")
            end
            clean_t = clean_t:gsub("[,]%s*$", "")
            local v = xray_units.parseNumberText(clean_t)
            if v and math.abs(v - num_val) < 0.001 then
                best_cand = cand
            elseif not clean_t:match("^%a") then
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

-- -- Cache file operations
local DocSettings = require("docsettings")

local function _getResolvedDirection(self)
    local settings = self.ai_helper and self.ai_helper.settings or {}
    local direction = settings.unit_conversion_direction or "auto"
    if direction == "auto" then
        local lang = self.loc and self.loc:getLanguage() or "en"
        direction = xray_units.getDefaultDirection(lang)
    end
    return direction
end

function M:_getUnitCachePath(resolved_dir)
    if not self.ui or not self.ui.document or not self.ui.document.file then return nil end
    local sidecar = DocSettings:getSidecarDir(self.ui.document.file)
    if not sidecar then return nil end
    resolved_dir = resolved_dir or _getResolvedDirection(self)
    return sidecar .. "/xray_unit_cache_" .. resolved_dir .. ".cache"
end

local function _getSettingsSignature(settings)
    local cat_l = settings.unit_cat_length ~= false
    local cat_w = settings.unit_cat_weight ~= false
    local cat_t = settings.unit_cat_temp ~= false
    local cat_v = settings.unit_cat_volume ~= false
    local cat_s = settings.unit_cat_speed ~= false
    local cat_a = settings.unit_cat_area ~= false
    return table.concat({
        "v30",
        tostring(cat_l), tostring(cat_w), tostring(cat_t),
        tostring(cat_v), tostring(cat_s), tostring(cat_a)
    }, "|")
end

function M:loadUnitCache(resolved_dir)
    resolved_dir = resolved_dir or _getResolvedDirection(self)
    local cache_file = self:_getUnitCachePath(resolved_dir)
    if not cache_file then return false end
    
    local f, err = io.open(cache_file, "r")
    if not f then return false end
    
    local signature = f:read("*l")
    if not signature then
        f:close()
        return false
    end
    
    local settings = self.ai_helper and self.ai_helper.settings or {}
    local current_sig = _getSettingsSignature(settings)
    if signature ~= current_sig then
        log("loadUnitCache: Cache settings signature mismatch, ignoring")
        f:close()
        return false
    end
    
    local matches = {}
    for line in f:lines() do
        line = line:gsub("\r", "")
        local start_xp, end_xp, original, converted, category = line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)$")
        if start_xp then
            table.insert(matches, {
                start_xp = start_xp,
                end_xp = end_xp,
                original = original,
                converted = converted,
                category = category ~= "" and category or nil
            })
        end
    end
    f:close()
    
    self.unit_xp_matches = matches
    self._box_cache_sig = nil
    log("loadUnitCache: Successfully loaded " .. tostring(#self.unit_xp_matches) .. " matches from cache")
    if self.ui and self.ui.view then
        if self.ui.view.dialog then
            UIManager:setDirty(self.ui.view.dialog, "ui")
        end
        UIManager:setDirty(nil, "ui")
    end
    return true
end

function M:saveUnitCache(resolved_dir)
    resolved_dir = resolved_dir or _getResolvedDirection(self)
    local cache_file = self:_getUnitCachePath(resolved_dir)
    if not cache_file then return end
    
    local settings = self.ai_helper and self.ai_helper.settings or {}
    local signature = _getSettingsSignature(settings)
    
    local ok, err = pcall(function()
        local f, open_err = io.open(cache_file, "w")
        if f then
            f:write(signature .. "\n")
            for _, m in ipairs(self.unit_xp_matches or {}) do
                local original_clean = (m.original or ""):gsub("\r", " "):gsub("\n", " ")
                local converted_clean = (m.converted or ""):gsub("\r", " "):gsub("\n", " ")
                f:write(string.format("%s\t%s\t%s\t%s\t%s\n",
                    tostring(m.start_xp or ""),
                    tostring(m.end_xp or ""),
                    original_clean,
                    converted_clean,
                    m.category or ""))
            end
            f:close()
            log("saveUnitCache: Saved cache to " .. cache_file)
        else
            log("saveUnitCache: Failed to open cache: " .. tostring(open_err))
        end
    end)
    if not ok then
        log("saveUnitCache: Unexpected error writing cache: " .. tostring(err))
    end
end

-- Scan the entire book and cache matches
function M:scanBookForUnits(force)
    if not self.ui or not self.ui.document then return end
    
    local settings = self.ai_helper and self.ai_helper.settings or {}
    if settings.unit_converter_enabled == false or settings.unit_underline_enabled == false then
        self:clearUnitUnderlines()
        return
    end

    log("scanBookForUnits starting. Force=" .. tostring(force))
    local resolved_dir = _getResolvedDirection(self)
    local cache_loaded = self:loadUnitCache(resolved_dir)
    log("loadUnitCache returned " .. tostring(cache_loaded))
    if not force and cache_loaded then
        log("scanBookForUnits: returning early due to cached hits")
        return
    end

    if self._unit_scan_in_progress then return end
    self._unit_scan_in_progress = true

    local Notification = require("ui/widget/notification")
    local progress_msg = InfoMessage:new{
        text = "Scanning for unit conversions...",
        dismissable = false,
    }
    UIManager:show(progress_msg)
    UIManager:forceRePaint()

    UIManager:scheduleIn(0.1, function()
        if self.destroyed then
            self._unit_scan_in_progress = false
            return
        end

        local ok_scan, err_scan = pcall(function()
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

            -- Split unit aliases into ambiguous and unambiguous categories
            local ambiguous_aliases = {}
            local word_unambiguous_aliases = {}
            local non_word_unambiguous_aliases = {}
            for _, alias in ipairs(aliases) do
                local normalized = alias:lower():gsub("%s+", " ")
                local base = normalized:gsub("%.+$", "")
                
                if base == "in" or base == "m" or base == "l" or base == "g" or base == "f" or base == "t" or base == "c" or base == "oc" or base == "0c" or base == "of" or base == "0f" then
                    if normalized:match("[%w]$") then
                        normalized = normalized .. "\2"
                    end
                    table.insert(ambiguous_aliases, normalized)
                else
                    if normalized:match("[%w]$") then
                        normalized = normalized .. "\2"
                    end
                    if normalized:match("^[^%w]") then
                        table.insert(non_word_unambiguous_aliases, normalized)
                    else
                        table.insert(word_unambiguous_aliases, normalized)
                    end
                end
            end

            local is_ambig = {}
            for _, alias in ipairs(ambiguous_aliases) do
                local clean = alias:gsub("\2", ""):lower()
                is_ambig[clean] = true
            end

            -- Combine all unambiguous aliases for digit matching
            local all_unambiguous = {}
            for _, a in ipairs(word_unambiguous_aliases) do
                table.insert(all_unambiguous, a)
            end
            for _, a in ipairs(non_word_unambiguous_aliases) do
                table.insert(all_unambiguous, a)
            end

            local digit_units = ""
            if #ambiguous_aliases > 0 and #all_unambiguous > 0 then
                local ambig_trie = build_trie(ambiguous_aliases)
                local ambig_trie_regex = trie_to_regex(ambig_trie)
                local unambig_trie = build_trie(all_unambiguous)
                local unambig_trie_regex = trie_to_regex(unambig_trie)
                digit_units = ambig_trie_regex .. "|" .. unambig_trie_regex
            elseif #ambiguous_aliases > 0 then
                local ambig_trie = build_trie(ambiguous_aliases)
                local ambig_trie_regex = trie_to_regex(ambig_trie)
                digit_units = ambig_trie_regex
            else
                local unambig_trie = build_trie(all_unambiguous)
                digit_units = trie_to_regex(unambig_trie)
            end

            local pat_digit = "(([0-9]+[0-9\\.,]*|\\.[0-9]+)\\s*(" .. digit_units .. "))"
            local pat_word
            local parts = {}
            if #word_unambiguous_aliases > 0 then
                local trie = build_trie(word_unambiguous_aliases)
                table.insert(parts, "\\b(" .. trie_to_regex(trie) .. ")")
            end
            if #non_word_unambiguous_aliases > 0 then
                local trie = build_trie(non_word_unambiguous_aliases)
                table.insert(parts, "(" .. trie_to_regex(trie) .. ")")
            end
            if #parts > 0 then
                pat_word = "(" .. table.concat(parts, "|") .. ")"
            end
            
            log("scanBookForUnits: pat_digit=[" .. tostring(pat_digit) .. "]")
            if pat_word then
                log("scanBookForUnits: pat_word=[" .. tostring(pat_word) .. "]")
            end

            local doc = self.ui.document
            local t0 = os.clock()
            local ok1, hits1 = pcall(function()
                -- Note: findAllText regex flag is true, contextWords=5, maxResults=5000, returnXPointers=true
                return doc:findAllText(pat_digit, true, 5, 5000, true)
            end)
            local t1 = os.clock()
            log(string.format("scanBookForUnits: findAllText (digit) took %.2fs", t1 - t0))

            local ok2, hits2
            local t2 = t1
            if pat_word then
                ok2, hits2 = pcall(function()
                    return doc:findAllText(pat_word, true, 5, 5000, true)
                end)
                t2 = os.clock()
                log(string.format("scanBookForUnits: findAllText (word) took %.2fs", t2 - t1))
            end

            if (not ok1 or not hits1) and (not pat_word or (not ok2 or not hits2)) then
                log("scanBookForUnits: findAllText failed: " .. tostring(hits1 or hits2))
                self:clearUnitUnderlines()
                return
            end

            local hits = {}
            if ok1 and hits1 then
                for _, h in ipairs(hits1) do
                    table.insert(hits, h)
                end
            end
            if ok2 and hits2 then
                for _, h in ipairs(hits2) do
                    table.insert(hits, h)
                end
            end

            -- Deduplicate overlapping hits by end xpointer (keeps the longest match)
            local unique_hits = {}

            for _, hit in ipairs(hits) do
                local end_xp = hit["end"]
                if not unique_hits[end_xp] or #hit.matched_text > #unique_hits[end_xp].matched_text then
                    unique_hits[end_xp] = hit
                end
            end

            local deduped_hits = {}
            for _, hit in pairs(unique_hits) do
                table.insert(deduped_hits, hit)
            end
            hits = deduped_hits

            local t_start_lua = os.clock()
            log(string.format("scanBookForUnits: dedup took %.2fs, %d hits", t_start_lua - t2, #hits))

            local xp_matches = {}
            local lang = self.loc and self.loc:getLanguage() or "en"

            -- Sort descending by length to prevent shadowing issues (e.g. "m" matching before "mm")
            local sorted_aliases = {}
            for _, alias in ipairs(aliases) do
                table.insert(sorted_aliases, alias:lower())
            end
            table.sort(sorted_aliases, function(a, b)
                return #a > #b
            end)

            -- Construct suffix_map hash table: alias_lower -> true
            local suffix_map = {}
            for _, alias in ipairs(sorted_aliases) do
                local alias_lower = alias:gsub("\194\160", " "):gsub("%s+", " ")
                suffix_map[alias_lower] = true
            end


            for _, hit in ipairs(hits) do
                local is_range = false
                local val, num_str
                local val1, val2
                local is_vague = false
                
                local matched_text = (hit.matched_text or "")
                local lower_matched = matched_text:lower():gsub("\194\160", " "):gsub("%s+", " ")
                
                -- Extract unit alias using suffix_map lookup by iterating suffixes
                local matched_alias = nil
                for i = 1, #lower_matched do
                    local suffix = lower_matched:sub(i)
                    if suffix_map[suffix] then
                        matched_alias = suffix
                        break
                    end
                end
                matched_alias = matched_alias or lower_matched

                -- Extract prefix part
                local num_part = matched_text:sub(1, #matched_text - #matched_alias)
                local p = (hit.prev_text or "") .. num_part
                p = p:gsub("%s+$", "")
                for _, sep in ipairs(RANGE_SEPS) do
                    p = p:gsub(sep, "-")
                end
                
                -- 1. Check for vague quantifiers (e.g. "a few hundred yards")
                local vague = xray_units.detectVagueQuantifier(p)
                if vague then
                    val1 = vague.low
                    val2 = vague.high
                    is_range = true
                    is_vague = true
                    num_str = vague.quantifier .. " " .. vague.multiplier
                else
                    -- 2. Try prefix_word or prev_text tail
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
                        local w1, w2 = p:match("([%a%d%-]+)%s*[,]?%s*(?:to|or|%-|and)%s*([%a%d%-]+)$")
                        if not w1 then
                            w1, w2 = p:match("([%a%d%-]+)%s*,%s+([%a%d%-]+)$")
                        end
                        if w1 and w2 then
                            local phrase_words = {}
                            for w in p:gmatch("[%a%d%-%.%,]+") do
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
                                    num_str = p:match("([%a%d%-]+%s*[,]?%s*(?:to|or|%-|and|,)%s*[%a%d%-]+)$") or (w1 .. " to " .. w2)
                                end
                            end
                        end
                    end
                    
                    if not is_range then
                        local single = p:match("([%-−–—]?%s*[0-9%.%,]+)$")
                        if single then
                            val = xray_units.parseNumberText(single)
                            if val then
                                num_str = single
                            end
                        end
                        
                        if not val then
                            -- Single number or written compound (greedy backward accumulation)
                            local words = {}
                            for w in p:gmatch("[%a%d%-%.%,]+") do
                                table.insert(words, w)
                            end
                            
                            local valid_words = {}
                            local i_w = #words
                            local saw_digit = false
                            while i_w >= 1 do
                                local w = words[i_w]
                                local clean_w = w:gsub("[%-,]$", "")
                                if clean_w == "a" and i_w > 1 and words[i_w-1]:gsub("[%-,]$", "") == "half" then
                                    if saw_digit then break end
                                    table.insert(valid_words, 1, "half a")
                                    i_w = i_w - 2
                                else
                                    local val_parsed = xray_units.parseNumberText(clean_w)
                                    if clean_w == "and" or val_parsed then
                                        if saw_digit then break end
                                        if clean_w:match("%d") then
                                            saw_digit = true
                                        end
                                        table.insert(valid_words, 1, clean_w)
                                        i_w = i_w - 1
                                    else
                                        break
                                    end
                                end
                            end
                            
                            -- Check if a minus sign was left just before the matched digit (e.g. separated by space)
                            if i_w >= 1 and words[i_w] == "-" and #valid_words > 0 and saw_digit then
                                valid_words[1] = "-" .. valid_words[1]
                                i_w = i_w - 1
                            end
                            
                            while #valid_words > 0 and valid_words[1] == "and" do
                                table.remove(valid_words, 1)
                            end
                            
                            if #valid_words > 0 then
                                local num_phrase = table.concat(valid_words, " ")
                                val = xray_units.parseNumberText(num_phrase)
                                if val then
                                    num_str = num_phrase
                                end
                            end
                        end
                    end
                end
                
                if val or (val1 and val2) then
                    local matched_unit = matched_alias
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
                                if (before_num:match("%-") or before_num:match("−")) and val > 0 then
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
                        local span_start = hit.start
                        local num_part_clean = num_part:gsub("%s+", "")
                        if num_part_clean == "" or is_range or is_vague then
                            span_start = extend_span_start(doc, hit.start, is_range and val1 or val)
                        end
                        local ok_t, real_text = pcall(function()
                            return doc:getTextFromXPointers(span_start, hit["end"])
                        end)
                        
                        local valid = false
                        local original_text
                        if ok_t and real_text then
                            original_text = real_text:gsub("^%s+", ""):gsub("%s+$", "")
                            
                            -- Reject if resolved text contains newlines, unless matched unit is unambiguous
                            local has_newline = original_text:find("[\r\n]")
                            if not has_newline or not is_ambig[matched_alias] then
                                if has_newline then
                                    original_text = original_text:gsub("[\r\n]+", " "):gsub("%s+", " ")
                                end
                                valid = true
                                if not is_range then
                                    local lower_orig = original_text:gsub("−", "-"):gsub("–", "-"):gsub("—", "-"):lower():gsub("\194\160", " "):gsub("%s+", " ")
                                    local lower_num = num_str:gsub("^%s+", ""):gsub("%s+$", ""):lower():gsub("\194\160", " "):gsub("%s+", " ")
                                    local lower_match = hit.matched_text:lower():gsub("\194\160", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
                                    
                                    if lower_orig ~= lower_match then
                                        if lower_orig:sub(1, #lower_num) == lower_num then
                                            local suffix = lower_orig:sub(#lower_num + 1)
                                            if suffix:sub(-#lower_match) == lower_match then
                                                local middle = suffix:sub(1, #suffix - #lower_match)
                                                if middle:match("[%w]") then
                                                    valid = false
                                                end
                                            end
                                        else
                                            local first_idx = lower_orig:find(lower_num, 1, true)
                                            if first_idx then
                                                local suffix = lower_orig:sub(first_idx + #lower_num)
                                                if suffix:sub(-#lower_match) == lower_match then
                                                    local middle = suffix:sub(1, #suffix - #lower_match)
                                                    if middle:match("[%w]") then
                                                        valid = false
                                                    end
                                                end
                                            else
                                                valid = false
                                            end
                                        end
                                    end
                                end
                            end
                        end
                        
                        if valid then
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
            end

            self.unit_xp_matches = xp_matches
            local t3 = os.clock()
            log(string.format("scanBookForUnits: Lua processing took %.2fs, %d unit matches", t3 - t_start_lua, #xp_matches))
            log(string.format("scanBookForUnits: TOTAL %.2fs", t3 - t0))
            self:saveUnitCache(resolved_dir)
            
            UIManager:show(Notification:new{
                text = tostring(#self.unit_xp_matches) .. " unit conversions found",
                timeout = 3,
                toast = true,
            })
            if self.ui and self.ui.view then
                if self.ui.view.dialog then
                    UIManager:setDirty(self.ui.view.dialog, "ui")
                end
                UIManager:setDirty(nil, "ui")
            end
        end)
        
        self._unit_scan_in_progress = false
        UIManager:close(progress_msg)
        
        if not ok_scan then
            log("scanBookForUnits async error: " .. tostring(err_scan))
        end
    end)
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
    if settings.unit_converter_enabled == false then return false end
    
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
M._draw_underline = _draw_underline
return M
