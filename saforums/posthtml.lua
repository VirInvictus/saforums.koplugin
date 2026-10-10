--[[
Shared post-HTML pipeline: the sanitizer that turns the site's raw td.postbody
HTML into safe XHTML-ish markup, and the XML escaper for metadata. Used by the
EPUB builder (dormant) and the in-app thread view (the live reading surface).

The sanitizer's output is the plugin's own intermediate format: images become
imgref spans carrying their source URL (the view's tap-to-view needs it),
embeddable media become embedref spans, smilies collapse to their typed codes,
and spoilers keep their marked span form (the EPUB path styles it).
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

local function attr_value(tag, name)
    return tag:match(name .. '%s*=%s*"(.-)"')
end

--- Plain text of an anchor's body: tags stripped, entities decoded.
local function anchor_text(body)
    return htmltext.trim(htmltext.decode_entities((body:gsub("<[^>]*>", ""))))
end

--- The site's media embeds are bare links the reference client recognizes by
--- shape (host and path facts mined from it). Each becomes a labeled
--- placeholder span; anything unrecognized keeps its anchor (and therefore
--- its text once tags are stripped).
local function classify_bare_link(href)
    local host, path = href:match("^https?://([^/]+)(/.*)$")
    if not host then return nil end
    host = host:lower()

    local status_id = path and path:match("/status%w*/(%d+)")
    if status_id and (host == "twitter.com" or host == "x.com"
        or host:match("%.twitter%.com$") or host:match("%.x%.com$")) then
        local user = path:match("^/([^/]+)/")
        return '[tweet: @' .. (user or "twitter") .. ']'
    end

    if host == "bsky.app" and path and path:find("/post/", 1, true) then
        return "[bluesky post]"
    end

    if href:find("youtu", 1, true) then
        return "[video: youtube]"
    end

    local file = href:match("([^/]+)$") or ""
    if file:lower():match("%.png$") or file:lower():match("%.jpe?g$")
        or file:lower():match("%.gif$") or file:lower():match("%.webp$")
        or file:lower():match("%.bmp$") then
        return "image"
    end

    return nil
end

--- Rewrite one anchor. Bare links to tweets, bluesky posts, videos, and
--- images become placeholders; a bare image link becomes a full imgref (the
--- view can fetch and show it), the rest become labeled embeds.
local function rewrite_anchor(anchor)
    local href = attr_value(anchor, "href") or ""
    local body = anchor:match("^<a[^>]*>(.*)</a>$") or ""
    local text = anchor_text(body)
    local decoded_href = htmltext.decode_entities(href)
    if text == "" or text ~= decoded_href then
        return anchor -- a labeled link: the text itself is the content
    end

    local kind = classify_bare_link(decoded_href)
    if kind == "image" then
        local label = decoded_href:match("([^/]+)$") or "image"
        return '<span class="imgref" src="' .. xml_escape(decoded_href) .. '">[linked image: '
            .. xml_escape(htmltext.decode_entities(label)) .. ']</span>'
    elseif kind then
        return '<span class="embedref">' .. xml_escape(kind) .. '</span>'
    end
    return anchor
end

--- Flash-era video embeds (div.bbcode_video wrapping an object) become a
--- labeled placeholder before the object strip would eat them.
local function rewrite_bbcode_video(div)
    local value = div:match('<param name="movie" value="(.-)"') or ""
    local label = value:find("vimeo", 1, true) and "[video: vimeo]" or "[video]"
    return '<span class="embedref">' .. label .. '</span>'
end

-- Smilie hosts and paths (the reference client's detection, as facts): the
-- site serves its emoticons from these trees; anything else is a real image.
local SMILIE_TREES = {
    ["fi.somethingawful.com"] = { "/smilies/", "/posticons/", "/customtitles/" },
    ["i.somethingawful.com"] = { "/emot/", "/emoticons/", "/images/", "/u/", "/adminuploads/", "/garbageday/" },
    ["forumimages.somethingawful.com"] = { "/images/", "/posticons/" },
}

local function is_smilie_src(src)
    local host, path = src:match("^https?://([^/]+)(/.*)$")
    local trees = host and SMILIE_TREES[host:lower()]
    if not trees or not path then return false end
    for _, tree in ipairs(trees) do
        if path:sub(1, #tree) == tree then return true end
    end
    return false
end

--- Rewrite one image tag. Smilies collapse to their typed code (the alt is
--- empty; the title carries ":code:"); real images become imgref spans that
--- keep the source URL for the view's tap-to-view.
local function replace_image(img_tag)
    local src = attr_value(img_tag, "src") or ""
    if is_smilie_src(src) then
        local code = attr_value(img_tag, "title")
        if code and code ~= "" then
            return htmltext.decode_entities(code)
        end
        return ""
    end
    local alt = attr_value(img_tag, "alt")
    local label = alt and alt ~= "" and alt
        or (src:match("([^/]+)$") or "image")
    return '<span class="imgref" src="' .. xml_escape(htmltext.decode_entities(src))
        .. '">[image: ' .. xml_escape(htmltext.decode_entities(label)) .. ']</span>'
end

local function sanitize_body(raw_html)
    local html = raw_html or ""

    -- Video embeds first: their object guts would vanish in the strip below.
    html = html:gsub('<div class="bbcode_video">.-</div>', rewrite_bbcode_video)

    -- Scripted and embedded content has no business on an e-reader.
    html = strip_blocks(html, "script")
    html = strip_blocks(html, "style")
    html = strip_blocks(html, "iframe")
    html = strip_blocks(html, "object")
    html = strip_blocks(html, "embed")
    html = html:gsub("<iframe[^>]*>", ""):gsub("<embed[^>]*>", "")

    -- Bare media links become placeholders (spec: Rendering).
    html = html:gsub("<a%s[^>]*>.-</a>", rewrite_anchor)

    -- Images become placeholders; smilies become their codes (spec: Rendering).
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
posthtml.is_smilie_src = is_smilie_src
posthtml.classify_bare_link = classify_bare_link

return posthtml
