--[[
Top dashbar: a row of icon buttons with a hairline underneath.

Visually modelled on Zen UI's status bar (flat, borderless, hairline-separated),
but Zen's top bar is informational only -- its buttons live in the bottom
navbar. This combines the two: Zen's top-bar chrome, navbar-style icon buttons.
--]]

local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local LineWidget = require("ui/widget/linewidget")
local Size = require("ui/size")
local VerticalGroup = require("ui/widget/verticalgroup")

local Screen = Device.screen

local TopBar = {}

local function makeButton(spec, icon_size)
    local button = Button:new{
        icon = spec.icon,
        icon_width = icon_size,
        icon_height = icon_size,
        bordersize = 0,
        padding = Size.padding.button,
        callback = spec.callback,
    }
    -- Icons ship as white-on-transparent; keep the alpha channel so they sit
    -- on the page background instead of on a white block.
    local label = button.label_widget
    if label then
        label.alpha = true
        label:free()
    end
    if button.frame then
        button.frame.background = nil
    end
    return button
end

--- @param buttons array of {icon = <icon name>, callback = <fn>}
-- @param width total bar width; defaults to screen width
-- @return a widget, and its height in pixels
function TopBar.build(buttons, width)
    width = width or Screen:getWidth()
    local icon_size = Screen:scaleBySize(28)

    local row = HorizontalGroup:new{}
    local widgets = {}
    local content_w = 0
    for _, spec in ipairs(buttons) do
        local b = makeButton(spec, icon_size)
        widgets[#widgets + 1] = b
        content_w = content_w + b:getSize().w
    end

    -- Space evenly: n+1 equal gaps, so the row reads as balanced whether it
    -- holds three buttons or seven.
    local gap_count = #widgets + 1
    local remaining = math.max(0, width - content_w)
    local base_gap = math.floor(remaining / gap_count)
    local extra = remaining - base_gap * gap_count

    for i, b in ipairs(widgets) do
        table.insert(row, HorizontalSpan:new{ width = base_gap + (i <= extra and 1 or 0) })
        table.insert(row, b)
    end

    local row_h = row:getSize().h
    local bar = VerticalGroup:new{
        align = "center",
        CenterContainer:new{
            dimen = Geom:new{ w = width, h = row_h },
            row,
        },
        LineWidget:new{
            background = Blitbuffer.Color8(0xCC),
            dimen = Geom:new{ w = width, h = Size.line.medium },
        },
    }

    return bar, bar:getSize().h
end

return TopBar
