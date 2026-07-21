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
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")

local BookRow = require("widgets/book_row")
local Heatmap = require("widgets/heatmap")
local Recent = require("common/recent")
local Stats = require("common/stats")
local TopBar = require("widgets/topbar")

local Screen = Device.screen

local HEATMAP_WEEKS = 26
local RECENT_COUNT = 3

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

    local bar = TopBar.build(self:topBarButtons(), self.screen_w)

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

    table.insert(body, VerticalSpan:new{ width = Size.padding.large * 3 })
    table.insert(body, sectionLabel(_("Continue reading"), content_w))
    table.insert(body, VerticalSpan:new{ width = Size.padding.default })

    local books = Recent.getBooks(RECENT_COUNT)
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
                on_tap = function(b) self:openBook(b) end,
            })
        end
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
            bar,
            VerticalSpan:new{ width = Size.padding.large * 2 },
            CenterContainer:new{
                dimen = Geom:new{ w = self.screen_w, h = body:getSize().h },
                body,
            },
        },
    }
end

function HomePage:topBarButtons()
    return {
        {
            icon = "appbar.filebrowser",
            callback = function() self:showFileBrowser() end,
        },
        {
            icon = "appbar.search",
            callback = function()
                UIManager:close(self)
                UIManager:broadcastEvent(require("ui/event"):new("ShowFileSearch"))
            end,
        },
        {
            -- KOReader core ships no history icon; Zen has one (tab_history.svg)
            -- but copying it would pull Zen's GPL-3 into this repo.
            icon = "book.opened",
            callback = function()
                UIManager:close(self)
                UIManager:broadcastEvent(require("ui/event"):new("ShowHist"))
            end,
        },
        {
            icon = "appbar.settings",
            callback = function()
                UIManager:broadcastEvent(require("ui/event"):new("ShowMenu"))
            end,
        },
    }
end

function HomePage:showFileBrowser()
    UIManager:close(self)
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
