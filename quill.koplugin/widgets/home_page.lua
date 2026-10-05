--[[
The Quill home page.

One screen, top to bottom:
  - top dashbar with icon buttons
  - reading activity heatmap (darker square = more pages that day)
  - the selected book in full, with the button that opens it
  - a strip of the most recently opened books' covers, most recent first

Tapping a cover in the strip selects it; the most recent book is selected
when the page opens.
--]]

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")
local N_ = _.ngettext
local T = require("ffi/util").template

local BookDetail = require("widgets/book_detail")
local CoverCell = require("widgets/cover_cell")
local Heatmap = require("widgets/heatmap")
local Quotes = require("common/quotes")
local Recent = require("common/recent")
local Stats = require("common/stats")
local TapText = require("widgets/tap_text")

local Screen = Device.screen

local HEATMAP_WEEKS = 26
local RECENT_COUNT = 6

-- Height of the selected-book panel, before screen scaling. Tall enough for a
-- two-line title, author, progress and the button beside a 2:3 cover.
local DETAIL_HEIGHT = 160

-- How often the open page re-checks the statistics database. The check itself
-- is two lfs.attributes() calls, and nothing is redrawn unless the numbers
-- moved, so this is cheap enough to run while the home screen sits idle.
local REFRESH_INTERVAL = 60

-- Tapping the summary line walks through these in order and wraps around.
-- Every scope reports both a page count and the number of days it was spread
-- over, so the tap only changes the window, never the shape of the sentence.
local SUMMARY_SCOPES = { "all", "year", "month", "week" }
local SUMMARY_FORMAT = {
    all   = _("%1 over %2"),
    year  = _("%1 over %2 this year"),
    month = _("%1 over %2 this month"),
    week  = _("%1 over %2 this week"),
}
-- Remembered globally rather than per page: the home page is rebuilt every time
-- a book is closed, so an instance field would snap back to "all" constantly.
local SETTING_SUMMARY_SCOPE = "quill_summary_scope"

-- The quote sets at QUOTE_MAX_PT and steps down a point at a time until the
-- page fits. Nothing below QUOTE_MIN_PT is worth reading on e-ink.
local QUOTE_MAX_PT = 15
local QUOTE_MIN_PT = 9

local HomePage = InputContainer:extend{
    covers_fullscreen = true,
}

-- "2026-07-22" -> "Jul 22, 2026". Anchored at noon so the label can't slip a
-- day on a daylight-saving boundary.
local function formatDay(date_str)
    local y, m, d = date_str:match("(%d+)-(%d+)-(%d+)")
    if not y then return date_str end
    local ts = os.time{ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 }
    return os.date("%b %d, %Y", ts)
end

--- The first day a scope covers, as "YYYY-MM-DD", or nil for all of history.
-- ISO dates sort lexicographically, so callers can compare with plain <=.
-- Weeks start on Sunday, matching the heatmap's rows.
local function scopeStart(scope)
    local t = os.date("*t")
    if scope == "year" then
        return string.format("%04d-01-01", t.year)
    elseif scope == "month" then
        return string.format("%04d-%02d-01", t.year, t.month)
    elseif scope == "week" then
        -- Anchored at noon so a daylight-saving shift can't land the subtraction
        -- on the wrong calendar day. wday is 1 on Sunday.
        local noon = os.time{ year = t.year, month = t.month, day = t.day, hour = 12 }
        return os.date("%Y-%m-%d", noon - (t.wday - 1) * 86400)
    end
    return nil
end

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

    -- Held as a field so it can be unscheduled by identity on close; a fresh
    -- closure each time would leave the old one queued.
    self.refresh_task = function()
        self:refreshStats()
        self:scheduleRefresh()
    end

    self:build()
end

