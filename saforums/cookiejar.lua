--[[
Cookie jar for the forums session.

Handles exactly what the site does: a couple of long-lived Set-Cookie headers
from the login response (bbuserid, bbpassword), Cloudflare's own cookies, and
nothing else exotic. Splitting honors the rule that a comma inside an Expires
date is not a cookie separator, the classic Set-Cookie trap.

Cookies are credentials (spec: Semantics > Session): this module never logs
values and offers them only through header().
--]]

local config = require("saforums.config")

local cookiejar = {}

local CookieJar = {}
CookieJar.__index = CookieJar

function cookiejar.new()
    return setmetatable({ cookies = {} }, CookieJar)
end

local TOKEN_CHARS = "[%a%d!#%$&'%*%+%.%-%^_`%~]"

-- Splits a comma-joined Set-Cookie payload into single header values without
-- cutting Expires dates: a comma only splits when a token-name followed by
-- "=" comes after it ("..., 21 Oct 2026" stays whole; "..., next=1" splits).
-- Quoted strings are parked behind sentinel bytes first so their commas and
-- equals signs never participate.
local function split_set_cookie(s)
    local quoted = {}
    s = s:gsub('"([^"]*)"', function(q)
        quoted[#quoted + 1] = q
        return "\1Q" .. #quoted .. "\1"
    end)

    local values = {}
    local start = 1
    local i = 1
    local n = #s
    while i <= n do
        if s:sub(i, i) == "," then
            local j = i + 1
            while s:sub(j, j) == " " do j = j + 1 end
            local k = j
            while s:sub(k, k):find(TOKEN_CHARS) do k = k + 1 end
            if k > j and s:sub(k, k) == "=" then
                -- The comma is a cookie separator; the next cookie's name
                -- starts at the token, not after the equals sign.
                values[#values + 1] = s:sub(start, i - 1)
                start = j
                i = start
            else
                i = i + 1
            end
        else
            i = i + 1
        end
    end
    values[#values + 1] = s:sub(start)

    for idx = 1, #values do
        values[idx] = (values[idx]:gsub("\1Q(%d+)\1", function(m)
            return '"' .. quoted[tonumber(m)] .. '"'
        end):gsub("^%s+", ""))
    end
    return values
end

-- Parses one Set-Cookie value into {name, value, path, domain, expires}.
local function parse_set_cookie(value)
    local name, rest = value:match("^%s*([^=;]+)%s*=%s*(.-)%s*$")
    if not name then return nil end
    local cookie = { name = name, value = (rest:gsub('%s*;%s*$', "")) }
    local head, attributes = cookie.value:match("^(.-);(.*)$")
    if head then
        cookie.value = head
        for attribute in attributes:gmatch("[^;]+") do
            local k, v = attribute:match("^%s*([^=]+)%s*=?%s*(.-)%s*$")
            if k then
                k = k:lower()
                if k == "path" or k == "domain" or k == "expires" then
                    cookie[k] = v
                end
            end
        end
    end
    cookie.value = cookie.value:gsub('^"(.*)"$', "%1")
    return cookie
end

--- Feed a response headers table (lowercased keys, as LuaSocket/LuaSec return
--- them). The set-cookie field may be a single comma-joined string or a list.
function CookieJar:store(headers)
    if not headers then return end
    local raw = headers["set-cookie"]
    if not raw then return end
    for _, value in ipairs(type(raw) == "table" and raw or split_set_cookie(raw)) do
        local cookie = parse_set_cookie(value)
        if cookie then
            self.cookies[cookie.name] = cookie
        end
    end
end

function CookieJar:get(name)
    local cookie = self.cookies[name]
    return cookie and cookie.value or nil
end

--- The session is whatever the site says it is: a bbuserid cookie (spec).
--- A deleted cookie arrives as an empty value, which is no session.
function CookieJar:has_session()
    local value = self:get(config.session_user_cookie)
    return value ~= nil and value ~= ""
end

--- Cookie header value for requests to the forums host.
function CookieJar:header()
    local parts = {}
    for name, cookie in pairs(self.cookies) do
        parts[#parts + 1] = name .. "=" .. cookie.value
    end
    table.sort(parts)
    return table.concat(parts, "; ")
end

--- Drop session state. Cloudflare clearance survives a logout (the site still
--- fronts its challenge with it), everything else goes.
function CookieJar:clear_session()
    for name in pairs(self.cookies) do
        if not name:find("^__cf") and name ~= "cf_clearance" then
            self.cookies[name] = nil
        end
    end
end

--- Plain table for settings persistence (device side); load() restores.
function CookieJar:to_table()
    local out = {}
    for name, cookie in pairs(self.cookies) do
        out[name] = { value = cookie.value, path = cookie.path, domain = cookie.domain }
    end
    return out
end

function CookieJar:load(t)
    if not t then return end
    for name, cookie in pairs(t) do
        self.cookies[name] = { name = name, value = cookie.value, path = cookie.path, domain = cookie.domain }
    end
end

cookiejar.split_set_cookie = split_set_cookie
cookiejar.parse_set_cookie = parse_set_cookie

return cookiejar
