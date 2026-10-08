--[[
Windows-1252 codec.

The site is Windows-1252 end to end (spec: HTML structure contract). Requests
escape characters the encoding cannot represent as decimal HTML entities, which
is the same trick the reference clients use so a form field like "naïve 🙃"
survives the trip. Page bodies are decoded to UTF-8 before parsing.
--]]

local cp1252 = {}

-- Bytes 0x80..0x9F: the C1 frame is replaced with printable characters.
-- Undefined slots (0x81, 0x8D, 0x8F, 0x90, 0x9D) decode to U+FFFD.
local high = {
    [0x80] = 0x20AC, -- EURO SIGN
    [0x82] = 0x201A, -- SINGLE LOW-9 QUOTATION MARK
    [0x83] = 0x0192, -- LATIN SMALL LETTER F WITH HOOK
    [0x84] = 0x201E, -- DOUBLE LOW-9 QUOTATION MARK
    [0x85] = 0x2026, -- HORIZONTAL ELLIPSIS
    [0x86] = 0x2020, -- DAGGER
    [0x87] = 0x2021, -- DOUBLE DAGGER
    [0x88] = 0x02C6, -- MODIFIER LETTER CIRCUMFLEX ACCENT
    [0x89] = 0x2030, -- PER MILLE SIGN
    [0x8A] = 0x0160, -- LATIN CAPITAL LETTER S WITH CARON
    [0x8B] = 0x2039, -- SINGLE LEFT-POINTING ANGLE QUOTATION MARK
    [0x8C] = 0x0152, -- LATIN CAPITAL LIGATURE OE
    [0x8E] = 0x017D, -- LATIN CAPITAL LETTER Z WITH CARON
    [0x91] = 0x2018, -- LEFT SINGLE QUOTATION MARK
    [0x92] = 0x2019, -- RIGHT SINGLE QUOTATION MARK
    [0x93] = 0x201C, -- LEFT DOUBLE QUOTATION MARK
    [0x94] = 0x201D, -- RIGHT DOUBLE QUOTATION MARK
    [0x95] = 0x2022, -- BULLET
    [0x96] = 0x2013, -- EN DASH
    [0x97] = 0x2014, -- EM DASH
    [0x98] = 0x02DC, -- SMALL TILDE
    [0x99] = 0x2122, -- TRADE MARK SIGN
    [0x9A] = 0x0161, -- LATIN SMALL LETTER S WITH CARON
    [0x9B] = 0x203A, -- SINGLE RIGHT-POINTING ANGLE QUOTATION MARK
    [0x9C] = 0x0153, -- LATIN SMALL LIGATURE OE
    [0x9E] = 0x017E, -- LATIN SMALL LETTER Z WITH CARON
    [0x9F] = 0x0178, -- LATIN CAPITAL LETTER Y WITH DIAERESIS
}

local low_reverse = {}
for byte, codepoint in pairs(high) do
    low_reverse[codepoint] = byte
end
-- Bytes 0xA0..0xFF map to the identical Unicode codepoints.
for byte = 0xA0, 0xFF do
    low_reverse[byte] = byte
end

local REPLACEMENT = "\xEF\xBF\xBD" -- U+FFFD

local function utf8_encode(codepoint)
    if codepoint < 0x80 then
        return string.char(codepoint)
    elseif codepoint < 0x800 then
        return string.char(
            0xC0 + math.floor(codepoint / 0x40),
            0x80 + codepoint % 0x40
        )
    elseif codepoint < 0x10000 then
        return string.char(
            0xE0 + math.floor(codepoint / 0x1000),
            0x80 + math.floor(codepoint / 0x40) % 0x40,
            0x80 + codepoint % 0x40
        )
    else
        return string.char(
            0xF0 + math.floor(codepoint / 0x40000),
            0x80 + math.floor(codepoint / 0x1000) % 0x40,
            0x80 + math.floor(codepoint / 0x40) % 0x40,
            0x80 + codepoint % 0x40
        )
    end
end

-- Returns the codepoint at the position and its byte length, or nil for a
-- malformed sequence (we decode byte-wise and never trust the source).
local function utf8_decode(s, i)
    local b1 = s:byte(i)
    if b1 < 0x80 then
        return b1, 1
    elseif b1 < 0xC2 then
        return nil
    elseif b1 < 0xE0 then
        local b2 = s:byte(i + 1)
        if not b2 or b2 < 0x80 or b2 > 0xBF then return nil end
        return (b1 - 0xC0) * 0x40 + (b2 - 0x80), 2
    elseif b1 < 0xF0 then
        local b2, b3 = s:byte(i + 1, i + 2)
        if not b3 or b2 < 0x80 or b2 > 0xBF or b3 < 0x80 or b3 > 0xBF then return nil end
        return (b1 - 0xE0) * 0x1000 + (b2 - 0x80) * 0x40 + (b3 - 0x80), 3
    elseif b1 < 0xF5 then
        local b2, b3, b4 = s:byte(i + 1, i + 3)
        if not b4 or b2 < 0x80 or b2 > 0xBF or b3 < 0x80 or b3 > 0xBF or b4 < 0x80 or b4 > 0xBF then
            return nil
        end
        return (b1 - 0xF0) * 0x40000 + (b2 - 0x80) * 0x1000 + (b3 - 0x80) * 0x40 + (b4 - 0x80), 4
    end
    return nil
end

--- Windows-1252 bytes to UTF-8.
function cp1252.decode(s)
    if not s then return nil end
    local out = {}
    local i, n = 1, #s
    while i <= n do
        local byte = s:byte(i)
        if byte < 0x80 then
            out[#out + 1] = s:sub(i, i)
            i = i + 1
        elseif byte >= 0xA0 then
            out[#out + 1] = utf8_encode(byte)
            i = i + 1
        else
            local codepoint = high[byte]
            out[#out + 1] = codepoint and utf8_encode(codepoint) or REPLACEMENT
            i = i + 1
        end
    end
    return table.concat(out)
end

--- UTF-8 to Windows-1252 bytes. Codepoints the encoding cannot carry become
--- decimal HTML entities, e.g. "naïve 🙃" -> "naïve &#128569;". The receiving
--- form decodes entities, which is why this round-trips.
function cp1252.encode(s)
    if not s then return nil end
    local out = {}
    local i, n = 1, #s
    while i <= n do
        local codepoint, len = utf8_decode(s, i)
        if not codepoint then
            out[#out + 1] = REPLACEMENT
            i = i + 1
        elseif codepoint < 0x80 then
            out[#out + 1] = string.char(codepoint)
            i = i + len
        else
            local byte = low_reverse[codepoint]
            if byte then
                out[#out + 1] = string.char(byte)
            else
                out[#out + 1] = string.format("&#%d;", codepoint)
            end
            i = i + len
        end
    end
    return table.concat(out)
end

return cp1252
