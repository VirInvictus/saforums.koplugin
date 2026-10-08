--[[
Builds the per-thread EPUB.

One EPUB per thread, one chapter per fetched site page (spec: Rendering).
The container layout follows the shape KOReader's own NewsDownloader ships
against crengine: mimetype stored first, META-INF/container.xml, an EPUB 2.0
content.opf, toc.ncx, and one XHTML file per chapter. Zip packaging goes
through KOReader's ffi/archiver; tests run it against the recording fake in
spec/stubs.lua.

Post bodies arrive as the site's raw inner HTML. The sanitizer keeps text,
links, and basic formatting, turns images and embeds into bracketed
placeholders (spec: no images in v1), and patches the common HTML sloppiness
that would break strict XHTML.
--]]

local Archiver = require("ffi/archiver")
local logger = require("logger")
local posthtml = require("saforums.posthtml")

local epubbuilder = {}

local MIMETYPE = "application/epub+zip"

local CONTAINER = [[<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>]]

local STYLESHEET = [[
/* saforums thread book. Art-directed, deferential: em/% units only, no
   font-family, no line-height, gray inks, hierarchy by size/weight/case.
   Rules the user can always beat with a style tweak (spec: Typography). */
body { margin: 0; }

p { text-indent: 0; margin: 0 0 0.5em 0; text-align: left; }
div.postbody { text-align: left; }

div.post { border-top: 1px solid #888; margin-top: 1.4em; padding-top: 0.9em; }
div.post:first-child { border-top: none; margin-top: 0; padding-top: 0; }

div.posthead { margin-bottom: 0.7em; }
img.avatar { width: 3em; vertical-align: middle; margin-right: 0.7em; }
span.postauthor { font-weight: bold; }
span.usertitle { font-style: italic; }
div.postmeta { font-size: 0.8em; color: #555; margin-top: 0.2em; }

p.editedby, div.editedby { font-size: 0.8em; color: #555; text-indent: 0; }

blockquote { border-left: 2px solid #888; margin: 0.6em 0 0.6em 1em;
             padding-left: 0.8em; color: #333; }
span.spoiler { color: #555; font-style: italic; }
span.imgref { color: #555; font-size: 0.85em; }
hr { border-style: solid; color: #888; }
]]

-- Avatar zip paths are derived from the user id: images/a<id>.<ext>.
local AVATAR_MIME = {
    gif = "image/gif", png = "image/png", jpg = "image/jpeg",
    jpeg = "image/jpeg", webp = "image/webp",
}

local function avatar_zip_name(userid, local_path)
    local ext = (local_path:match("%.(%w+)$") or "png"):lower()
    return "images/a" .. userid .. "." .. ext, AVATAR_MIME[ext] or "image/png"
end

local function chapter_xhtml(title, posts, avatars)
    local parts = {}
    parts[#parts + 1] = [[<?xml version="1.0" encoding="utf-8"?>]]
    parts[#parts + 1] = [[<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">]]
    parts[#parts + 1] = '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>'
        .. posthtml.xml_escape(title) .. '</title></head><body>'
    for _, post in ipairs(posts) do
        parts[#parts + 1] = '<div class="post">'
        parts[#parts + 1] = '<div class="posthead">'
        local avatar = post.author_id and avatars and avatars[post.author_id]
        if avatar then
            local zip_path = avatar_zip_name(post.author_id, avatar)
            parts[#parts + 1] = '<img class="avatar" src="' .. zip_path .. '" alt=""/>'
        end
        parts[#parts + 1] = '<span class="postauthor">'
            .. posthtml.xml_escape(post.author_name or "?") .. '</span>'
        if post.custom_title and post.custom_title ~= "" then
            parts[#parts + 1] = ' <span class="usertitle">'
                .. posthtml.xml_escape(post.custom_title) .. '</span>'
        end
        local meta = {}
        if post.date_raw and post.date_raw ~= "" then
            meta[#meta + 1] = posthtml.xml_escape(post.date_raw)
        end
        if post.index then
            meta[#meta + 1] = "post #" .. post.index
        end
        if #meta > 0 then
            parts[#parts + 1] = '<div class="postmeta">' .. table.concat(meta, " &#183; ") .. '</div>'
        end
        parts[#parts + 1] = '</div>'
        parts[#parts + 1] = posthtml.sanitize_body(post.body_html)
        parts[#parts + 1] = '</div>'
    end
    parts[#parts + 1] = '</body></html>'
    return table.concat(parts, "\n")
end

local function content_opf(doc, page_count, avatar_zip_names)
    local manifest, spine = {}, {}
    for i = 1, page_count do
        manifest[#manifest + 1] = string.format(
            '    <item id="page%d" href="page%d.xhtml" media-type="application/xhtml+xml"/>', i, i)
        spine[#spine + 1] = string.format('    <itemref idref="page%d"/>', i)
    end
    for _, av in ipairs(avatar_zip_names) do
        manifest[#manifest + 1] = string.format(
            '    <item id="%s" href="%s" media-type="%s"/>',
            "av" .. av.userid, av.zip_path, av.mime)
    end
    return table.concat({
        "<?xml version='1.0' encoding='utf-8'?>",
        '<package xmlns="http://www.idpf.org/2007/opf"',
        '        xmlns:dc="http://purl.org/dc/elements/1.1/"',
        '        unique-identifier="bookid" version="2.0">',
        "  <metadata>",
        "    <dc:title>" .. posthtml.xml_escape(doc.title) .. "</dc:title>",
        "    <dc:identifier id=\"bookid\">saforums-thread-" .. posthtml.xml_escape(doc.thread_id) .. "</dc:identifier>",
        "    <dc:publisher>saforums.koplugin</dc:publisher>",
        "  </metadata>",
        "  <manifest>",
        '    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>',
        '    <item id="css" href="stylesheet.css" media-type="text/css"/>',
        table.concat(manifest, "\n"),
        "  </manifest>",
        '  <spine toc="ncx">',
        table.concat(spine, "\n"),
        "  </spine>",
        "</package>",
    }, "\n")
end

local function toc_ncx(doc, page_count)
    local points = {}
    for i = 1, page_count do
        points[#points + 1] = string.format(
            '<navPoint id="navpoint-%d" playOrder="%d"><navLabel><text>%s</text></navLabel>'
                .. '<content src="page%d.xhtml"/></navPoint>',
            i, i, posthtml.xml_escape("Page " .. i), i)
    end
    return table.concat({
        "<?xml version='1.0' encoding='utf-8'?>",
        '<!DOCTYPE ncx PUBLIC "-//NISO//DTD ncx 2005-1//EN" "http://www.daisy.org/z3986/2005/ncx-2005-1.dtd">',
        '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">',
        "  <head>",
        '    <meta name="dtb:uid" content="saforums-thread-' .. posthtml.xml_escape(doc.thread_id) .. '"/>',
        '    <meta name="dtb:depth" content="1"/>',
        string.format('    <meta name="dtb:totalPageCount" content="%d"/>', page_count),
        "  </head>",
        "  <docTitle><text>" .. posthtml.xml_escape(doc.title) .. "</text></docTitle>",
        "  <navMap>",
        table.concat(points, "\n"),
        "  </navMap>",
        "</ncx>",
    }, "\n")
end

--- Build the EPUB at `path`. `doc` = { thread_id, title, pages, avatars }
--- where each page is { number, posts } and avatars maps user id to a
--- local cache file path (they are fetched by the caller before build).
--- Writes to a .tmp file and renames only on success, so an interrupted
--- build never clobbers the readable file.
function epubbuilder.build(path, doc)
    local pages = doc.pages or {}
    if #pages == 0 then
        return false
    end

    -- Avatar files: read once, embedded into OEBPS/images/, manifest items
    -- generated per unique user id.
    local avatar_zip_names, avatar_contents = {}, {}
    for userid, local_path in pairs(doc.avatars or {}) do
        local file = io.open(local_path, "rb")
        if file then
            local content = file:read("*a")
            file:close()
            if content and #content > 0 then
                local zip_path, mime = avatar_zip_name(userid, local_path)
                avatar_zip_names[#avatar_zip_names + 1] = {
                    userid = userid, zip_path = zip_path, mime = mime,
                }
                avatar_contents[zip_path] = content
            end
        end
    end

    local epub = Archiver.Writer:new{}
    local tmp_path = path .. ".tmp"
    if not epub:open(tmp_path, "epub") then
        logger.err("saforums: failed to open", tmp_path, ":", epub.err)
        return false
    end

    epub:setZipCompression("store")
    epub:addFileFromMemory("mimetype", MIMETYPE)
    epub:setZipCompression("deflate")

    epub:addFileFromMemory("META-INF/container.xml", CONTAINER)
    epub:addFileFromMemory("OEBPS/stylesheet.css", STYLESHEET)
    epub:addFileFromMemory("OEBPS/content.opf", content_opf(doc, #pages, avatar_zip_names))
    epub:addFileFromMemory("OEBPS/toc.ncx", toc_ncx(doc, #pages))

    for _, page in ipairs(pages) do
        epub:addFileFromMemory(
            string.format("OEBPS/page%d.xhtml", page.number),
            chapter_xhtml(doc.title, page.posts, doc.avatars))
    end
    for _, av in ipairs(avatar_zip_names) do
        epub:addFileFromMemory("OEBPS/" .. av.zip_path, avatar_contents[av.zip_path])
    end

    -- KOReader's Writer:close returns nothing; errors surface through the
    -- err field set along the way (the first device pass threw away two
    -- good EPUBs by branching on the return value).
    epub:close()
    if epub.err then
        logger.err("saforums: archiver error on", tmp_path, ":", epub.err)
        return false
    end

    os.rename(tmp_path, path)
    return true
end

epubbuilder.sanitize_body = posthtml.sanitize_body
epubbuilder.xml_escape = posthtml.xml_escape

return epubbuilder
