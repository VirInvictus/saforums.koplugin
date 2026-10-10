--[[
Pure block model: turns the sanitized post-body HTML (the posthtml
sanitizer's output) into a list of layout blocks for the native widget
renderer.

    { type = "para",    text = "..." }              -- text carries PTF bold markers
    { type = "quote",   header = "...", text = "...", mentions_you = true }
    { type = "spoiler", text = "..." }
    { type = "image",   label = "[image: x.png]", src = "https://..." }
    { type = "embed",   label = "[tweet: @user]" }  -- inert media placeholder

parse(body_html, opts) takes opts.username (the logged-in user): bare
occurrences of it in text get bold markers, and quote headers citing it set
mentions_you. A string scanner rather than a DOM walk: htmlparser's tree is
elements-only, so inter-element text (most of any post) would be lost.
Blockquotes nest on the site; nested levels flatten into the enclosing
quote's text (v1 limitation, like inline italics rendering plain).
--]]

local htmltext = require("saforums.htmltext")
local cp1252 = require("saforums.cp1252")

local postblocks = {}

-- TextBoxWidget's inline bold markers (private-use codepoints, see
-- textboxwidget.lua PTF_*).
local BOLD_START = cp1252.utf8_encode(0xFFF2)
local BOLD_END = cp1252.utf8_encode(0xFFF3)
local PTF_HEADER = cp1252.utf8_encode(0xFFF1)

postblocks.BOLD_START = BOLD_START
postblocks.BOLD_END = BOLD_END
postblocks.PTF_HEADER = PTF_HEADER

