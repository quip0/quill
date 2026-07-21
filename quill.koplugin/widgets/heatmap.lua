--[[
GitHub/Anki style reading activity heatmap.

One column per week, seven rows (Sunday..Saturday), most recent week on the
right. Cell darkness scales with pages read that day.

Drawn directly into the blitbuffer rather than composed from child widgets:
a year's grid is ~370 cells, and that many FrameContainers is far too much
allocation and layout work for an e-ink refresh.
--]]

local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")
local Widget = require("ui/widget/widget")

local SECONDS_PER_DAY = 86400

-- Light to dark. Index 1 is "no reading"; 2..5 are increasing activity.
local LEVEL_COLORS = {
    Blitbuffer.Color8(0xE4),
    Blitbuffer.Color8(0xB4),
    Blitbuffer.Color8(0x84),
    Blitbuffer.Color8(0x50),
    Blitbuffer.Color8(0x18),
}

local TODAY_BORDER = 2
local TODAY_COLOR = Blitbuffer.Color8(0x00)

local Heatmap = Widget:extend{
    width = nil,        -- required: available width in pixels
    weeks = 26,         -- number of week columns to show
    gap = 3,            -- pixels between cells
    daily = nil,        -- map of "YYYY-MM-DD" -> pages read
}

function Heatmap:init()
    self.daily = self.daily or {}

    -- Today's outline is drawn in the gutter around its cell, so the widget
    -- reserves that much padding on every side. Without it the ring would
    -- paint outside our own dimen when today lands on an edge row/column.
    self.inset = math.min(TODAY_BORDER + 1, self.gap)

    -- Derive cell size from the width we were given so the grid always fills it.
    local total_gap = self.gap * (self.weeks - 1)
    local avail_w = self.width - self.inset * 2
    self.cell = math.max(4, math.floor((avail_w - total_gap) / self.weeks))

    -- Recompute width from the rounded cell size to avoid a ragged right edge.
    self.grid_w = self.weeks * self.cell + total_gap + self.inset * 2
    self.grid_h = 7 * self.cell + 6 * self.gap + self.inset * 2

    self:buildGrid()
end

--- Anchor the grid to noon so daylight-saving shifts can't move a day.
local function dayStart(ts)
    local t = os.date("*t", ts)
    return os.time{ year = t.year, month = t.month, day = t.day, hour = 12 }
end

function Heatmap:buildGrid()
    local today = dayStart(os.time())
    local wday = tonumber(os.date("%w", today)) -- 0 = Sunday
    local this_sunday = today - wday * SECONDS_PER_DAY
    local first_sunday = this_sunday - (self.weeks - 1) * 7 * SECONDS_PER_DAY

    local max_pages = 0
    for _, pages in pairs(self.daily) do
        if pages > max_pages then max_pages = pages end
    end
    self.max_pages = max_pages

    self.cells = {}
    self.total_pages = 0
    self.active_days = 0

    for col = 0, self.weeks - 1 do
        for row = 0, 6 do
            local ts = first_sunday + (col * 7 + row) * SECONDS_PER_DAY
            if ts <= today then
                local date = os.date("%Y-%m-%d", ts)
                local pages = self.daily[date] or 0
                self.cells[#self.cells + 1] = {
                    col = col,
                    row = row,
                    level = self:levelFor(pages, max_pages),
                    is_today = ts == today,
                }
                if pages > 0 then
                    self.total_pages = self.total_pages + pages
                    self.active_days = self.active_days + 1
                end
            end
        end
    end
end

--- Map a page count onto 1..5, scaled against the busiest day in range.
function Heatmap:levelFor(pages, max_pages)
    if pages <= 0 then return 1 end
    if max_pages <= 0 then return 1 end
    local level = math.ceil(4 * pages / max_pages)
    if level < 1 then level = 1 end
    if level > 4 then level = 4 end
    return level + 1
end

function Heatmap:getSize()
    return Geom:new{ w = self.grid_w, h = self.grid_h }
end

function Heatmap:paintTo(bb, x, y)
    self.dimen = Geom:new{ x = x, y = y, w = self.grid_w, h = self.grid_h }
    local step = self.cell + self.gap
    local ox, oy = x + self.inset, y + self.inset
    local today

    for _, c in ipairs(self.cells) do
        local cx, cy = ox + c.col * step, oy + c.row * step
        bb:paintRect(cx, cy, self.cell, self.cell, LEVEL_COLORS[c.level])
        if c.is_today then today = { x = cx, y = cy } end
    end

    -- Outline today in the gutter *around* the cell rather than on top of it,
    -- so the ring stays visible whether the square is empty or nearly black.
    if today then
        bb:paintBorder(
            today.x - self.inset,
            today.y - self.inset,
            self.cell + self.inset * 2,
            self.cell + self.inset * 2,
            TODAY_BORDER,
            TODAY_COLOR)
    end
end

return Heatmap
