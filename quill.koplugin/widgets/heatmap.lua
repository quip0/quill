--[[
GitHub/Anki style reading activity heatmap.

One column per week, seven rows (Sunday..Saturday), most recent week on the
right. Cell darkness scales with pages read that day.

Drawn directly into the blitbuffer rather than composed from child widgets:
a year's grid is ~370 cells, and that many FrameContainers is far too much
allocation and layout work for an e-ink refresh.
--]]

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Geom = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")

local SECONDS_PER_DAY = 86400

-- Light to dark. Index 1 is "no reading"; 2..5 are increasing activity.
local LEVEL_COLORS = {
    Blitbuffer.Color8(0xE4),
    Blitbuffer.Color8(0xB4),
    Blitbuffer.Color8(0x84),
    Blitbuffer.Color8(0x50),
    Blitbuffer.Color8(0x18),
}

-- The ring that marks the selected day. Starts on today, then follows taps.
local SELECT_BORDER = 2
local SELECT_COLOR = Blitbuffer.Color8(0x00)

local Heatmap = InputContainer:extend{
    width = nil,        -- required: available width in pixels
    weeks = 26,         -- number of week columns to show
    gap = 3,            -- pixels between cells
    daily = nil,        -- map of "YYYY-MM-DD" -> pages read
    on_tap_day = nil,   -- optional: function(date_str, pages) called on cell tap
}

function Heatmap:init()
    self.daily = self.daily or {}

    -- The selection outline is drawn in the gutter around its cell, so the
    -- widget reserves that much padding on every side. Without it the ring
    -- would paint outside our own dimen on an edge row/column.
    self.inset = math.min(SELECT_BORDER + 1, self.gap)

    -- Derive cell size from the width we were given so the grid always fills it.
    local total_gap = self.gap * (self.weeks - 1)
    local avail_w = self.width - self.inset * 2
    self.cell = math.max(4, math.floor((avail_w - total_gap) / self.weeks))

    -- Recompute width from the rounded cell size to avoid a ragged right edge.
    self.grid_w = self.weeks * self.cell + total_gap + self.inset * 2
    self.grid_h = 7 * self.cell + 6 * self.gap + self.inset * 2

    -- Created up front so the tap GestureRange below (and onTap) can reference
    -- this exact table; paintTo updates its x/y in place rather than replacing
    -- it, keeping the range in sync with where the grid actually lands.
    self.dimen = Geom:new{ x = 0, y = 0, w = self.grid_w, h = self.grid_h }

    self:buildGrid()

    if Device:isTouchDevice() and self.on_tap_day then
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

--- Anchor the grid to noon so daylight-saving shifts can't move a day.
local function dayStart(ts)
    local t = os.date("*t", ts)
    return os.time{ year = t.year, month = t.month, day = t.day, hour = 12 }
end

