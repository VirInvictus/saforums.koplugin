--[[
Pure renderer: parsed posts to an HTML fragment for the in-app thread
view (mupdf's HTML engine via ScrollHtmlWidget). No I/O, no KOReader
modules; the device widget and the tests share this file.

The design is a grayscale port of Awful.app's posts-view theme (the
reference clone's AwfulTheming/Stylesheets/posts-view.less + _base.less):
white post cards with hairline top/bottom borders on a bare page, seen
posts tinted light gray (white = new since you last read), avatar beside
an inline name-and-date block, username 1.1em, metadata 0.8em in muted
ink, blockquotes with muted headers, and a 3em end-of-thread marker.
Sizes in em, everything else per spec (Typography).
--]]

local posthtml = require("saforums.posthtml")

local threadhtml = {}

local xml_escape = posthtml.xml_escape
local sanitize_body = posthtml.sanitize_body

-- Grayscale translation of the York-Street-style light theme:
-- #ddd card borders, #e6eff8 seen tint -> #e8e8e8, rgba(0,0,0,.3) metadata
-- -> #999, quote headers #555, links #333.
local CSS = [[
body { margin: 0; font-family: sans-serif; }
p { text-indent: 0; margin: 0 0 0.5em 0; }
div.post { display: block; border-top: 1px solid #ccc; border-bottom: 1px solid #ccc;
           margin-top: 0.5em; padding: 0 0.6em; background-color: #ffffff; }
div.post.first { margin-top: 0; }
div.post.seen { background-color: #e8e8e8; }
header { padding-top: 0.75em; padding-bottom: 0.7em; }
img.avatar { display: inline-block; vertical-align: middle; width: 2.5em;
             margin-right: 0.6em; }
div.nameanddate { display: inline-block; vertical-align: middle; }
div.username { font-size: 1.1em; font-weight: bold; margin: 0 0 2px; }
span.opbadge { font-size: 0.65em; border: 1px solid #555; color: #555;
               padding: 0 0.25em; margin-left: 0.4em; }
span.usertitle { display: block; font-size: 0.8em; font-style: italic; color: #555; }
div.postdate { font-size: 0.8em; color: #999; }
div.regdate { font-size: 0.8em; color: #999; }
div.postbody { text-align: left; }
div.postbody img { max-width: 100%; }
p.editedby, div.editedby { font-size: 0.8em; color: #999; text-indent: 0; }
blockquote { border-left: 2px solid #ccc; margin: 0.5em 0 0.5em 1em;
             padding-left: 0.7em; color: #333; }
blockquote h4 { font-size: 0.8em; color: #555; margin: 0 0 0.2em 0; }
span.spoiler { color: #555; font-style: italic; }
span.imgref { color: #999; font-size: 0.85em; }
hr { border-style: solid; color: #ccc; }
a { color: #333; }
div.endmarker { text-align: center; line-height: 3em; color: #999; }
]]

-- The end-of-thread line (spec: Voice and humor). Lore-accurate, deadpan,
-- and never explained.
local END_MARKER = "The frog says: GET OUT."

local function avatar_src(avatars, userid)
    local av = avatars and avatars[userid]
    if not av then return nil end
    return av
end

--- Render posts to an HTML fragment (ScrollHtmlWidget wraps it into the
--- document itself; the webbrowser viewer feeds it exactly this shape).
--- `doc` = { title, posts, avatars } where avatars maps user id to a
--- path relative to the resource directory.
function threadhtml.render(doc)
    local parts = {}
    parts[#parts + 1] = '<div class="thread">'
    for i, post in ipairs(doc.posts or {}) do
        local classes = { "post" }
        if i == 1 then classes[#classes + 1] = "first" end
        if post.seen then classes[#classes + 1] = "seen" end
        parts[#parts + 1] = '<div class="' .. table.concat(classes, " ") .. '">'

        -- Awful's header: avatar beside an inline name-and-date block.
        parts[#parts + 1] = "<header>"
        local src = avatar_src(doc.avatars, post.author_id)
        if src then
            parts[#parts + 1] = '<img class="avatar" src="' .. xml_escape(src) .. '" alt=""/>'
        end
        parts[#parts + 1] = '<div class="nameanddate">'
        parts[#parts + 1] = '<div class="username">'
            .. xml_escape(post.author_name or "?")
        if post.author_is_op then
            parts[#parts + 1] = '<span class="opbadge">OP</span>'
        end
        parts[#parts + 1] = "</div>"
        if post.custom_title and post.custom_title ~= "" then
            parts[#parts + 1] = '<span class="usertitle">'
                .. xml_escape(post.custom_title) .. "</span>"
        end
        if post.date_raw and post.date_raw ~= "" then
            parts[#parts + 1] = '<div class="postdate">' .. xml_escape(post.date_raw)
            if post.index then
                parts[#parts + 1] = " &#183; post #" .. post.index
            end
            parts[#parts + 1] = "</div>"
        end
        if post.regdate and post.regdate ~= "" then
            parts[#parts + 1] = '<div class="regdate">joined ' .. xml_escape(post.regdate) .. "</div>"
        end
        parts[#parts + 1] = "</div>"
        parts[#parts + 1] = "</header>"

        parts[#parts + 1] = '<div class="postbody">'
        parts[#parts + 1] = sanitize_body(post.body_html)
        parts[#parts + 1] = "</div>"
        parts[#parts + 1] = "</div>"
    end
    -- The #end marker: Awful reserves a 3em line after the last post; ours
    -- carries the frog (spec: Voice and humor).
    parts[#parts + 1] = '<div class="endmarker">' .. END_MARKER .. "</div>"
    parts[#parts + 1] = "</div>"
    return table.concat(parts, "\n")
end

threadhtml.css = CSS

return threadhtml
