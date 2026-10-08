--[[
Retention: the thread-book shelf self-cleans.

Thread EPUBs are small and accumulate quietly; the LRU cap bounds the
shelf. Oldest books (by file mtime) are deleted beyond the cap, each with
its reading-position sidecar and history/collection entries, the same
three-way cleanup KOReader's own file manager performs. Everything is
pcall-guarded and failure-tolerant: a retention miss must never take down
startup (spec: Rendering; policy decided 2026-10-08, cap default 100).
--]]

local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

local retention = {}

local function sidecar_cleanup(path)
    local ok, DocSettings = pcall(require, "docsettings")
    if ok then
        pcall(function()
            DocSettings:open(path):purge()
        end)
    end
    pcall(function()
        require("readhistory"):removeItemByPath(path)
    end)
    pcall(function()
        require("readcollection"):removeItem(path)
    end)
end

local function epub_files(books_dir)
    local files = {}
    for entry in lfs.dir(books_dir) do
        local path = books_dir .. "/" .. entry
        if entry:match("%.epub$") and lfs.attributes(path, "mode") == "file" then
            files[#files + 1] = {
                path = path,
                mtime = lfs.attributes(path, "modification") or 0,
            }
        end
    end
    table.sort(files, function(a, b) return a.mtime < b.mtime end)
    return files
end

--- Delete oldest thread books beyond cap. Returns the number deleted.
function retention.enforce(books_dir, cap)
    if not books_dir or not cap or cap <= 0 then return 0 end
    if not lfs.attributes(books_dir, "mode") then return 0 end

    local files = epub_files(books_dir)
    local doomed_count = #files - cap
    if doomed_count <= 0 then return 0 end

    local deleted = 0
    for i = 1, doomed_count do
        local path = files[i].path
        local removed = os.remove(path)
        if removed ~= nil then
            deleted = deleted + 1
            sidecar_cleanup(path)
        else
            logger.warn("saforums: retention could not remove", path)
        end
    end
    if deleted > 0 then
        logger.info("saforums: retention removed", deleted, "old thread books")
    end
    return deleted
end

return retention
