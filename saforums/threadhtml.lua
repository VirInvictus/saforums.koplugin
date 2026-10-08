--[[
Pure renderer: parsed posts to a single HTML document for the in-app
thread view (mupdf's HTML engine via ScrollHtmlWidget). No I/O, no
KOReader modules; the device widget and the tests share this file.

mupdf's CSS engine is broader than crengine's for what we need (borders,
inline images, floats) but still a subset: no text-shadow, no flex, no
CSS variables. Sizes in em, gray inks, hierarchy by weight and case, per
spec (Typography).
--]]

local posthtml = require("saforums.posthtml")

local threadhtml = {}

local xml_escape = posthtml.xml_escape
local sanitize_body = posthtml.sanitize_body

local CSS = [[
body { font-family: serif; margin: 0; }
p { text-indent: 0; margin: 0 0 0.5em 0; }
div.post { border-top: 1px solid #888; margin-top: 1.4em; padding-top: 0.9em; }
div.post.first { border-top: none; margin-top: 0; padding-top: 0; }
div.posthead { margin-bottom: 0.7em; }
img.avatar { width: 3em; vertical-align: middle; margin-right: 0.7em; }
span.postauthor { font-weight: bold; }
span.usertitle { font-style: italic; color: #333; }
div.postmeta { font-size: 0.75em; color: #555; margin-top: 0.2em; }
p.editedby, div.editedby { font-size: 0.75em; color: #555; text-indent: 0; }
blockquote { border-left: 2px solid #888; margin: 0.6em 0 0.6em 1em;
             padding-left: 0.8em; color: #333; }
span.spoiler { color: #555; font-style: italic; }
span.imgref { color: #555; font-size: 0.85em; }
hr { border-style: solid; color: #888; }
a { color: #333; }
]]

-- RFC 4648 base64, small and allocation-happy enough for avatar-sized blobs.
local B64 = {}
for i = 0, 63 do
    local c = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    B64[i] = c:sub(i + 1, i + 1)
end

function threadhtml.base64(data)
    local out = {}
    for i = 1, #data, 3 do
        local a, b, c = data:byte(i, i + 2)
        local n = a * 0x10000 + (b or 0) * 0x100 + (c or 0)
        out[#out + 1] = B64[math.floor(n / 0x40000)]
        out[#out + 1] = B64[math.floor(n / 0x1000) % 0x40]
        out[#out + 1] = b and B64[math.floor(n / 0x40) % 0x40] or "="
        out[#out + 1] = c and B64[n % 0x40] or "="
    end
    return table.concat(out)
end

local function avatar_data_uri(avatars, userid)
    local av = avatars and avatars[userid]
    if not av then return nil end
    return "data:" .. av.mime .. ";base64," .. threadhtml.base64(av.data)
end

--- Render posts to a full HTML document. `doc` = { title, posts,
--- avatars } where avatars maps user id to { data, mime }.
function threadhtml.render(doc)
    local parts = {}
    parts[#parts + 1] = [[<!DOCTYPE html>]]
    parts[#parts + 1] = "<html><head><meta charset='utf-8'><title>"
        .. xml_escape(doc.title) .. "</title></head><body>"
    for i, post in ipairs(doc.posts or {}) do
        local first = i == 1 and " first" or ""
        parts[#parts + 1] = '<div class="post' .. first .. '">'
        parts[#parts + 1] = '<div class="posthead">'
        local uri = avatar_data_uri(doc.avatars, post.author_id)
        if uri then
            parts[#parts + 1] = '<img class="avatar" src="' .. uri .. '" alt=""/>'
        end
        parts[#parts + 1] = '<span class="postauthor">'
            .. xml_escape(post.author_name or "?") .. '</span>'
        if post.custom_title and post.custom_title ~= "" then
            parts[#parts + 1] = ' <span class="usertitle">'
                .. xml_escape(post.custom_title) .. '</span>'
        end
        local meta = {}
        if post.date_raw and post.date_raw ~= "" then
            meta[#meta + 1] = xml_escape(post.date_raw)
        end
        if post.index then
            meta[#meta + 1] = "post #" .. post.index
        end
        if #meta > 0 then
            parts[#parts + 1] = '<div class="postmeta">' .. table.concat(meta, " &#183; ") .. '</div>'
        end
        parts[#parts + 1] = "</div>"
        parts[#parts + 1] = sanitize_body(post.body_html)
        parts[#parts + 1] = "</div>"
    end
    parts[#parts + 1] = "</body></html>"
    return table.concat(parts, "\n")
end

threadhtml.css = CSS

return threadhtml
