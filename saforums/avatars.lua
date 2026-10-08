--[[
Avatar cache.

One fetch per poster, ever: avatars land in <data dir>/saforums/avatars/
keyed by user id, are reused across every thread, and never expire (the
site's avatars are effectively permanent; a stale avatar is a cosmetic
wrong, a re-fetch storm is a politeness wrong). Bytes are stored raw:
this is the one part of the plugin that must not touch the Windows-1252
text decoder.

A failed or missing avatar is cosmetic: the post renders without one.
--]]

local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")

local avatars = {}

local MIME_BY_EXT = {
    gif = "image/gif",
    png = "image/png",
    jpg = "image/jpeg",
    jpeg = "image/jpeg",
    webp = "image/webp",
}

function avatars.mime_for(src)
    local path = src:match("^([^?#]*)")
    local ext = path:match("%.(%w+)$") or "png"
    ext = ext:lower()
    return MIME_BY_EXT[ext] or "image/png", ext
end

--- Returns the local cache path for a user id, fetching and storing on a
--- cache miss. nil when there is nothing usable (no source, fetch failed).
function avatars.ensure(cache_dir, session, userid, src)
    if not userid or not src then return nil end
    if not cache_dir then return nil end

    if not lfs.attributes(cache_dir, "mode") then
        local created = lfs.mkdir(cache_dir)
        if not created then
            logger.warn("saforums: avatar cache dir unusable:", cache_dir)
            return nil
        end
    end

    local _, ext = avatars.mime_for(src)
    local cached_path = cache_dir .. "/" .. userid .. "." .. ext
    if lfs.attributes(cached_path, "mode") then
        return cached_path
    end

    local result = session:get(src, { raw = true })
    if result.kind ~= "ok" or not result.body or #result.body == 0 then
        logger.warn("saforums: avatar fetch failed for user", userid, "from", src,
            "->", result.kind)
        return nil
    end

    local file = io.open(cached_path, "wb")
    if not file then
        logger.warn("saforums: cannot write avatar cache:", cached_path)
        return nil
    end
    file:write(result.body)
    file:close()
    return cached_path
end

return avatars
