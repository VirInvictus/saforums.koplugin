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
local cp1252 = require("saforums.cp1252")
local htmltext = require("saforums.htmltext")

local epubbuilder = {}

local MIMETYPE = "application/epub+zip"

local CONTAINER = [[<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>]]

local STYLESHEET = [[
body { font-family: serif; }
div.post { margin: 0 0 1.2em 0; }
div.posthead { font-size: 0.8em; color: #666; border-bottom: 1px solid #999; margin-bottom: 0.4em; }
span.postauthor { font-weight: bold; }
span.spoiler { color: #777; font-style: italic; }
span.imgref { color: #666; font-size: 0.85em; }
blockquote { margin: 0.5em 0 0.5em 1.5em; color: #444; }
]]

-- Entities the source HTML uses that strict XML will not accept by name.
local entity_to_numeric = {
    nbsp = "&#160;", hellip = "&#8230;", mdash = "&#8212;", ndash = "&#8211;",
    ldquo = "&#8220;", rdquo = "&#8221;", lsquo = "&#8216;", rsquo = "&#8217;",
    laquo = "&#171;", raquo = "&#187;", copy = "&#169;", reg = "&#174;",
    trade = "&#8482;", eacute = "&#233;", egrave = "&#232;", agrave = "&#224;",
    ccedil = "&#231;", ouml = "&#246;", uuml = "&#252;", auml = "&#228;",
    szlig = "&#223;",
}

local function xml_escape(s)
    return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
        :gsub('"', "&quot;"):gsub("'", "&apos;"))
end

-- Everything between an opening and closing tag of these, gone. Lua's `.-`
-- matches across newlines, which is what multi-line blocks need.
local function strip_blocks(html, tag)
    html = html:gsub("<" .. tag .. "[^>]*>.-</" .. tag .. ">", "")
    html = html:gsub("<" .. tag .. "[^>]*/>", "")
    return html
end

--- Rewrite one image tag into a bracketed placeholder span.
local function replace_image(img_tag)
    local alt = img_tag:match('alt%s*=%s*"(.-)"')
    local src = img_tag:match('src%s*=%s*"(.-)"')
    local label = alt and alt ~= "" and alt
        or (src and src:match("([^/]+)$") or "image")
    return '<span class="imgref">[image: ' .. xml_escape(htmltext.decode_entities(label)) .. ']</span>'
end

local function sanitize_body(raw_html)
    local html = raw_html or ""

    -- Scripted and embedded content has no business on an e-reader.
    html = strip_blocks(html, "script")
    html = strip_blocks(html, "style")
    html = strip_blocks(html, "iframe")
    html = strip_blocks(html, "object")
    html = strip_blocks(html, "embed")
    html = html:gsub("<iframe[^>]*>", ""):gsub("<embed[^>]*>", "")

    -- Images become placeholders (spec: Rendering).
    html = html:gsub("<img[^>]*>", replace_image)

    -- Spoiler spans keep their text, clearly marked and de-emphasized.
    html = html:gsub('<span class="bbc%-spoiler"[^>]*>(.-)</span>',
        '<span class="spoiler">[spoiler] %1 [/spoiler]</span>')

    -- Close the void tags XHTML expects closed.
    html = html:gsub("<br>", "<br/>"):gsub("<br%s*/%s*>", "<br/>")
    html = html:gsub("<hr>", "<hr/>"):gsub("<hr%s*/%s*>", "<hr/>")

    -- Escape every ampersand first, then recognize the entity forms that
    -- just got escaped: named ones go numeric, already-numeric ones come
    -- back as themselves. What remains escaped is exactly the bare &.
    html = html:gsub("&", "&amp;")
    html = html:gsub("&amp;(%a+);", entity_to_numeric)
    html = html:gsub("&amp;#x(%x+);", "&#x%1;")
    html = html:gsub("&amp;#(%d+);", "&#%1;")

    return html
end

local function chapter_xhtml(title, posts)
    local parts = {}
    parts[#parts + 1] = [[<?xml version="1.0" encoding="utf-8"?>]]
    parts[#parts + 1] = [[<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">]]
    parts[#parts + 1] = '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>'
        .. xml_escape(title) .. '</title></head><body>'
    for _, post in ipairs(posts) do
        parts[#parts + 1] = '<div class="post">'
        parts[#parts + 1] = '<div class="posthead"><span class="postauthor">'
            .. xml_escape(post.author_name or "?") .. '</span>'
            .. (post.date_raw and " &#183; " .. xml_escape(post.date_raw) or "")
            .. '</div>'
        parts[#parts + 1] = sanitize_body(post.body_html)
        parts[#parts + 1] = '</div>'
    end
    parts[#parts + 1] = '</body></html>'
    return table.concat(parts, "\n")
end

local function content_opf(doc, page_count)
    local manifest, spine = {}, {}
    for i = 1, page_count do
        manifest[#manifest + 1] = string.format(
            '    <item id="page%d" href="page%d.xhtml" media-type="application/xhtml+xml"/>', i, i)
        spine[#spine + 1] = string.format('    <itemref idref="page%d"/>', i)
    end
    return table.concat({
        "<?xml version='1.0' encoding='utf-8'?>",
        '<package xmlns="http://www.idpf.org/2007/opf"',
        '        xmlns:dc="http://purl.org/dc/elements/1.1/"',
        '        unique-identifier="bookid" version="2.0">',
        "  <metadata>",
        "    <dc:title>" .. xml_escape(doc.title) .. "</dc:title>",
        "    <dc:identifier id=\"bookid\">saforums-thread-" .. xml_escape(doc.thread_id) .. "</dc:identifier>",
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
            i, i, xml_escape("Page " .. i), i)
    end
    return table.concat({
        "<?xml version='1.0' encoding='utf-8'?>",
        '<!DOCTYPE ncx PUBLIC "-//NISO//DTD ncx 2005-1//EN" "http://www.daisy.org/z3986/2005/ncx-2005-1.dtd">',
        '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">',
        "  <head>",
        '    <meta name="dtb:uid" content="saforums-thread-' .. xml_escape(doc.thread_id) .. '"/>',
        '    <meta name="dtb:depth" content="1"/>',
        string.format('    <meta name="dtb:totalPageCount" content="%d"/>', page_count),
        "  </head>",
        "  <docTitle><text>" .. xml_escape(doc.title) .. "</text></docTitle>",
        "  <navMap>",
        table.concat(points, "\n"),
        "  </navMap>",
        "</ncx>",
    }, "\n")
end

--- Build the EPUB at `path`. `doc` = { thread_id, title, pages } where each
--- page is { number, posts }. Writes to a .tmp file and renames only on
--- success, so an interrupted build never clobbers the readable file.
function epubbuilder.build(path, doc)
    local pages = doc.pages or {}
    if #pages == 0 then
        return false
    end

    local epub = Archiver.Writer:new{}
    local tmp_path = path .. ".tmp"
    if not epub:open(tmp_path, "epub") then
        logger.err("saforums: failed to open", tmp_path)
        return false
    end

    epub:setZipCompression("store")
    epub:addFileFromMemory("mimetype", MIMETYPE)
    epub:setZipCompression("deflate")

    epub:addFileFromMemory("META-INF/container.xml", CONTAINER)
    epub:addFileFromMemory("OEBPS/stylesheet.css", STYLESHEET)
    epub:addFileFromMemory("OEBPS/content.opf", content_opf(doc, #pages))
    epub:addFileFromMemory("OEBPS/toc.ncx", toc_ncx(doc, #pages))

    for _, page in ipairs(pages) do
        epub:addFileFromMemory(
            string.format("OEBPS/page%d.xhtml", page.number),
            chapter_xhtml(doc.title, page.posts))
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

epubbuilder.sanitize_body = sanitize_body
epubbuilder.xml_escape = xml_escape

return epubbuilder