function HomePage:build()
    local margin = Size.padding.large * 2
    local content_w = self.screen_w - margin * 2

    -- Stamped before the query, so a write that lands while we read is caught
    -- by the next refresh rather than being mistaken for already-loaded data.
    self.stats_stamp = Stats.getStamp()
    self.today_date = os.date("%Y-%m-%d")

    self.summary_scope = self:readScope()

    -- The whole history, not just the drawn window: the summary line can be
    -- asked for an all-time total, and the heatmap ignores dates outside the
    -- half-year it draws. Unbounded costs no more than a bounded query --
    -- there is no index on start_time either way, and the rows are few.
    self.daily = Stats.getDailyPages(0)
    local heatmap = Heatmap:new{
        width = content_w,
        weeks = HEATMAP_WEEKS,
        daily = self.daily,
        -- Tapping a day swaps the "today" line for that day's total; the
        -- default line comes back the next time the page is opened.
        on_tap_day = function(date) self:showDay(date) end,
    }
    self.heatmap = heatmap

    local body = VerticalGroup:new{ align = "left" }
    table.insert(body, sectionLabel(_("Reading activity"), content_w))
    table.insert(body, VerticalSpan:new{ width = Size.padding.default })
    self.day_line = TextWidget:new{
        text = self:todayText(),
        face = Font:getFace("NotoSans-Italic.ttf", 16),
    }
    table.insert(body, self.day_line)
    table.insert(body, VerticalSpan:new{ width = Size.padding.default })
    table.insert(body, heatmap)
    table.insert(body, VerticalSpan:new{ width = Size.padding.default })
    self.summary_line = TapText:new{
        text = self:summaryText(),
        face = Font:getFace("cfont", 14),
        fgcolor = Blitbuffer.Color8(0x77),
        -- The line is short and thin; the whole width of the column and the
        -- gap under it are given over to the target so it can be hit at all.
        tap_width = content_w,
        tap_pad = Size.padding.default,
        on_tap = function() self:cycleSummaryScope() end,
    }
    table.insert(body, self.summary_line)

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

    -- Kept as references: once everything is measured, whatever vertical room
    -- is still unused is split between these two gaps, so the detail panel
    -- floats midway between the quote and the strip, and the strip sits against
    -- the bottom of the panel instead of leaving a dead band under it.
    local gap_above = VerticalSpan:new{ width = Size.padding.large * 3 }
    local gap_below = VerticalSpan:new{ width = Size.padding.large * 2 }
    table.insert(body, gap_above)
    -- The selected book's details land here once the books are loaded; the
    -- holder keeps a fixed size so swapping its contents never moves the page.
    self.detail_h = Screen:scaleBySize(DETAIL_HEIGHT)
    self.detail_holder = LeftContainer:new{
        dimen = Geom:new{ w = content_w, h = self.detail_h },
        VerticalSpan:new{ width = 0 },
    }
    self.content_w = content_w
    table.insert(body, self.detail_holder)
    table.insert(body, gap_below)
    table.insert(body, sectionLabel(_("Recent books"), content_w))
    table.insert(body, VerticalSpan:new{ width = Size.padding.default })

    -- The covers share the column width equally. Height only becomes the
    -- limit on a short or landscape panel, where the strip gives way rather
    -- than push the page past the bottom of the screen.
    -- getSize() memoizes child offsets, so anything measured mid-build must be
    -- followed by resetLayout() once the remaining children are appended --
    -- otherwise paintTo walks a stale offset table and indexes nil.
    local cover_gap = Size.padding.large
    local cover_w = math.floor((content_w - cover_gap * (RECENT_COUNT - 1)) / RECENT_COUNT)
    local cover_h = math.floor(cover_w * 3 / 2)
    local used_h = body:getSize().h + Size.padding.large * 6
    local room_h = self.screen_h - used_h - (CoverCell.heightFor(cover_h) - cover_h)
    if cover_h > room_h then
        cover_h = math.max(Screen:scaleBySize(64), room_h)
        cover_w = math.floor(cover_h * 2 / 3)
    end

    -- Asked for at the detail panel's size, the larger of the two places a
    -- cover is drawn, so a cover extracted here is sharp in both.
    self.books = Recent.getBooks(RECENT_COUNT,
        math.floor(self.detail_h * 2 / 3), self.detail_h)
    self.cells = {}
    if #self.books == 0 then
        table.insert(body, TextWidget:new{
            text = _("No books opened yet."),
            face = Font:getFace("cfont", 16),
            fgcolor = Blitbuffer.Color8(0x77),
        })
    else
        local strip = HorizontalGroup:new{ align = "top" }
        for i, book in ipairs(self.books) do
            if i > 1 then
                table.insert(strip, HorizontalSpan:new{ width = cover_gap })
            end
            local cell = CoverCell:new{
                book = book,
                cover_w = cover_w,
                cover_h = cover_h,
                -- The most recent book is the one on show when the page opens.
                selected = i == 1,
                on_tap = function(c) self:selectCell(c) end,
            }
            self.cells[i] = cell
            table.insert(strip, cell)
        end
        table.insert(body, strip)
        self.selected_cell = self.cells[1]
        self.detail_holder[1] = self:buildDetail(self.books[1])
    end

    body:resetLayout()

    -- Absorb the leftover strip at the bottom. Measured after resetLayout so the
    -- group re-adds up the rows that were appended past the mid-build getSize().
    local top_pad = Size.padding.large * 3
    local leftover = self.screen_h - top_pad * 2 - body:getSize().h

    -- A long quote can eat the room the book strip needs. Rather than truncate it,
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
        local half = math.floor(leftover / 2)
        gap_above.width = gap_above.width + half
        gap_below.width = gap_below.width + leftover - half
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

--- Keyed by local calendar date, same as the stats query, so the counter
-- naturally starts over at zero when the day rolls over.
function HomePage:todayText()
    local pages = self.daily[self.today_date] or 0
    return pages == 1
        and _("1 page read today")
        or string.format(_("%d pages read today"), pages)
end

--- Read the remembered summary scope, discarding anything unrecognised so a
-- stale or hand-edited setting can't leave the line with no format string.
function HomePage:readScope()
    local gs = rawget(_G, "G_reader_settings")
    local saved = gs and gs:readSetting(SETTING_SUMMARY_SCOPE)
    for _idx, scope in ipairs(SUMMARY_SCOPES) do
        if saved == scope then return saved end
    end
    return SUMMARY_SCOPES[1]
