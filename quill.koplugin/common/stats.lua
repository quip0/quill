--[[
Reading statistics access.

Reads KOReader's statistics.sqlite3 (written by statistics.koplugin) and
returns pages-read-per-day, which is what the heatmap renders.
--]]

local logger = require("logger")

local Stats = {}

-- The live statistics plugin buffers the current session in memory. Without
-- forcing a write, today's reading is missing from the database.
local function flushPendingStats()
    local ok, PluginLoader = pcall(require, "pluginloader")
    if not ok then return end
    local plugin = PluginLoader:getPluginInstance("statistics")
    if not plugin then return end
    if type(plugin.isEnabled) == "function" and not plugin:isEnabled() then return end
    pcall(plugin.insertDB, plugin)
end

function Stats.getDbPath()
    local DataStorage = require("datastorage")
    local lfs = require("libs/libkoreader-lfs")
    local primary = DataStorage:getDataDir() .. "/statistics.sqlite3"
    if lfs.attributes(primary, "mode") == "file" then return primary end
    local fallback = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
    if lfs.attributes(fallback, "mode") == "file" then return fallback end
    return primary
end

--- Pages read per day, as a map of "YYYY-MM-DD" -> page count.
-- @param since_ts unix timestamp; only days at or after this are returned
function Stats.getDailyPages(since_ts)
    local result = {}
    flushPendingStats()

    local path = Stats.getDbPath()
    local lfs = require("libs/libkoreader-lfs")
    if lfs.attributes(path, "mode") ~= "file" then
        logger.dbg("quill: no statistics database at", path)
        return result
    end

    local ok_sq, SQ3 = pcall(require, "lua-ljsqlite3/init")
    if not ok_sq then return result end
    local ok_open, conn = pcall(SQ3.open, path)
    if not ok_open or not conn then
        logger.warn("quill: cannot open statistics db:", tostring(conn))
        return result
    end

    -- The inner GROUP BY collapses (book, page, day) so re-reading a page on
    -- the same day counts once; the outer count(*) is therefore distinct pages.
    -- page_stat is a view that rescales historical page numbers to the book's
    -- current page count, so it is the correct source for page *counts*.
    local sql = string.format([[
        SELECT dates, count(*) AS pages
        FROM (
            SELECT strftime('%%Y-%%m-%%d', start_time, 'unixepoch', 'localtime') AS dates,
                   sum(duration) AS sum_duration
            FROM page_stat
            WHERE start_time >= %d
            GROUP BY id_book, page, dates
        )
        GROUP BY dates;
    ]], since_ts or 0)

    local ok_exec, rows = pcall(conn.exec, conn, sql)
    pcall(conn.close, conn)

    if not ok_exec or not rows or not rows.dates then
        if not ok_exec then logger.warn("quill: stats query failed:", tostring(rows)) end
        return result
    end

    for i = 1, #rows.dates do
        result[rows.dates[i]] = tonumber(rows[2][i]) or 0
    end
    return result
end

return Stats
