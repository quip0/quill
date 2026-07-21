--[[
One entry in the "recently read" strip: cover, title, author, progress bar.
Tapping it opens the book.
--]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local ProgressWidget = require("ui/widget/progresswidget")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")

local Screen = Device.screen

local BookRow = InputContainer:extend{
    book = nil,         -- record from common/recent.lua
    width = nil,
    cover_h = nil,
    on_tap = nil,
}

-- A blank widget with a real width AND height. VerticalSpan/HorizontalSpan each
-- report zero on their other axis, so a FrameContainer built around one of them
-- measures as zero-width and the next widget in a HorizontalGroup overlaps it.
local Spacer = require("ui/widget/widget"):extend{ w = 0, h = 0 }
function Spacer:getSize()
    return Geom:new{ w = self.w, h = self.h }
end

--- Placeholder for books whose cover hasn't been extracted yet.
local function coverPlaceholder(w, h)
    local border = Size.border.thin
    return FrameContainer:new{
        bordersize = border,
        color = Blitbuffer.Color8(0x99),
        background = Blitbuffer.Color8(0xE8),
        padding = 0,
        margin = 0,
        Spacer:new{ w = w - 2 * border, h = h - 2 * border },
    }
end

function BookRow:init()
    local book = self.book
    local cover_h = self.cover_h or Screen:scaleBySize(110)
    local cover_w = math.floor(cover_h * 2 / 3)
    local pad = Size.padding.large

    local cover
    if book.cover_bb then
        cover = ImageWidget:new{
            image = book.cover_bb,
            image_disposable = true,   -- we own this copy
            width = cover_w,
            height = cover_h,
            scale_factor = 0,          -- fit within the box, keep aspect ratio
        }
    else
        cover = coverPlaceholder(cover_w, cover_h)
    end

    local text_w = self.width - cover_w - pad * 3

    local lines = VerticalGroup:new{ align = "left" }
    table.insert(lines, TextWidget:new{
        text = book.title or "",
        face = Font:getFace("cfont", 19),
        bold = true,
        max_width = text_w,
    })
    if book.authors and book.authors ~= "" then
        table.insert(lines, VerticalSpan:new{ width = Size.padding.small })
        table.insert(lines, TextWidget:new{
            text = book.authors,
            face = Font:getFace("cfont", 15),
            fgcolor = Blitbuffer.Color8(0x66),
            max_width = text_w,
        })
    end
    if book.percent then
        table.insert(lines, VerticalSpan:new{ width = Size.padding.default })
        table.insert(lines, ProgressWidget:new{
            width = text_w,
            height = Screen:scaleBySize(6),
            percentage = book.percent,
            margin_h = 0,
            margin_v = 0,
            bordersize = 0,
            bgcolor = Blitbuffer.Color8(0xDD),
            fillcolor = Blitbuffer.Color8(0x44),
        })
        table.insert(lines, VerticalSpan:new{ width = Size.padding.small })
        table.insert(lines, TextWidget:new{
            text = string.format("%d%%", math.floor(book.percent * 100 + 0.5)),
            face = Font:getFace("cfont", 14),
            fgcolor = Blitbuffer.Color8(0x66),
        })
    end

    -- The text stack has a floor of its own (title, author, progress bar,
    -- percentage) and can easily out-measure a shrunken cover. Sizing the
    -- container to the cover alone would let it paint past its own bounds and
    -- silently overlap whatever follows, so the row takes the taller of the two.
    local row_h = math.max(cover_h, lines:getSize().h)

    local row = HorizontalGroup:new{
        align = "center",
        cover,
        HorizontalSpan:new{ width = pad },
        LeftContainer:new{
            dimen = Geom:new{ w = text_w, h = row_h },
            lines,
        },
    }

    self[1] = FrameContainer:new{
        width = self.width,
        bordersize = 0,
        padding = 0,
        margin = 0,
        background = nil,
        row,
    }

    self.dimen = Geom:new{ w = self.width, h = self[1]:getSize().h }

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

function BookRow:onTap()
    if self.on_tap then self.on_tap(self.book) end
    return true
end

return BookRow
