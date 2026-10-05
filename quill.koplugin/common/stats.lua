--[[
Reading statistics access.

Reads KOReader's statistics.sqlite3 (written by statistics.koplugin) and
returns pages-read-per-day, which is what the heatmap renders.
--]]

local logger = require("logger")

local Stats = {}

--- Push the live statistics plugin's in-memory buffer out to the database.
-- The current session is only held in RAM until something triggers insertDB(),
-- so without this the pages read since the book was opened are missing.
function Stats.flush()
    -- ReaderUI:onClose() runs PluginLoader:finalize() *before* the FileManager
    -- is rebuilt, which empties the loader's table -- so ask the live reader
    -- first and only fall back to the loader.
    local plugin
    local ok_ui, ReaderUI = pcall(require, "apps/reader/readerui")
    if ok_ui and ReaderUI.instance then
        plugin = ReaderUI.instance.statistics
    end
    if not plugin then
        local ok_pl, PluginLoader = pcall(require, "pluginloader")
        if ok_pl then plugin = PluginLoader:getPluginInstance("statistics") end
    end
    if not plugin or type(plugin.insertDB) ~= "function" then return end

    -- Deliberately not gated on isEnabled(): that also demands an open
    -- document, which is never true on the home screen, so the gate turned this
    -- into a no-op exactly where it was needed. insertDB() already guards
    -- itself on there being a current book, so calling it is always safe.
    pcall(plugin.insertDB, plugin)
end

--- A cheap fingerprint of the database, for skipping needless re-queries.
-- Stamps the -wal sidecar too: in WAL mode (the default where the device
-- supports it) writes land there and leave the main file untouched.
function Stats.getStamp()
    local lfs = require("libs/libkoreader-lfs")
    local path = Stats.getDbPath()
    local parts = {}
    for _, p in ipairs({ path, path .. "-wal" }) do
        local attr = lfs.attributes(p)
        parts[#parts + 1] = attr
            and (tostring(attr.modification) .. ":" .. tostring(attr.size))
            or "-"
    end
    return table.concat(parts, "/")
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
-- @param no_flush skip the Stats.flush() call, for callers that just made one
function Stats.getDailyPages(since_ts, no_flush)
    local result = {}
    if not no_flush then Stats.flush() end

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
