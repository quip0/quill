--[[
Recently read books.

ReadHistory.hist is already ordered most-recent-first; we filter out entries
whose file no longer exists (history keeps deleted books) and enrich the rest
with title/author/cover/progress.
--]]

local Recent = {}

local function titleFromPath(path)
    local name = path:match("([^/]+)$") or path
    return (name:gsub("%.[^%.]+$", ""))
end

-- Embedded metadata is frequently junk. Two patterns show up often enough to
-- be worth correcting, and both are narrow enough to rarely misfire.
local DOC_EXTENSIONS = {
    pdf = true, epub = true, mobi = true, azw = true, azw3 = true,
    djvu = true, fb2 = true, txt = true, html = true, htm = true,
    cbz = true, cbr = true, doc = true, docx = true, rtf = true,
    jpg = true, jpeg = true, png = true, tif = true, tiff = true,
}

--- True when a "title" is really just a filename, e.g. "img-Z03140005.pdf".
-- Scanned PDFs routinely carry the scanner's output filename as their title.
local function looksLikeFilename(title)
    local ext = title:match("%.([%a%d]+)$")
    return ext ~= nil and DOC_EXTENSIONS[ext:lower()] == true
end

--- Collapse a title that is one phrase repeated twice, e.g.
-- "Shadow Divers Shadow Divers" -> "Shadow Divers". Restricted to multi-word
-- halves so genuine reduplications ("Boom Boom", "Sing Sing") survive.
local function collapseDoubled(title)
    local mid = (#title - 1) / 2
    if mid ~= math.floor(mid) or mid < 1 then return title end
    if title:sub(mid + 1, mid + 1) ~= " " then return title end
    local first, second = title:sub(1, mid), title:sub(mid + 2)
    if first ~= second or not first:find(" ") then return title end
    return first
end

-- Placeholder authors written by scanners and conversion tools. Showing these
-- is worse than showing nothing, since they read as a real credit.
local PLACEHOLDER_AUTHORS = {
    ["administrator"] = true, ["admin"] = true, ["user"] = true,
    ["unknown"] = true, ["unknown author"] = true, ["anonymous"] = true,
    ["calibre"] = true, ["default"] = true, ["owner"] = true,
}

local function cleanAuthors(authors)
    if type(authors) ~= "string" then return nil end
    local trimmed = authors:gsub("^%s+", ""):gsub("%s+$", "")
    if trimmed == "" then return nil end
    if PLACEHOLDER_AUTHORS[trimmed:lower()] then return nil end
    return trimmed
end

--- @param meta_title title from embedded metadata (may be nil or junk)
-- @param path the book's file path, used as the fallback
local function cleanTitle(meta_title, path)
    if type(meta_title) ~= "string" or meta_title:gsub("%s", "") == "" then
        return titleFromPath(path)
    end
    local title = meta_title:gsub("^%s+", ""):gsub("%s+$", "")
    if looksLikeFilename(title) then
        return titleFromPath(path)
    end
    return collapseDoubled(title)
end

--- Read progress as a 0..1 fraction, or nil if the book has no sidecar yet.
local function readProgress(path)
    local ok, DocSettings = pcall(require, "docsettings")
    if not ok or not DocSettings:hasSidecarFile(path) then return nil end
    local ok_open, doc = pcall(DocSettings.open, DocSettings, path)
    if not ok_open or not doc then return nil end
    -- Deliberately not closed: LuaSettings:close() flushes and rewrites the
    -- sidecar, which we have no reason to touch from a read-only view.
    return tonumber(doc:readSetting("percent_finished"))
end

--- @param limit how many books to return
-- @param cover_w,cover_h desired cover size in pixels (cover may come back smaller)
-- @return array of {path, title, authors, cover_bb, percent}, most recent first
function Recent.getBooks(limit, cover_w, cover_h)
    limit = limit or 3
    local books = {}

    local ok_rh, ReadHistory = pcall(require, "readhistory")
    if not ok_rh or not ReadHistory then return books end
    pcall(ReadHistory.reload, ReadHistory, false)

    local lfs = require("libs/libkoreader-lfs")
    local ok_bim, BookInfoManager = pcall(require, "bookinfomanager")

    for _, entry in ipairs(ReadHistory.hist or {}) do
        local path = entry and entry.file
        if type(path) == "string" and path ~= ""
                and lfs.attributes(path, "mode") == "file" then
            local book = {
                path = path,
                title = titleFromPath(path),
                authors = nil,
                cover_bb = nil,
                percent = readProgress(path),
            }

            if ok_bim then
                local info = BookInfoManager:getBookInfo(path, true)
                -- Nothing cached yet (fresh install, or CoverBrowser has never
                -- scanned this folder). Extract inline: we only ever do this for
                -- a handful of books, and only once -- the result is cached.
                if not info or (not info.cover_fetched and not info.ignore_cover) then
                    pcall(BookInfoManager.extractBookInfo, BookInfoManager, path, {
                        max_cover_w = cover_w or 200,
                        max_cover_h = cover_h or 300,
                    })
                    info = BookInfoManager:getBookInfo(path, true)
                end
                if info then
                    book.title = cleanTitle(info.title, path)
                    book.authors = cleanAuthors(info.authors)
                    -- cover_bb is owned by BookInfoManager's cache, so copy it:
                    -- the widget outlives the cache entry.
                    if info.cover_bb and info.has_cover and info.cover_fetched
                            and not info.ignore_cover then
                        local ok_copy, bb = pcall(info.cover_bb.copy, info.cover_bb)
                        if ok_copy then
                            book.cover_bb = bb
                            book.cover_w = info.cover_w
                            book.cover_h = info.cover_h
                        end
                    end
                end
            end

            books[#books + 1] = book
            if #books >= limit then break end
        end
    end

    return books
end

return Recent
