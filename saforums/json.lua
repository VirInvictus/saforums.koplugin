--[[
Small JSON decoder, stdlib Lua 5.1.

Only a decoder: everything the plugin sends is form-encoded. Covers what the
site's JSON side-channel actually emits (strings, numbers, booleans, null,
arrays, objects, \u escapes incl. surrogate pairs) and fails loudly with a
position on anything else.
--]]

local json = {}

local function decode_error(s, i, message)
    error(string.format("json: %s at position %d in: %.60s", message, i, s), 0)
end

local escapes = {
    ['"'] = '"', ["\\"] = "\\", ["/"] = "/",
    b = "\b", f = "\f", n = "\n", r = "\r", t = "\t",
}

local function skip_whitespace(s, i)
    while i <= #s do
        local c = s:sub(i, i)
        if c == " " or c == "\t" or c == "\n" or c == "\r" then
            i = i + 1
        else
            break
        end
    end
    return i
end

local function decode_string(s, i)
    i = i + 1 -- opening quote
    local out = {}
    while true do
        local c = s:sub(i, i)
        if c == "" then
            decode_error(s, i, "unterminated string")
        elseif c == '"' then
            return table.concat(out), i + 1
        elseif c == "\\" then
            local e = s:sub(i + 1, i + 1)
            if escapes[e] then
                out[#out + 1] = escapes[e]
                i = i + 2
            elseif e == "u" then
                local hex = s:sub(i + 2, i + 5)
                if #hex < 4 or not hex:find("^%x%x%x%x$") then
                    decode_error(s, i, "bad \\u escape")
                end
                local codepoint = tonumber(hex, 16)
                i = i + 6
                if codepoint >= 0xD800 and codepoint <= 0xDBFF then
                    -- High surrogate: a low surrogate must follow.
                    if s:sub(i, i + 1) ~= "\\u" then
                        decode_error(s, i, "lone high surrogate")
                    end
                    local low_hex = s:sub(i + 2, i + 5)
                    if #low_hex < 4 or not low_hex:find("^%x%x%x%x$") then
                        decode_error(s, i, "bad low surrogate")
                    end
                    local low = tonumber(low_hex, 16)
                    if low < 0xDC00 or low > 0xDFFF then
                        decode_error(s, i, "invalid low surrogate")
                    end
                    codepoint = 0x10000 + (codepoint - 0xD800) * 0x400 + (low - 0xDC00)
                    i = i + 6
                elseif codepoint >= 0xDC00 and codepoint <= 0xDFFF then
                    decode_error(s, i, "lone low surrogate")
                end
                -- Encode UTF-8.
                if codepoint < 0x80 then
                    out[#out + 1] = string.char(codepoint)
                elseif codepoint < 0x800 then
                    out[#out + 1] = string.char(
                        0xC0 + math.floor(codepoint / 0x40),
                        0x80 + codepoint % 0x40)
                elseif codepoint < 0x10000 then
                    out[#out + 1] = string.char(
                        0xE0 + math.floor(codepoint / 0x1000),
                        0x80 + math.floor(codepoint / 0x40) % 0x40,
                        0x80 + codepoint % 0x40)
                else
                    out[#out + 1] = string.char(
                        0xF0 + math.floor(codepoint / 0x40000),
                        0x80 + math.floor(codepoint / 0x1000) % 0x40,
                        0x80 + math.floor(codepoint / 0x40) % 0x40,
                        0x80 + codepoint % 0x40)
                end
            else
                decode_error(s, i, "bad escape: " .. e)
            end
        else
            out[#out + 1] = c
            i = i + 1
        end
    end
end

local function decode_value(s, i)
    i = skip_whitespace(s, i)
    local c = s:sub(i, i)
    if c == '"' then
        return decode_string(s, i)
    elseif c == "{" then
        local object = {}
        i = skip_whitespace(s, i + 1)
        if s:sub(i, i) == "}" then
            return object, i + 1
        end
        while true do
            i = skip_whitespace(s, i)
            if s:sub(i, i) ~= '"' then
                decode_error(s, i, "expected object key")
            end
            local key
            key, i = decode_string(s, i)
            i = skip_whitespace(s, i)
            if s:sub(i, i) ~= ":" then
                decode_error(s, i, "expected ':'")
            end
            local value
            value, i = decode_value(s, i + 1)
            object[key] = value
            i = skip_whitespace(s, i)
            local terminator = s:sub(i, i)
            if terminator == "," then
                i = i + 1
            elseif terminator == "}" then
                return object, i + 1
            else
                decode_error(s, i, "expected ',' or '}'")
            end
        end
    elseif c == "[" then
        local array = {}
        i = skip_whitespace(s, i + 1)
        if s:sub(i, i) == "]" then
            return array, i + 1
        end
        while true do
            local value
            value, i = decode_value(s, i)
            array[#array + 1] = value
            i = skip_whitespace(s, i)
            local terminator = s:sub(i, i)
            if terminator == "," then
                i = i + 1
            elseif terminator == "]" then
                return array, i + 1
            else
                decode_error(s, i, "expected ',' or ']'")
            end
        end
    elseif s:sub(i, i + 4) == "false" then
        return false, i + 5
    elseif s:sub(i, i + 3) == "true" then
        return true, i + 4
    elseif s:sub(i, i + 3) == "null" then
        return json.null, i + 4
    elseif c == "-" or c:find("^%d") then
        local number = s:match("^%-?%d+%.?%d*[eE]?[+-]?%d*", i)
        if not number or tonumber(number) == nil then
            decode_error(s, i, "bad number")
        end
        return tonumber(number), i + #number
    else
        decode_error(s, i, "unexpected character: " .. (c == "" and "<end>" or c))
    end
end

--- Sentinel for JSON null, distinct from a missing key.
json.null = setmetatable({}, {
    __tostring = function() return "json.null" end,
})

--- Decode a JSON document. Returns one value; throws on malformed input.
function json.decode(s)
    local value, next_i = decode_value(s, 1)
    next_i = skip_whitespace(s, next_i)
    if next_i <= #s then
        decode_error(s, next_i, "trailing content")
    end
    return value
end

return json
