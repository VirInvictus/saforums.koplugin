--[[
Text helpers over parsed HTML nodes.

The html parser returns raw substrings: entities undecoded, whitespace from
the source formatting intact. Every text field the parsers surface (titles,
names, dates, counts) goes through text() so the rest of the plugin works
with clean UTF-8. Post bodies stay raw on purpose; the EPUB builder owns
them.
--]]

local cp1252 = require("saforums.cp1252")

local htmltext = {}

local named = {
    ["amp"] = "&",
    ["lt"] = "<",
    ["gt"] = ">",
    ["quot"] = '"',
    ["apos"] = "'",
    ["nbsp"] = " ",
    ["hellip"] = "\xE2\x80\xA6",
    ["mdash"] = "\xE2\x80\x94",
    ["ndash"] = "\xE2\x80\x93",
    ["laquo"] = "\xC2\xAB",
    ["raquo"] = "\xC2\xBB",
    ["copy"] = "\xC2\xA9",
}

function htmltext.decode_entities(s)
    s = s:gsub("&#(%d+);", function(body)
        local codepoint = tonumber(body, 10)
        if codepoint and codepoint > 0 and codepoint <= 0x10FFFF then
            return cp1252.utf8_encode(codepoint)
        end
        return "&#" .. body .. ";"
    end)
    s = s:gsub("&#x(%x+);", function(body)
        local codepoint = tonumber(body, 16)
        if codepoint and codepoint > 0 and codepoint <= 0x10FFFF then
            return cp1252.utf8_encode(codepoint)
        end
        return "&#x" .. body .. ";"
    end)
    s = s:gsub("&(%a+);", function(body)
        return named[body] or ("&" .. body .. ";")
    end)
    return s
end

function htmltext.trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Decoded, trimmed text of a parsed node; nil-safe for optional nodes.
function htmltext.text(node)
    if not node then return nil end
    return htmltext.trim(htmltext.decode_entities(node:textonly()))
end

--- Raw (entities intact) inner content of a parsed node.
function htmltext.content(node)
    if not node then return nil end
    return node:getcontent()
end

--- True when the node's class list contains the class.
function htmltext.has_class(node, class)
    if not node then return false end
    for _, c in ipairs(node.classes or {}) do
        if c == class then return true end
    end
    return false
end

--- Class matching a pattern (e.g. "^bm(%d)$" for bookmark star colors).
function htmltext.class_match(node, pattern)
    if not node then return nil end
    for _, c in ipairs(node.classes or {}) do
        local captured = c:match(pattern)
        if captured then return captured end
    end
    return nil
end

--- Pull a query parameter out of an href/URL string. Attribute values arrive
--- entity-encoded ("&amp;" between params), so decode before matching.
function htmltext.query_param(url, name)
    if not url then return nil end
    url = htmltext.decode_entities(url)
    return url:match("[?&]" .. name .. "=([^&]*)")
end

return htmltext
