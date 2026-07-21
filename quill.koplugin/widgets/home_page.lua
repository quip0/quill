--[[
The Quill home page.

One screen, top to bottom:
  - top dashbar with icon buttons
  - reading activity heatmap (darker square = more pages that day)
  - the three most recently opened books, most recent first
--]]

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")

local BookRow = require("widgets/book_row")
local Heatmap = require("widgets/heatmap")
local Quotes = require("common/quotes")
local Recent = require("common/recent")
local Stats = require("common/stats")

local Screen = Device.screen

local HEATMAP_WEEKS = 26
local RECENT_COUNT = 3

-- The quote sets at QUOTE_MAX_PT and steps down a point at a time until the
-- page fits. Nothing below QUOTE_MIN_PT is worth reading on e-ink.
local QUOTE_MAX_PT = 15
local QUOTE_MIN_PT = 9

local HomePage = InputContainer:extend{
    covers_fullscreen = true,
}

local function sectionLabel(text, width)
    return LeftContainer:new{
        dimen = Geom:new{ w = width, h = Screen:scaleBySize(24) },
        TextWidget:new{
            text = text,
            face = Font:getFace("cfont", 16),
            bold = true,
            fgcolor = Blitbuffer.Color8(0x55),
        },
    }
end

function HomePage:init()
    self.screen_w = Screen:getWidth()
    self.screen_h = Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.screen_w, h = self.screen_h }

    if Device:isTouchDevice() then
        self.ges_events = {
            Close = {
                require("ui/gesturerange"):new{
                    ges = "swipe",
                    range = self.dimen,
                    direction = "south",
                },
            },
        }
    end
    self.key_events = { Close = { { Device.input.group.Back } } }

    self:build()
end

function HomePage:build()
    local margin = Size.padding.large * 2
    local content_w = self.screen_w - margin * 2

    -- Half a year of history is enough to read at a glance without the
    -- squares getting too small on a 6.8" panel.
    local since = os.time() - HEATMAP_WEEKS * 7 * 86400
    local heatmap = Heatmap:new{
        width = content_w,
        weeks = HEATMAP_WEEKS,
        daily = Stats.getDailyPages(since),
    }

    local summary = string.format(
        _("%d pages over %d days"), heatmap.total_pages, heatmap.active_days)

    local body = VerticalGroup:new{ align = "left" }
    table.insert(body, sectionLabel(_("Reading activity"), content_w))
    table.insert(body, VerticalSpan:new{ width = Size.padding.default })
    table.insert(body, heatmap)
    table.insert(body, VerticalSpan:new{ width = Size.padding.default })
    table.insert(body, TextWidget:new{
        text = summary,
        face = Font:getFace("cfont", 14),
        fgcolor = Blitbuffer.Color8(0x77),
    })

    -- Zen UI's quote of the day, sitting between the activity block and the
    -- books. Skipped entirely when Zen UI isn't installed or its list is empty,
    -- so the rest of the page just closes up around it.
    local quote = Quotes.getDaily()
    local quote_box, quote_index
    local buildQuoteBox
    if quote then
        -- The quote is never truncated: when the page runs long the type size
        -- comes down instead, so a wordy quote simply sets smaller.
        buildQuoteBox = function(pt)
            return TextBoxWidget:new{
                text = "\226\128\156" .. quote.text .. "\226\128\157",
                width = content_w,
                face = Font:getFace("cfont", pt),
                alignment = "left",
            }
        end
        table.insert(body, VerticalSpan:new{ width = Size.padding.large * 3 })
        quote_box = buildQuoteBox(QUOTE_MAX_PT)
        table.insert(body, quote_box)
        quote_index = #body
        if quote.author ~= "" then
            table.insert(body, VerticalSpan:new{ width = Size.padding.small })
            table.insert(body, TextWidget:new{
                text = "\226\128\148 " .. quote.author,
                face = Font:getFace("cfont", 13),
                fgcolor = Blitbuffer.Color8(0x77),
            })
        end
    end

    -- Kept as a reference: once the rows are measured, whatever vertical room
    -- is still unused gets folded into this gap, so the book strip sits against
    -- the bottom of the panel instead of leaving a dead band under it.
    local flex_gap = VerticalSpan:new{ width = Size.padding.large * 3 }
    table.insert(body, flex_gap)
    table.insert(body, sectionLabel(_("Continue reading"), content_w))
    table.insert(body, VerticalSpan:new{ width = Size.padding.default })

    -- Size the covers to whatever vertical room is left, so all three rows fit
    -- regardless of panel height, and never exceed a comfortable maximum.
    -- getSize() memoizes child offsets, so anything measured mid-build must be
    -- followed by resetLayout() once the remaining children are appended --
    -- otherwise paintTo walks a stale offset table and indexes nil.
    local used_h = body:getSize().h + Size.padding.large * 4
    local per_row = math.floor((self.screen_h - used_h) / RECENT_COUNT)
    local cover_h = math.max(
        Screen:scaleBySize(64),
        math.min(Screen:scaleBySize(120), per_row - Size.padding.large * 2))
    local cover_w = math.floor(cover_h * 2 / 3)

    local books = Recent.getBooks(RECENT_COUNT, cover_w, cover_h)
    if #books == 0 then
        table.insert(body, TextWidget:new{
            text = _("No books opened yet."),
            face = Font:getFace("cfont", 16),
            fgcolor = Blitbuffer.Color8(0x77),
        })
    else
        for i, book in ipairs(books) do
            if i > 1 then
                table.insert(body, VerticalSpan:new{ width = Size.padding.large * 2 })
            end
            table.insert(body, BookRow:new{
                book = book,
                width = content_w,
                cover_h = cover_h,
                on_tap = function(b) self:openBook(b) end,
            })
        end
    end

    body:resetLayout()

    -- Absorb the leftover strip at the bottom. Measured after resetLayout so the
    -- group re-adds up the rows that were appended past the mid-build getSize().
    local top_pad = Size.padding.large * 3
    local leftover = self.screen_h - top_pad * 2 - body:getSize().h

    -- A long quote can eat the room the book rows need. Rather than truncate it,
    -- step the type down a point at a time until the whole thing fits: the quote
    -- is the only block on the page that can give, and every word stays on
    -- screen. Long quotes just set smaller than short ones.
    if leftover < 0 and quote_box then
        for pt = QUOTE_MAX_PT - 1, QUOTE_MIN_PT, -1 do
            local smaller = buildQuoteBox(pt)
            quote_box:free()
            body[quote_index] = smaller
            quote_box = smaller
            body:resetLayout()
            leftover = self.screen_h - top_pad * 2 - body:getSize().h
            if leftover >= 0 then break end
        end
    end

    if leftover > 0 then
        flex_gap.width = flex_gap.width + leftover
        body:resetLayout()
    end

    self[1] = FrameContainer:new{
        width = self.screen_w,
        height = self.screen_h,
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = 0,
        margin = 0,
        VerticalGroup:new{
            align = "left",
            VerticalSpan:new{ width = top_pad },
            CenterContainer:new{
                dimen = Geom:new{ w = self.screen_w, h = body:getSize().h },
                body,
            },
        },
    }
end

function HomePage:openBook(book)
    UIManager:close(self)
    local ReaderUI = require("apps/reader/readerui")
    ReaderUI:showReader(book.path)
end

function HomePage:onClose()
    UIManager:close(self)
    return true
end

function HomePage:onShow()
    UIManager:setDirty(self, "full")
    return true
end

function HomePage:onCloseWidget()
    UIManager:setDirty(nil, "full")
end

return HomePage
