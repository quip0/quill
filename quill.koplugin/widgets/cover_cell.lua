--[[
One book in the recent-books strip: the cover with a thin progress bar under
it, and nothing else. Tapping it selects the book -- the page shows its details
above the strip -- and the selected cell wears a ring.

Every cell is the same size whatever the cover's own proportions, so the bars
line up along the bottom of the strip and the tap targets are predictable.
--]]

local Blitbuffer = require("ffi/blitbuffer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local ProgressWidget = require("ui/widget/progresswidget")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")

local Screen = Device.screen

local CoverCell = InputContainer:extend{
    book = nil,         -- record from common/recent.lua
    cover_w = nil,
    cover_h = nil,
    selected = false,
    on_tap = nil,       -- function(cell)
}

local BAR_H = Screen:scaleBySize(6)
local BAR_GAP = Size.padding.default

-- The ring that marks the selected book. Every cell reserves the room for it
-- and unselected ones simply draw it in white, so moving the selection never
-- shifts a cover.
local RING = Size.border.thick
local RING_GAP = Size.border.thick
local RING_ON = Blitbuffer.COLOR_BLACK
local RING_OFF = Blitbuffer.COLOR_WHITE

--- The height a cell takes for a given cover height, so the page can budget
-- for the strip before any cell exists.
function CoverCell.heightFor(cover_h)
    return cover_h + BAR_GAP + BAR_H
end

--- Stand-in for books with no cover to show. With the title gone from the
-- strip, a blank box would be unidentifiable, so the title is set inside it.
local function coverPlaceholder(book, w, h)
    local border = Size.border.thin
    local pad = Size.padding.default
    local inner_w = w - 2 * border
    local inner_h = h - 2 * border
    return FrameContainer:new{
        bordersize = border,
        color = Blitbuffer.Color8(0x99),
        background = Blitbuffer.Color8(0xE8),
        padding = 0,
        margin = 0,
        CenterContainer:new{
            dimen = Geom:new{ w = inner_w, h = inner_h },
            TextBoxWidget:new{
                text = book.title or "",
                face = Font:getFace("cfont", 12),
                width = inner_w - 2 * pad,
                -- Clipped to the box rather than left to run out of the bottom.
                height = inner_h - 2 * pad,
                height_adjust = true,
                height_overflow_show_ellipsis = true,
                alignment = "center",
                bgcolor = Blitbuffer.Color8(0xE8),
            },
        },
    }
end

function CoverCell:init()
    local book = self.book
    local cover_w, cover_h = self.cover_w, self.cover_h
    local inset = (RING + RING_GAP) * 2
    local box_w, box_h = cover_w - inset, cover_h - inset

    local cover
    if book.cover_bb then
        cover = ImageWidget:new{
            image = book.cover_bb,
            -- The page owns the blitbuffer; the detail panel draws from it too.
            image_disposable = false,
            width = box_w,
            height = box_h,
            scale_factor = 0,          -- fit within the box, keep aspect ratio
        }
    else
        cover = coverPlaceholder(book, box_w, box_h)
    end

    self.ring = FrameContainer:new{
        bordersize = RING,
        padding = RING_GAP,
        margin = 0,
        color = self.selected and RING_ON or RING_OFF,
        -- Covers narrower or squatter than the box sit on its bottom edge, so
        -- a row of mixed proportions still shares a baseline with the bars.
        BottomContainer:new{
            dimen = Geom:new{ w = box_w, h = box_h },
            cover,
        },
    }

    self[1] = VerticalGroup:new{
        align = "center",
        self.ring,
        VerticalSpan:new{ width = BAR_GAP },
        -- Always drawn, empty for a book with no progress recorded, so every
        -- cell has the same outline.
        ProgressWidget:new{
            width = cover_w,
            height = BAR_H,
            percentage = book.percent or 0,
            margin_h = 0,
            margin_v = 0,
            bordersize = 0,
            bgcolor = Blitbuffer.Color8(0xDD),
            fillcolor = Blitbuffer.Color8(0x44),
        },
    }

    self.dimen = Geom:new{ w = cover_w, h = CoverCell.heightFor(cover_h) }

    if Device:isTouchDevice() and self.on_tap then
        self.ges_events = {
            Tap = {
                require("ui/gesturerange"):new{
                    ges = "tap",
                    range = self.dimen,
                },
            },
        }
    end
end

--- Draw or clear the ring. The caller repaints.
function CoverCell:setSelected(selected)
    self.selected = selected
    self.ring.color = selected and RING_ON or RING_OFF
end

function CoverCell:onTap()
    if self.on_tap then self.on_tap(self) end
    return true
end

return CoverCell