-- A collapsed long quote shows this many of its lines (the reference
-- client's QUOTE_COLLAPSED_LINES).
postblocks.QUOTE_COLLAPSED_LINES = 3

local function collapse(text)
    return htmltext.trim((text:gsub("%s+", " ")))
end

--- Bold-marker every bare occurrence of username in text. Boundaries follow
--- the reference client's rule: the match must not sit next to a word
--- character (ASCII word characters; the site's usernames are cp1252-era
--- ASCII). Case-insensitive via ASCII lowercasing, which preserves byte
--- offsets.
local function highlight_mentions(text, username)
    if not username or username == "" or text == "" then return text end
    local lower = text:lower()
    local pattern = username:lower():gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
    local out = {}
    local pos = 1
    while true do
        local start_pos, end_pos = lower:find(pattern, pos)
        if not start_pos then
            out[#out + 1] = text:sub(pos)
            break
        end
        local before = start_pos > 1 and lower:sub(start_pos - 1, start_pos - 1) or ""
        local after = lower:sub(end_pos + 1, end_pos + 1)
        local bounded = not before:match("[%w_]") and not after:match("[%w_]")
        if bounded then
            out[#out + 1] = text:sub(pos, start_pos - 1)
            out[#out + 1] = BOLD_START .. text:sub(start_pos, end_pos) .. BOLD_END
        else
            out[#out + 1] = text:sub(pos, end_pos)
        end
        pos = end_pos + 1
    end
    return table.concat(out)
end

--- Inline HTML to PTF-marked plain text: <b>/<strong> runs wrapped in
--- TextBoxWidget's bold markers, every other tag stripped, entities
--- decoded, whitespace collapsed. opts.username gets mention markers.
local function make_inline_from_html(opts)
    return function(html)
        html = html:gsub("<b>(.-)</b>", BOLD_START .. "%1" .. BOLD_END)
        html = html:gsub("<strong>(.-)</strong>", BOLD_START .. "%1" .. BOLD_END)
        html = html:gsub("<span class=\"spoiler\">%[spoiler%] (.-) %[/spoiler%]", "[spoiler] %1 [/spoiler]")
        html = html:gsub("<[^>]*>", "")
        local text = collapse(htmltext.decode_entities(html))
        if opts and opts.username then
            text = highlight_mentions(text, opts.username)
        end
        return text
    end
end

--- The site quotes blockquotes with a bare tag; some pages carry classes.
--- Find the next open tag and the end of its open form (the `>`).
local function find_quote_open(html, position)
    local at = html:find("<blockquote", position, true)
    if not at then return nil end
    local after = html:sub(at + #"<blockquote", at + #"<blockquote")
    if after ~= ">" and after ~= " " and after ~= "" then
        return find_quote_open(html, at + 1)
    end
    local tag_end = html:find(">", at, true)
    return at, tag_end
end

--- Close of the innermost quote open at or after from_pos, counting only
--- real quote opens (prefix match, so classed tags nest correctly).
local function find_quote_close(html, from_pos)
    local depth = 1
    local position = from_pos
    while position <= #html do
        local open_start = find_quote_open(html, position)
        local close_start, close_end = html:find("</blockquote>", position, true)
        if not close_start then return nil end
        if open_start and open_start < close_start then
            depth = depth + 1
            position = open_start + #"<blockquote"
        else
            depth = depth - 1
            if depth == 0 then
                return close_start, close_end
            end
            position = close_end + 1
        end
    end
    return nil
end

--- Position of one of the sanitizer's own spans (imgref, spoiler,
--- embedref). The trailing quote in the search key already rules out longer
--- class names sharing the prefix; the next character tells the bare form
--- (">") from the with-attributes form (" ").
local function find_span(html, position, class)
    local key = '<span class="' .. class .. '"'
    local start_pos = html:find(key, position, true)
    if not start_pos then return nil end
    local after = html:sub(start_pos + #key, start_pos + #key)
    if after == ">" or after == " " then
        return start_pos
    end
    return nil
end

local function parse_quote_block(inner_html, blocks, inline, opts)
    local header
    local header_start, header_end, header_text = inner_html:find("<h4>(.-)</h4>")
    if header_start then
        header = collapse(htmltext.decode_entities(header_text))
        inner_html = inner_html:sub(1, header_start - 1) .. inner_html:sub(header_end + 1)
    end
    local mentions_you = false
    if header and opts and opts.username and opts.username ~= "" then
        mentions_you = header:lower() == (opts.username:lower() .. " posted:")
    end
    blocks[#blocks + 1] = {
        type = "quote",
        header = header,
        mentions_you = mentions_you or nil,
        text = inline(inner_html),
    }
end

--- Split a paragraph chunk on <br/> into trimmed inline chunks.
local function split_paragraphs(html)
    local chunks = {}
    local position = 1
    while true do
        local br_start, br_end = html:find("<br/>", position, true)
        if not br_start then
            chunks[#chunks + 1] = html:sub(position)
            break
        end
        chunks[#chunks + 1] = html:sub(position, br_start - 1)
        position = br_end + 1
    end
    return chunks
end

--- Prefix of a laid-out TextBoxWidget's text covering its first max_lines
--- lines, with bold markers balanced. Returns the prefix and how many
--- lines remain, or nil when the widget laid out to max_lines or fewer
--- (or never laid out at all, as under the test stubs).
function postblocks.collapsed_text(tbox, max_lines)
    local lines = tbox and tbox.vertical_string_list
    if not lines or #lines <= max_lines then return nil end
    local chars = tbox.charlist
    if not chars then return nil end
    local last = nil
    for i = max_lines, 1, -1 do
        if lines[i].end_offset then
            last = lines[i].end_offset
            break
        end
    end
    if not last then return nil end
    local parts = {}
    for i = 1, last do parts[#parts + 1] = chars[i] end
    local prefix = table.concat(parts)
    -- A bold run cut by the truncation must not leak past it.
    local opens = select(2, prefix:gsub(BOLD_START, ""))
    local closes = select(2, prefix:gsub(BOLD_END, ""))
    if opens > closes then
        prefix = prefix .. string.rep(BOLD_END, opens - closes)
    end
    return prefix, #lines - max_lines
end

--- Parse a sanitized post body into blocks, in document order.
function postblocks.parse(body_html, opts)
    local inline = make_inline_from_html(opts)
    local blocks = {}
    if not body_html or body_html == "" then return blocks end

    local function emit_paragraph(chunk)
        for _, piece in ipairs(split_paragraphs(chunk)) do
            local text = inline(piece)
            if text ~= "" then
                blocks[#blocks + 1] = { type = "para", text = PTF_HEADER .. text }
            end
        end
    end

    local position = 1
    while position <= #body_html do
        local quote_start, quote_tag_end = find_quote_open(body_html, position)
        local candidates = {
            { pos = quote_start, kind = "quote" },
            { pos = find_span(body_html, position, "imgref"), kind = "image" },
            { pos = find_span(body_html, position, "spoiler"), kind = "spoiler" },
            { pos = find_span(body_html, position, "embedref"), kind = "embed" },
        }
        local next_block, next_kind
        for _, candidate in ipairs(candidates) do
            if candidate.pos and (not next_block or candidate.pos < next_block) then
                next_block = candidate.pos
                next_kind = candidate.kind
            end
        end

        if not next_block then
            emit_paragraph(body_html:sub(position))
            break
        end

        emit_paragraph(body_html:sub(position, next_block - 1))

        -- The site's HTML sometimes leaves these unclosed or mismatched; a
        -- missing close tag degrades to "the rest is this block's text"
        -- rather than silently truncating the page.
        if next_kind == "quote" then
            local inner_start = (quote_tag_end or quote_start + #"<blockquote>") + 1
            local close_start, close_end = find_quote_close(body_html, inner_start)
            if not close_start then
                blocks[#blocks + 1] = {
                    type = "quote",
                    text = inline(body_html:sub(inner_start)),
                }
                break
            end
            parse_quote_block(body_html:sub(inner_start, close_start - 1), blocks, inline, opts)
            position = close_end + 1
        else
            local open_end = body_html:find(">", next_block, true)
            local close_start, close_end = body_html:find("</span>", (open_end or next_block) + 1, true)
            if not close_start then
                -- no close: the rest of the body is this block's content
                local tail = body_html:sub((open_end or next_block) + 1)
                if next_kind == "spoiler" then
                    local text = inline(tail):gsub("^%[spoiler%] (.*) %[/spoiler%]$", "%1")
                    blocks[#blocks + 1] = { type = "spoiler", text = text }
                elseif next_kind == "embed" then
                    local label = inline(tail)
                    if label ~= "" then
                        blocks[#blocks + 1] = { type = "embed", label = label }
                    end
                else
                    emit_paragraph(body_html:sub(next_block))
                end
                break
            end
            local inner = body_html:sub((open_end or next_block) + 1, close_start - 1)
            if next_kind == "image" then
                local open_tag = body_html:sub(next_block, open_end)
                local src = open_tag:match('src="([^"]*)"')
                local label = inline(inner)
                if label ~= "" then
                    blocks[#blocks + 1] = { type = "image", label = label, src = src }
                end
            elseif next_kind == "spoiler" then
                -- the sanitizer wraps spoiler text in [spoiler] markers;
                -- the block's card carries the labeling itself
                local text = inline(inner):gsub("^%[spoiler%] (.*) %[/spoiler%]$", "%1")
                blocks[#blocks + 1] = { type = "spoiler", text = text }
            else
                local label = inline(inner)
                if label ~= "" then
                    blocks[#blocks + 1] = { type = "embed", label = label }
                end
            end
            position = close_end + 1
        end
    end

    -- Last resort: a body that produced nothing but was not empty still
    -- shows its text (the ghost-page bug: fetches marked read, render
    -- showed nothing).
    if #blocks == 0 then
        local text = inline(body_html)
        if text ~= "" then
            blocks[#blocks + 1] = { type = "para", text = PTF_HEADER .. text }
        end
    end

    return blocks
end

return postblocks
