--[[
The forums session: login, requests, redirects, cookies, and the failure
modes the site actually produces (Cloudflare challenges, server-side logout).

Behavioral contract: spec.md, Semantics > Session and the endpoints table.
Every request goes out with the honest UA and the session cookies; every
response feeds the jar; a bbuserid flip between requests means the site
logged us out. POSTs are multipart/form-data in Windows-1252, because that
is the dialect the site's forms speak.

The transport is injectable: on device it is ssl.https via socketutil; tests
pass a recording fake. Nothing else in this module touches I/O.
--]]

local ltn12 = require("ltn12")

local config = require("saforums.config")
local cookiejar = require("saforums.cookiejar")
local cp1252 = require("saforums.cp1252")
local indexparser = require("saforums.indexparser")
local json = require("saforums.json")

local session = {}

local Session = {}
Session.__index = Session

local BOUNDARY = "saforums-form-boundary-7f3a9c"

local function default_transport(request)
    local socketutil = require("socketutil")
    local https = require("ssl.https")
    request.source = ltn12.source.string(request.body)
    local sink = {}
    request.sink = ltn12.sink.table(sink)
    request.redirect = false
    request.block_timeout = config.request_block_timeout
    request.total_timeout = config.request_total_timeout
    local ok, code, headers
    if request.body and #request.body > 0 then
        request.headers = request.headers or {}
        request.headers["content-length"] = tostring(#request.body)
        ok, code, headers = https.request(request)
    else
        request.body = nil
        ok, code, headers = https.request(request)
    end
    if not ok then
        return nil, headers
    end
    return code, headers, table.concat(sink)
end

--- Build a multipart/form-data body with 1252-encoded field values.
local function multipart_body(fields)
    local parts = {}
    for key, value in pairs(fields) do
        parts[#parts + 1] = table.concat({
            "--" .. BOUNDARY,
            'Content-Disposition: form-data; name="' .. key .. '"',
            "",
            cp1252.encode(tostring(value)),
        }, "\r\n")
    end
    parts[#parts + 1] = "--" .. BOUNDARY .. "--\r\n"
    return table.concat(parts, "\r\n")
end

--- Join a Location header onto the URL that produced it.
local function resolve_url(base, location)
    if not location or location == "" then return base end
    if location:find("^https?://") then return location end
    local origin = base:match("^(https?://[^/]+)")
    if location:sub(1, 1) == "/" then
        return origin .. location
    end
    local dir = base:match("^(.*/)[^/]*$")
    return (dir or origin .. "/") .. location
end

function html_query(url, name) -- luacheck: ignore (module-local helper)
    return url:match("[?&]" .. name .. "=([^&]*)")
end

--- After a goto=newpost redirect the site drops the perpage parameter
--- (spec: HTML structure contract); put it back.
local function restore_perpage(url)
    if not url:find("showthread%.php") then return url end
    if html_query(url, "perpage") then return url end
    return url .. (url:find("%?") and "&" or "?") .. "perpage=" .. config.perpage
end

--- Cloudflare fronted the request with a challenge we cannot solve here.
local function looks_like_challenge(code, headers, body)
    local mitigated = headers and headers["cf-mitigated"]
    if mitigated and tostring(mitigated):find("challenge", 1, true) then
        return true
    end
    if code == 403 or code == 503 then
        if body:find("challenges%.cloudflare%.com") or body:find("Just a moment")
            or body:find("Attention Required") then
            return true
        end
    end
    return false
end

function session.new(transport)
    local self = setmetatable({
        jar = cookiejar.new(),
        transport = transport or default_transport,
    }, Session)
    return self
end

--- Single request with cookie/UA headers, manual redirects, jar updates,
--- and session-loss detection. Returns a result table:
---   { kind = "ok"|"cloudflare"|"logged_out"|"http_error"|"transport_error",
---     code, url (final), body (UTF-8 decoded) }
function Session:request(method, url, fields)
    local body = fields and multipart_body(fields) or nil
    local was_logged_in = self.jar:has_session()

    for _ = 1, 5 do
        local headers_map = {
            ["user-agent"] = config.user_agent(),
            ["cookie"] = self.jar:header(),
        }
        if body then
            headers_map["content-type"] = "multipart/form-data; boundary=" .. BOUNDARY
        end

        local code, headers, response = self.transport({
            method = method,
            url = url,
            headers = headers_map,
            body = body,
        })

        if code == nil then
            return { kind = "transport_error", error = headers }
        end

        self.jar:store(headers)

        if code == 301 or code == 302 or code == 303 or code == 307 then
            local location = headers and (headers["location"] or (type(headers.location) == "table" and headers.location[1]))
            url = restore_perpage(resolve_url(url, location))
            if code == 303 or code == 302 then
                method = "GET"
                body = nil
            end
        else
            local result = {
                code = code,
                url = url,
                body = cp1252.decode(response),
            }
            if looks_like_challenge(code, headers, response) then
                result.kind = "cloudflare"
            elseif code ~= 200 then
                result.kind = "http_error"
            elseif was_logged_in and not self.jar:has_session() then
                result.kind = "logged_out"
                self.jar:clear_session()
            else
                result.kind = "ok"
            end
            return result
        end
    end

    return { kind = "http_error", code = nil, url = url, error = "too many redirects" }
end

function Session:get(url)
    return self:request("GET", url, nil)
end

--- POST form fields and parse a JSON reply. Returns the parsed document or
--- an error table. A non-JSON body on login means the credentials failed:
--- the site answers bad logins with its HTML error page (spec: Session).
function Session:post_json(url, fields)
    local result = self:request("POST", url, fields)
    if result.kind ~= "ok" then
        return nil, result
    end
    local ok, document = pcall(json.decode, result.body or "")
    if not ok then
        return nil, { kind = "not_json", code = result.code, url = result.url }
    end
    return document, result
end

--- Login per spec: POST account.php?json=1. Returns parsed index document
--- on success; nil, result on failure.
function Session:login(username, password)
    return self:post_json(config.base_url .. "/account.php?json=1", {
        action = "login",
        username = username,
        password = password,
        next = "/index.php?json=1",
    })
end

function Session:has_session()
    return self.jar:has_session()
end

--- Persistence delegates to the jar's plain tables; the UI layer decides
--- where they live on a given device.
function Session:to_table()
    return { cookies = self.jar:to_table() }
end

function Session:load(t)
    if t and t.cookies then
        self.jar:load(t.cookies)
    end
end

session.multipart_body = multipart_body
session.resolve_url = resolve_url
session.restore_perpage = restore_perpage

return session
