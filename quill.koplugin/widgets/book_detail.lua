--[[
The selected book, spelled out: cover on the left; title, author and progress
on the right, with the button that actually opens it underneath.

The strip below shows covers only, so this panel is where a book gets its name.
It is rebuilt whole each time the selection moves -- one book's worth of
widgets is cheap, and it keeps the panel free of per-field update code.
--]]

local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ImageWidget = require("ui/widget/imagewidget")
local ProgressWidget = require("ui/widget/progresswidget")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")

local Screen = Device.screen

local TITLE_MAX_LINES = 2

local BookDetail = WidgetContainer:extend{
    book = nil,         -- record from common/recent.lua
    width = nil,
    height = nil,       -- the panel is exactly this tall whatever the book
    on_open = nil,      -- function(book), called by the button
}

-- A blank widget with a real width AND height. VerticalSpan/HorizontalSpan each
-- report zero on their other axis, so a FrameContainer built around one of them
-- measures as zero-width and the next widget in a HorizontalGroup overlaps it.
local Spacer = require("ui/widget/widget"):extend{ w = 0, h = 0 }
function Spacer:getSize()
    return Geom:new{ w = self.w, h = self.h }
end

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

--- The title wraps rather than truncates -- this is the one place it is shown --
-- but only as far as TITLE_MAX_LINES, so a runaway subtitle can't push the
-- button out of the bottom of the panel.
local function titleBox(text, width)
    local face = Font:getFace("cfont", 19)
    local box = TextBoxWidget:new{
        text = text, face = face, bold = true, width = width, alignment = "left",
    }
    local max_h = box:getLineHeight() * TITLE_MAX_LINES
    if box:getSize().h <= max_h then return box end
    box:free()
    return TextBoxWidget:new{
        text = text, face = face, bold = true, width = width, alignment = "left",
        height = max_h,
        height_adjust = true,
        height_overflow_show_ellipsis = true,
    }
end

function BookDetail:init()
    local book = self.book
    local cover_h = self.height
    local cover_w = math.floor(cover_h * 2 / 3)
    local pad = Size.padding.large

    local cover
    if book.cover_bb then
        cover = ImageWidget:new{
            image = book.cover_bb,
            -- The page owns the blitbuffer: the strip draws from it too, and
            -- this panel is torn down every time the selection moves.
            image_disposable = false,
            width = cover_w,
            height = cover_h,
            scale_factor = 0,          -- fit within the box, keep aspect ratio
        }
    else
        cover = coverPlaceholder(cover_w, cover_h)
    end

    local text_w = self.width - cover_w - pad * 2

    local info = VerticalGroup:new{ align = "left" }
    table.insert(info, titleBox(book.title or "", text_w))
    if book.authors and book.authors ~= "" then
        table.insert(info, VerticalSpan:new{ width = Size.padding.small })
        table.insert(info, TextWidget:new{
            text = book.authors,
            face = Font:getFace("cfont", 15),
            fgcolor = Blitbuffer.Color8(0x66),
            max_width = text_w,
        })
    end
    table.insert(info, VerticalSpan:new{ width = Size.padding.large })
    table.insert(info, ProgressWidget:new{
        width = text_w,
        height = Screen:scaleBySize(6),
        percentage = book.percent or 0,
        margin_h = 0,
        margin_v = 0,
        bordersize = 0,
        bgcolor = Blitbuffer.Color8(0xDD),
        fillcolor = Blitbuffer.Color8(0x44),
    })
    table.insert(info, VerticalSpan:new{ width = Size.padding.small })
    table.insert(info, TextWidget:new{
        text = book.percent
            and string.format(_("%d%% read"), math.floor(book.percent * 100 + 0.5))
            or _("Not started"),
        face = Font:getFace("cfont", 14),
        fgcolor = Blitbuffer.Color8(0x66),
    })

    local button = Button:new{
        text = _("Continue reading"),
        text_font_size = 17,
        padding_h = Size.padding.large * 2,
        padding_v = Size.padding.default,
        radius = Size.radius.button,
        callback = function()
            if self.on_open then self.on_open(book) end
        end,
    }

    -- The button rides the bottom edge, level with the foot of the cover,
    -- wherever the text above it happens to end.
    local slack = self.height - info:getSize().h - button:getSize().h
    local column = VerticalGroup:new{
        align = "left",
        info,
        VerticalSpan:new{ width = math.max(Size.padding.default, slack) },
        button,
    }

    self[1] = HorizontalGroup:new{
        align = "top",
        -- Boxed so a cover squarer than 2:3 doesn't pull the text column left.
        CenterContainer:new{
            dimen = Geom:new{ w = cover_w, h = cover_h },
            cover,
        },
        HorizontalSpan:new{ width = pad * 2 },
        column,
    }

    self.dimen = Geom:new{ w = self.width, h = self.height }
end

function BookDetail:getSize()
    return self.dimen
end

return BookDetail
