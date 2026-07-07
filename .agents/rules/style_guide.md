---
trigger: always_on
---

# X-Ray Plugin UI Style Guide

This style guide establishes consistent layout, borders, and colors for all dialogs, modals, and popups in the X-Ray plugin. It defines standard reusable patterns and tokens using `xray_theme.lua` and KOReader design system components.

---

## 1. Theme Design Tokens

Always use these tokens from `xray_theme` or Screen calculations to maintain visual consistency across all screen resolutions and DPIs:

| Token Name | Reference Value | Purpose |
|---|---|---|
| `border_line_h` | `sc(2)` | Thickness of separator lines and separators |
| `border_window` | `sc(2)` | Outer borders of modal windows / cards |
| `border_btn` | `sc(2)` | Border thickness for buttons (Close, option buttons) |
| `border_preview` | `sc(2)` | Border thickness of internal preview panels |
| `color_border` | `Blitbuffer.COLOR_DARK_GRAY` | Main border color |
| `color_bg` | `Blitbuffer.COLOR_WHITE` | Background color for modals and buttons |
| `color_label_dim` | `Blitbuffer.Color8(120)` | Faded text color for section headers and caps |
| `color_section_rule`| `Blitbuffer.COLOR_GRAY_B` | Color of separator lines and unselected button borders |
| `radius_window` | `0` | Radius for modals (always sharp, non-rounded corner) |
| `radius_btn` | `sc(4)` | Radius for buttons (slightly rounded) |
| `gap` | `sc(8)` | Vertical/horizontal gap spacer standard |
| `face_label_size`| `14` | Font size for section labels and headers |

---

## 2. Modal & Settings Card Layout

### Nesting Math (Double Borders)
To prevent 1px subpixel rounding gaps or misalignment on high-DPI e-ink screens (e.g. Kindle Paperwhite):
- Always nest the inner settings card (`bordersize = sc(2)`) inside a wrapper outer card (`bordersize = sc(1)`).
- Hardcode the outer card to the exact target width: `width = dialog_w`.
- Set the inner card width to exactly `width = dialog_w - sc(2)` to subtract the outer border size from the layout.

```lua
local card = FrameContainer:new{
    padding = sc(12),
    radius = xray_theme.radius_window,
    bordersize = sc(2),
    color = Blitbuffer.COLOR_BLACK,
    background = xray_theme.color_bg,
    width = dialog_w - sc(2), -- Inner card width
    VerticalGroup:new{
        align = "left",
        title_label,
        span(),
        preview_panel,
        span(),
        label("Section Header"),
        style_row_1,
        WidgetContainer:new{ dimen = Geom:new{ w = 1, h = sc(4) } },
        style_row_2,
        span(),
        close_btn,
    }
}

local card_outer = FrameContainer:new{
    bordersize = sc(1),
    color = Blitbuffer.Color8(180),
    padding = 0,
    background = xray_theme.color_bg,
    radius = xray_theme.radius_window,
    width = dialog_w, -- Outer card width
    card
}
```

### Option Button Picker rows
Grouped inputs (radio-button equivalents) should use filled buttons with standard borders that visually highlight selection:
- **Selected**: Solid border (`border_btn`), bullet point (`●`).
- **Unselected**: Thin gray border (`sc(1)`), empty circle (`○`).
```lua
local frame = FrameContainer:new{
    bordersize = is_selected and xray_theme.border_btn or sc(1),
    radius = xray_theme.radius_btn,
    padding = sc(6),
    color = is_selected and xray_theme.color_border or xray_theme.color_section_rule,
    background = xray_theme.color_bg,
    HorizontalGroup:new{
        align = "center",
        TextWidget:new{ text = is_selected and "●" or "○", face = Font:getFace("cfont", 16) },
        WidgetContainer:new{ dimen = Geom:new{ w = sc(4), h = 1 } },
        TextWidget:new{ text = opt.text, face = Font:getFace("cfont", 16) },
    }
}
```

### Multi-Row translation safe wrapping
When option picker groups have more than 3 options or contain translatable text (which can vary widely in length), split them into multiple horizontal rows stacked vertically with a `sc(4)` gap. Never force them into a single row.

---

## 3. Footnote Style Display (Bottom Popup)

The bottom-panel inline popup (`XRayBottomPopup`) is aligned flush to the bottom of the screen to match KOReader footnote styling:
- **Top Separator**: A solid dark gray `LineWidget` of width `sw` and height `line_h` (usually 2px).
- **Background Container**: A borderless `FrameContainer` (`bordersize = 0`, `radius = 0`, background `COLOR_WHITE`) occupying the full screen width (`width = sw`).
- **Inner Padding**: Standard top padding is `math.floor(fs * 0.55)` and bottom padding is `math.floor(fs * 0.85)` (plus safe area offset on Android devices). Standard horizontal padding (`padding_left`/`padding_right`) is `28px`.
- **Positioning**: Align bottom popup content with `BottomContainer` widget flush to `y = sh - popup_h`. Tap-outside region covers the top `y = 0` to `y = sh - popup_h`.

```lua
local separator = LineWidget:new{
    dimen      = Geom:new{ w = sw, h = line_h },
    background = Blitbuffer.COLOR_DARK_GRAY,
}

local popup_frame = FrameContainer:new{
    background = Blitbuffer.COLOR_WHITE,
    bordersize = 0,
    radius     = 0,
    padding    = 0,
    width      = sw,
    VerticalGroup:new{
        align = "left",
        separator,
        FrameContainer:new{
            background     = Blitbuffer.COLOR_WHITE,
            bordersize     = 0,
            radius         = 0,
            padding_top    = pad_top_px,
            padding_bottom = pad_bottom_px,
            padding_left   = pad,
            padding_right  = pad,
            width          = sw,
            inner_content_vg,
        }
    }
}
```

---

## 4. Classic Style Display

The classic display uses KOReader's fullscreen / large menu dialog format (`ButtonDialog`):
- **Size**: Centered dialog box with width `math.floor(math.min(sw, sh) * 0.9)`.
- **Typography & Font**: Text components (Name, Description, Attributes) should be built inside a `VerticalGroup` of `TextBoxWidget` items utilizing `cfont`.
- **Hierarchy**:
  1. Title/Name: Bold `TextBoxWidget` utilizing font size `fs`.
  2. Aliases/Attributes: Faded label headers (e.g. `ALIASES:` in `fs - 4` font size).
  3. Description: Plain `TextBoxWidget` utilizing font size `fs`.
- **Button Table**: Set at the bottom containing standard callbacks for `Find Mentions`, `Linked Entries`, and `Close`.

---

## 5. Custom Underline Rendering

- To keep rendering smooth and pixelation-free on e-ink, custom underlines (like waves or circles) must not be painted using manual pixel grids at small scales.
- Render SVG vector templates (like `wavy-underline.svg` or custom vector circle strings) to a cached `Blitbuffer` tile at the target DPI-scaled thickness.
- Blit these tiles to the screen using `bb:alphablitFrom` to ensure clean anti-aliasing edges on the curves.