--- Shade breakpoints for levels 2..5, taken as quartiles of the days that had
-- any reading at all.
--
-- Scaling against the busiest day instead -- the obvious approach -- lets one
-- marathon session flatten the rest of the map: against a 284-page best day,
-- every day under 72 pages draws in the same lightest shade, which is most of a
-- normal reading month. Quartiles spread the five shades over the volumes
-- actually read, so darkness tracks pages the way the map implies it does.
local function computeThresholds(counts)
    if #counts == 0 then return nil end
    table.sort(counts)

    local t = {}
    for i = 1, 3 do
        -- Nearest-rank quantile at 25%, 50% and 75%.
        t[i] = counts[math.max(1, math.ceil(#counts * i / 4))]
    end

    -- With few distinct day totals the quantiles can tie, which would swallow
    -- whole shades; nudge each breakpoint past the previous one so every level
    -- keeps a non-empty range.
    for i = 2, 3 do
        if t[i] <= t[i - 1] then t[i] = t[i - 1] + 1 end
    end
    return t
end

--- Swap in freshly queried counts and rebuild the grid in place.
-- The widget keeps its geometry and its dimen table, so the tap GestureRange
-- registered in init() stays valid; only the shades and totals change.
function Heatmap:setDaily(daily)
    self.daily = daily or {}
    self:buildGrid()
end

function Heatmap:buildGrid()
    local today = dayStart(os.time())
    local wday = tonumber(os.date("%w", today)) -- 0 = Sunday
    local this_sunday = today - wday * SECONDS_PER_DAY
    local first_sunday = this_sunday - (self.weeks - 1) * 7 * SECONDS_PER_DAY

    self.cells = {}
    self.date_lookup = {}   -- (col * 7 + row) -> "YYYY-MM-DD", for tap hit-testing
    self.total_pages = 0
    self.active_days = 0
    self.max_pages = 0

    self.today_date = os.date("%Y-%m-%d", today)
    -- The ring starts on today and follows taps. Until the reader taps, it
    -- tracks today, so a rebuild after midnight moves it to the new day rather
    -- than stranding it on yesterday.
    if not self.user_selected then
        self.selected_date = self.today_date
    end

    -- Page counts for the active days *in view*. Days the query returned that
    -- fall outside the grid must not skew the thresholds for days that are.
    local counts = {}

    for col = 0, self.weeks - 1 do
        for row = 0, 6 do
            local ts = first_sunday + (col * 7 + row) * SECONDS_PER_DAY
            if ts <= today then
                local date = os.date("%Y-%m-%d", ts)
                local pages = self.daily[date] or 0
                self.date_lookup[col * 7 + row] = date
                self.cells[#self.cells + 1] = {
                    col = col,
                    row = row,
                    pages = pages,
                    date = date,
                }
                if pages > 0 then
                    self.total_pages = self.total_pages + pages
                    self.active_days = self.active_days + 1
                    if pages > self.max_pages then self.max_pages = pages end
                    counts[#counts + 1] = pages
                end
            end
        end
    end

    -- Levels are assigned in a second pass: the breakpoints depend on the whole
    -- set of visible days, which isn't known until the loop above finishes.
    self.thresholds = computeThresholds(counts)
    for _, c in ipairs(self.cells) do
        c.level = self:levelFor(c.pages)
    end
end

--- Map a page count onto 1..5 against the quartile breakpoints.
function Heatmap:levelFor(pages)
    if pages <= 0 then return 1 end
    local t = self.thresholds
    if not t then return 2 end
    if pages <= t[1] then return 2 end
    if pages <= t[2] then return 3 end
    if pages <= t[3] then return 4 end
    return 5
end

function Heatmap:getSize()
    return Geom:new{ w = self.grid_w, h = self.grid_h }
end

function Heatmap:paintTo(bb, x, y)
    -- Update in place so the tap GestureRange (which holds this same table)
    -- follows the grid to its painted position.
    self.dimen.x = x
    self.dimen.y = y
    local step = self.cell + self.gap
    local ox, oy = x + self.inset, y + self.inset
    local sel

    for _, c in ipairs(self.cells) do
        local cx, cy = ox + c.col * step, oy + c.row * step
        bb:paintRect(cx, cy, self.cell, self.cell, LEVEL_COLORS[c.level])
        if c.date == self.selected_date then sel = { x = cx, y = cy } end
    end

    -- Outline the selected day in the gutter *around* the cell rather than on
    -- top of it, so the ring stays visible whether the square is empty or
    -- nearly black.
    if sel then
        bb:paintBorder(
            sel.x - self.inset,
            sel.y - self.inset,
            self.cell + self.inset * 2,
            self.cell + self.inset * 2,
            SELECT_BORDER,
            SELECT_COLOR)
    end
end

--- Map a tap back to the day whose cell was hit, and report it to on_tap_day.
-- Returns false for taps that fell in the gutter between cells or on a day
-- outside the drawn range (e.g. a future cell), so the tap can propagate.
function Heatmap:onTap(_, ges)
    if not self.on_tap_day then return false end
    local step = self.cell + self.gap
    local rel_x = ges.pos.x - (self.dimen.x + self.inset)
    local rel_y = ges.pos.y - (self.dimen.y + self.inset)
    if rel_x < 0 or rel_y < 0 then return false end

    local col = math.floor(rel_x / step)
    local row = math.floor(rel_y / step)
    if col < 0 or col >= self.weeks or row < 0 or row > 6 then return false end

    -- Reject taps that landed in the gap between cells rather than on one.
    if rel_x - col * step > self.cell or rel_y - row * step > self.cell then
        return false
    end

    local date = self.date_lookup[col * 7 + row]
    if not date then return false end

    -- Move the ring here; the caller's repaint redraws it at the new day.
    -- Flagged so later rebuilds leave it where the reader put it.
    self.selected_date = date
    self.user_selected = true
    self.on_tap_day(date, self.daily[date] or 0)
    return true
end

return Heatmap
