--[[
A single line of text that answers to a tap.

TextWidget has no gesture handling of its own. This wraps one in an
InputContainer and, importantly, keeps the tap target larger than the glyphs:
a 14pt line is a couple of millimetres tall on a 300ppi panel, which is not
something a thumb can hit reliably. The extra area is kept out of the layout
size, so growing the target does not push the page around.
--]]

local Device = require("device")
local Geom = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextWidget = require("ui/widget/textwidget")

local TapText = InputContainer:extend{
    text = "",
    face = nil,
    fgcolor = nil,
    on_tap = nil,       -- function(); tapping does nothing without it
    tap_width = nil,    -- hit area width; defaults to the text's own width
    tap_pad = 0,        -- hit area added below the line
}

function TapText:init()
    self.label = TextWidget:new{
        text = self.text,
        face = self.face,
        fgcolor = self.fgcolor,
    }
    self[1] = self.label

    local size = self.label:getSize()
    self.dimen = Geom:new{ x = 0, y = 0, w = size.w, h = size.h }

    -- Deliberately a separate table from self.dimen: the layout must measure
    -- the text alone while the hit area is larger. paintTo moves both.
    self.tap_range = Geom:new{
        x = 0, y = 0,
        w = self.tap_width or size.w,
        h = size.h + self.tap_pad,
    }

    if Device:isTouchDevice() and self.on_tap then
        self.ges_events = {
            Tap = {
                require("ui/gesturerange"):new{
                    ges = "tap",
                    range = self.tap_range,
                },
            },
        }
    end
end

function TapText:setText(text)
    self.label:setText(text)
    -- Only the width is refreshed: a single line in a fixed face cannot change
    -- height, and the surrounding layout has already been measured against it.
    local size = self.label:getSize()
    self.dimen.w = size.w
    if not self.tap_width then self.tap_range.w = size.w end
end

function TapText:getSize()
    return Geom:new{ w = self.dimen.w, h = self.dimen.h }
end

function TapText:paintTo(bb, x, y)
    -- Updated in place so the GestureRange, which holds these same tables,
    -- follows the text to wherever it was painted.
    self.dimen.x, self.dimen.y = x, y
    self.tap_range.x, self.tap_range.y = x, y
    self.label:paintTo(bb, x, y)
end

function TapText:onTap()
    if not self.on_tap then return false end
    self.on_tap()
    return true
end

return TapText
