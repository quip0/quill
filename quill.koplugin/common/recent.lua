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
                if info then
                    if info.title and info.title ~= "" then book.title = info.title end
                    book.authors = info.authors
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
