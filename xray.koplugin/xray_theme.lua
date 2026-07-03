local Screen = require("device").screen
local Font = require("ui/font")
local Blitbuffer = require("ffi/blitbuffer")

local function sc(val)
    return Screen:scaleBySize(val)
end

local M = {
    -- Borders & Separators
    border_line_h = sc(2),
    border_window = sc(2),
    border_btn = sc(2),
    border_preview = sc(2),

    -- Colors
    color_border = Blitbuffer.COLOR_DARK_GRAY,
    color_bg = Blitbuffer.COLOR_WHITE,
    color_label_dim = Blitbuffer.Color8(120),
    color_section_rule = Blitbuffer.COLOR_GRAY_B,

    -- Radii
    radius_window = 0,
    radius_btn = sc(4),

    -- Spacing
    pad_h = sc(28),
    pad_v_top = sc(12),
    pad_v_bottom = sc(12),
    gap = sc(8),
}

function M.getFontSafe(preferred_family, size)
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

return M