end

--- Totals for the current scope, summed straight from the daily counts rather
-- than re-queried: the map already holds every day of history, so switching
-- scope is arithmetic over a few hundred entries and needs no database round
-- trip on the tap.
function HomePage:summaryText()
    local from = scopeStart(self.summary_scope)
    local pages, days = 0, 0
    for date, n in pairs(self.daily) do
        if n > 0 and (not from or date >= from) then
            pages = pages + n
            days = days + 1
        end
    end
    return T(SUMMARY_FORMAT[self.summary_scope],
        T(N_("1 page", "%1 pages", pages), pages),
        T(N_("1 day", "%1 days", days), days))
end

--- Step the summary line to the next scope, wrapping at the end.
function HomePage:cycleSummaryScope()
    local next_idx = 1
    for i, scope in ipairs(SUMMARY_SCOPES) do
        if scope == self.summary_scope then
            next_idx = i % #SUMMARY_SCOPES + 1
            break
        end
    end
    self.summary_scope = SUMMARY_SCOPES[next_idx]

    local gs = rawget(_G, "G_reader_settings")
    if gs then gs:saveSetting(SETTING_SUMMARY_SCOPE, self.summary_scope) end

    self.summary_line:setText(self:summaryText())
    UIManager:setDirty(self, "ui")
end

--- The wording for whichever day the ring currently sits on. Today keeps the
-- "pages read today" phrasing rather than restating its own date.
function HomePage:dayText(date)
    if date == self.today_date then return self:todayText() end
    return string.format(_("Pages read on %s: %d"),
        formatDay(date), self.daily[date] or 0)
end

--- Show a tapped day's page total in place of the "pages read today" line.
-- The line keeps its font and single-line height, so only its text changes and
-- the surrounding layout stays put; a ui refresh repaints over the old text.
function HomePage:showDay(date)
    if not self.day_line then return end
    self.day_line:setText(self:dayText(date))
    UIManager:setDirty(self, "ui")
end

--- Re-read the statistics database and update the activity block in place.
--
-- This is what keeps the page honest while KOReader stays up: pages read in a
-- session reach the database only when the statistics plugin flushes, and the
-- day rolls over at midnight regardless of whether anything was redrawn.
--
-- Nothing is repainted unless the numbers actually moved -- an unnecessary
-- refresh is a visible flash on e-ink, and this runs on a timer.
-- @param force re-query even if the database looks untouched
function HomePage:refreshStats(force)
    if not self.heatmap then return end

    Stats.flush()
    local stamp = Stats.getStamp()
    local today = os.date("%Y-%m-%d")
    if not force and stamp == self.stats_stamp and today == self.today_date then
        return
    end
    self.stats_stamp = stamp
    self.today_date = today

    self.daily = Stats.getDailyPages(0, true)
    -- Rebuilds the grid against the new counts, which also re-derives the shade
    -- breakpoints and walks today's column forward if the date changed.
    self.heatmap:setDaily(self.daily)

    self.day_line:setText(self:dayText(self.heatmap.selected_date))
    self.summary_line:setText(self:summaryText())
    UIManager:setDirty(self, "ui")
end

function HomePage:scheduleRefresh()
    UIManager:unschedule(self.refresh_task)
    UIManager:scheduleIn(REFRESH_INTERVAL, self.refresh_task)
end

function HomePage:buildDetail(book)
    return BookDetail:new{
        book = book,
        width = self.content_w,
        height = self.detail_h,
        on_open = function(b) self:openBook(b) end,
    }
end

--- Move the selection to a tapped cover and show that book in the panel.
-- Selecting never opens anything; only the panel's button does that.
function HomePage:selectCell(cell)
    if cell == self.selected_cell then return end
    if self.selected_cell then self.selected_cell:setSelected(false) end
    cell:setSelected(true)
    self.selected_cell = cell

    local old = self.detail_holder[1]
    self.detail_holder[1] = self:buildDetail(cell.book)
    if old and old.free then old:free() end
    UIManager:setDirty(self, "ui")
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
    -- Covers the page being uncovered after a book was read on top of it: the
    -- data it was built with can be a whole session out of date by now.
    self:refreshStats()
    self:scheduleRefresh()
    UIManager:setDirty(self, "full")
    return true
end

--- Waking is the one moment the page is guaranteed to be stale: the timer does
-- not run while the device is asleep, and the sleep may have crossed midnight.
-- Not consumed -- other widgets still need the event.
function HomePage:onResume()
    self:refreshStats()
    self:scheduleRefresh()
end

function HomePage:onCloseWidget()
    UIManager:unschedule(self.refresh_task)
    -- The cover blitbuffers are ours: the widgets only ever drew scaled copies.
    for _idx, book in ipairs(self.books or {}) do
        if book.cover_bb then
            book.cover_bb:free()
            book.cover_bb = nil
        end
    end
    UIManager:setDirty(nil, "full")
end

return HomePage
