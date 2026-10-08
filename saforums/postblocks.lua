--[[
Pure block model: turns the sanitized post-body HTML (the posthtml
sanitizer's output) into a list of layout blocks for the native widget
renderer.

    { type = "para",  text = "..." }   -- text carries PTF bold markers
    { type = "quote", header = "...", text = "..." }
    { type = "image", label = "[image: x.png]" }

A string scanner rather than a DOM walk: htmlparser's tree is
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

local function collapse(text)
    return htmltext.trim((text:gsub("%s+", " ")))
end

--- Inline HTML to PTF-marked plain text: <b>/<strong> runs wrapped in
--- TextBoxWidget's bold markers, every other tag stripped, entities
--- decoded, whitespace collapsed.
local function inline_from_html(html)
    html = html:gsub("<b>(.-)</b>", BOLD_START .. "%1" .. BOLD_END)
    html = html:gsub("<strong>(.-)</strong>", BOLD_START .. "%1" .. BOLD_END)
    html = html:gsub("<span class=\"spoiler\">%[spoiler%] (.-) %[/spoiler%]", "[spoiler] %1 [/spoiler]")
    html = html:gsub("<[^>]*>", "")
    return collapse(htmltext.decode_entities(html))
end

--- Find the extent of a block element from its opening tag position,
--- counting nesting (blockquotes quote blockquotes on this site).
local function find_block_end(html, start_pos, open_tag, close_tag)
    local depth = 1 -- the opening tag we are inside already counts
    local position = start_pos
    while position <= #html do
        local open_start, open_end = html:find(open_tag, position, true)
        local close_start, close_end = html:find(close_tag, position, true)
        if not close_start then return nil end
        if open_start and open_start < close_start then
            depth = depth + 1
            position = open_end + 1
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

local function parse_quote_block(inner_html, blocks)
    local header
    local header_start, header_end, header_text = inner_html:find("<h4>(.-)</h4>")
    if header_start then
        header = collapse(htmltext.decode_entities(header_text))
        inner_html = inner_html:sub(1, header_start - 1) .. inner_html:sub(header_end + 1)
    end
    blocks[#blocks + 1] = {
        type = "quote",
        header = header,
        text = inline_from_html(inner_html),
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

--- Parse a sanitized post body into blocks, in document order.
function postblocks.parse(body_html)
    local blocks = {}
    if not body_html or body_html == "" then return blocks end

    local function emit_paragraph(chunk)
        for _, piece in ipairs(split_paragraphs(chunk)) do
            local text = inline_from_html(piece)
            if text ~= "" then
                blocks[#blocks + 1] = { type = "para", text = PTF_HEADER .. text }
            end
        end
    end

    local position = 1
    while position <= #body_html do
        local quote_start = body_html:find("<blockquote>", position, true)
        local image_start = body_html:find('<span class="imgref">', position, true)

        local next_block = quote_start
        local next_kind = "quote"
        if image_start and (not next_block or image_start < next_block) then
            next_block = image_start
            next_kind = "image"
        end

        if not next_block then
            emit_paragraph(body_html:sub(position))
            break
        end

        emit_paragraph(body_html:sub(position, next_block - 1))

        if next_kind == "quote" then
            local inner_start = quote_start + #"<blockquote>"
            local close_start, close_end = find_block_end(body_html, inner_start, "<blockquote>", "</blockquote>")
            if not close_start then break end
            parse_quote_block(body_html:sub(inner_start, close_start - 1), blocks)
            position = close_end + 1
        else
            local close_start, close_end = body_html:find("</span>", image_start, true)
            if not close_start then break end
            local label = inline_from_html(body_html:sub(image_start + #'<span class="imgref">', close_start - 1))
            if label ~= "" then
                blocks[#blocks + 1] = { type = "image", label = label }
            end
            position = close_end + 1
        end
    end

    return blocks
end

return postblocks
