--[[
Shared post-HTML pipeline: the sanitizer that turns the site's raw td.postbody
HTML into safe XHTML-ish markup, and the XML escaper for metadata. Used by the
EPUB builder (dormant) and the in-app thread view (the live reading surface).
--]]

local htmltext = require("saforums.htmltext")

local posthtml = {}

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


posthtml.xml_escape = xml_escape
posthtml.sanitize_body = sanitize_body

return posthtml
