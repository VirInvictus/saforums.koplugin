require("spec.stubs")

-- Everything is driven synchronously: the environment (socket, ssl, url,
-- select, scheduler, clock) is injected per instance, and the scripted
-- sockets below serve precomputed responses with explicit would-block
-- points so the non-blocking paths (yield, partial-prefix carry,
-- deadline, cancel) are all observable.
local asyncimage = require("saforums.asyncimage")

-- ---------------------------------------------------------------------------
-- Fakes
-- ---------------------------------------------------------------------------

--- Minimal URL helpers shaped like socket.url's parse/absolute for the
--- URLs the tests use.
local fake_url = {}
function fake_url.parse(url)
    local scheme, rest = url:match("^(https?)://([^/]*)([^#]*)")
    if not scheme then return nil end
    local authority, path = rest:match("^([^/]*)(.*)")
    if authority == "" then return nil end
    local host, port = authority:match("^([^:]+):?(%d*)$")
    local parsed = { scheme = scheme, host = host, path = path ~= "" and path or "/" }
    if port and port ~= "" then parsed.port = tonumber(port) end
    local query
    if parsed.path and parsed.path:find("?", 1, true) then
        parsed.path, query = parsed.path:match("^([^?]*)%?(.*)$")
        parsed.query = query
    end
    return parsed
end
function fake_url.absolute(base, location)
    if location:find("^https?://") then return location end
    local origin = base:match("^(https?://[^/]+)")
    return origin .. location
end

--- A socket whose receive() serves a scripted list of deliverables:
---   { line = "..." }            a complete header/body line
---   { partial = "..." }         bytes that arrive before a would-block
---   { data = "..." }            exactly-n bytes for a sized receive
---   { eof = true }              connection closed (read-to-close end)
--- Method scripts (connect/dohandshake) would-block exactly once each so
--- the async paths always run.
local ScriptedSocket = {}
ScriptedSocket.__index = ScriptedSocket

local function new_socket(script)
    script = script or {}
    local sock = setmetatable({
        script = script,
        deliveries = script.deliveries or {},
        closed = false,
        connects = 0,
        handshakes = 0,
    }, ScriptedSocket)
    sock.sni = function() end
    return sock
end

function ScriptedSocket:settimeout() end

function ScriptedSocket:connect()
    self.connects = self.connects + 1
    if self.connects == 1 then
        return nil, "Operation already in progress"
    end
    return 1
end

function ScriptedSocket:dohandshake()
    self.handshakes = self.handshakes + 1
    if self.handshakes == 1 then
        return nil, "wantread"
    end
    return true
end

function ScriptedSocket:send(data, i)
    if self.script.send_would_block and i == 1 then
        self.script.send_would_block = nil
        return nil, "wantwrite", 0
    end
    return #data
end

local function deliver(sock, prefix)
    local item = table.remove(sock.deliveries, 1)
    if not item then
        return nil, "closed", prefix
    end
    if item.eof then
        return nil, "closed", prefix
    end
    if item.partial then
        return nil, "timeout", (prefix or "") .. item.partial
    end
    return (prefix or "") .. (item.line or item.data or "")
end

function ScriptedSocket:receive(pattern, prefix)
    if pattern == "*l" then
        return deliver(self, prefix)
    end
    if type(pattern) == "number" then
        -- Sized reads are scripted as whole chunks or partial stalls.
        return deliver(self, prefix)
    end
    return deliver(self, prefix)
end

function ScriptedSocket:close()
    self.closed = true
end

local function make_env(sockets, opts)
    opts = opts or {}
    local scheduled = {}
    local env = {
        socket = { tcp = function()
            local sock = new_socket(opts.script)
            sockets[#sockets + 1] = sock
            return sock
        end },
        ssl = { wrap = function(sock)
            return sock
        end },
        url = fake_url,
        select_fn = opts.select_fn or function(recvt, sendt)
            -- Everything ready by default; tests override for not-ready.
            return recvt, sendt
        end,
        schedule_fn = function(delay, fn)
            scheduled[#scheduled + 1] = fn
        end,
        now = opts.now or function() return 1000 end,
    }
    return env, scheduled
end

local function fire(scheduled)
    local fns = { scheduled[1] }
    for i = #scheduled, 1, -1 do scheduled[i] = nil end
    for _, fn in ipairs(fns) do fn() end
end

--- Fire scheduled ticks until the driver stops scheduling (with a cap).
local function pump(scheduled)
    for _round = 1, 50 do
        if #scheduled == 0 then return end
        fire(scheduled)
    end
    error("pump: the driver never stopped scheduling")
end

-- A full 200 response script: headers, a partial-line stall mid-header,
-- and a content-length body split across a stall.
local function response_script(headers, body)
    local deliveries = {}
    local first = true
    for _, line in ipairs({ "HTTP/1.1 200 OK", table.unpack(headers), "" }) do
        if first then
            deliveries[#deliveries + 1] = { partial = line:sub(1, 5) }
            deliveries[#deliveries + 1] = { line = line:sub(6) }
            first = false
        else
            deliveries[#deliveries + 1] = { line = line }
        end
    end
    deliveries[#deliveries + 1] = { partial = body:sub(1, 3) }
    deliveries[#deliveries + 1] = { data = body:sub(4) }
    return { deliveries = deliveries }
end

-- ---------------------------------------------------------------------------
-- The vendored fetch core
-- ---------------------------------------------------------------------------

describe("asyncimage fetch core", function()
    it("completes an https fetch through stalls and handshakes", function()
        local sockets = {}
        local env, scheduled = make_env(sockets,
            { script = response_script({ "content-length: 11" }, "hello-bytes") })
        local fetcher = asyncimage.new(env)
        local completed
        fetcher:start{
            tasks = { { uid = 7, src = "https://fi.fixture.invalid/avatars/7.gif" } },
            on_complete = function(results) completed = results end,
        }
        assert.is_nil(completed, "one tick cannot finish a stalled fetch")
        pump(scheduled)
        assert.is_not_nil(completed, "fetch did not complete")
        assert.equals("hello-bytes", completed[7])
        assert.is_true(sockets[1].closed)
    end)

    it("reads a chunked body", function()
        local sockets = {}
        local env, scheduled = make_env(sockets, {
            script = {
                deliveries = {
                    { line = "HTTP/1.1 200 OK" },
                    { line = "transfer-encoding: chunked" },
                    { line = "" },
                    { line = "5" },
                    { data = "abcde" },
                    { line = "" },
                    { line = "3" },
                    { data = "fgh" },
                    { line = "" },
                    { line = "0" },
                },
            },
        })
        local fetcher = asyncimage.new(env)
        local completed
        fetcher:start{
            tasks = { { uid = 8, src = "https://fi.fixture.invalid/a.png" } },
            on_complete = function(results) completed = results end,
        }
        pump(scheduled)
        assert.is_not_nil(completed)
        assert.equals("abcdefgh", completed[8])
    end)

    it("follows a redirect once and fetches the target", function()
        local sockets = {}
        local scripts = {
            { deliveries = {
                { line = "HTTP/1.1 302 Found" },
                { line = "location: https://cdn.fixture.invalid/real.gif" },
                { line = "" },
            } },
            response_script({ "content-length: 4" }, "abcd"),
        }
        local which = 0
        local env, scheduled = make_env(sockets, {})
        env.socket.tcp = function()
            which = which + 1
            local sock = new_socket(scripts[which])
            sockets[#sockets + 1] = sock
            return sock
        end
        local fetcher = asyncimage.new(env)
        local completed
        fetcher:start{
            tasks = { { uid = 9, src = "https://fi.fixture.invalid/redirect.gif" } },
            on_complete = function(results) completed = results end,
        }
        pump(scheduled)
        assert.is_not_nil(completed)
        assert.equals("abcd", completed[9])
        assert.equals(2, #sockets, "redirect must open a second socket")
    end)

    it("an HTTP error fails the task without a result", function()
        local sockets = {}
        local env, scheduled = make_env(sockets, {
            script = { deliveries = {
                { line = "HTTP/1.1 404 Not Found" },
                { line = "" },
            } },
        })
        local fetcher = asyncimage.new(env)
        local completed
        fetcher:start{
            tasks = { { uid = 10, src = "https://fi.fixture.invalid/gone.png" } },
            on_complete = function(results) completed = results end,
        }
        pump(scheduled)
        assert.is_not_nil(completed)
        assert.is_nil(completed[10])
    end)

    it("a content-length body cut short by EOF fails, never caches", function()
        -- Avatar files live forever; half an image returned as a success
        -- would corrupt that poster's face on every future render.
        local sockets = {}
        local env, scheduled = make_env(sockets, {
            script = { deliveries = {
                { line = "HTTP/1.1 200 OK" },
                { line = "content-length: 11" },
                { line = "" },
                { partial = "abc" },
                { eof = true },
            } },
        })
        local fetcher = asyncimage.new(env)
        local completed
        fetcher:start{
            tasks = { { uid = 11, src = "https://fi.fixture.invalid/cut.gif" } },
            on_complete = function(results) completed = results end,
        }
        pump(scheduled)
        assert.is_not_nil(completed)
        assert.is_nil(completed[11], "a truncated body must not arrive as a result")
    end)

    it("a chunked body missing its terminating chunk fails", function()
        local sockets = {}
        local env, scheduled = make_env(sockets, {
            script = { deliveries = {
                { line = "HTTP/1.1 200 OK" },
                { line = "transfer-encoding: chunked" },
                { line = "" },
                { line = "5" },
                { data = "abcde" },
                { line = "" },
                { eof = true },
            } },
        })
        local fetcher = asyncimage.new(env)
        local completed
        fetcher:start{
            tasks = { { uid = 12, src = "https://fi.fixture.invalid/unchunked.png" } },
            on_complete = function(results) completed = results end,
        }
        pump(scheduled)
        assert.is_not_nil(completed)
        assert.is_nil(completed[12])
    end)
end)

-- ---------------------------------------------------------------------------
-- The scheduler
-- ---------------------------------------------------------------------------

describe("asyncimage scheduler", function()
    local function stub_env(opts)
        local scheduled = {}
        local env, _ = make_env({}, {
            now = opts and opts.now or function() return 1000 end,
            select_fn = opts and opts.select_fn or function(recvt) return recvt, {} end,
        })
        env.schedule_fn = function(delay, fn)
            scheduled[#scheduled + 1] = fn
        end
        return env, scheduled
    end

    it("resumes only sockets select reports ready", function()
        local resumed = 0
        local sock = new_socket({})
        local never_ready = function() return {}, {} end
        local env, scheduled = stub_env({ select_fn = never_ready })
        local fetcher = asyncimage.new(env)
        fetcher:start{
            tasks = { { uid = 1, src = "https://x.invalid/a" } },
            fetch = function()
                coroutine.yield(sock, "r")
                resumed = resumed + 1
                return true, "body"
            end,
            on_complete = function() end,
        }
        assert.equals(0, resumed, "a not-ready socket must not be resumed")
        fire(scheduled)
        assert.equals(0, resumed)
    end)

    it("caps simultaneous fetches at the concurrency limit", function()
        local in_flight, max_in_flight = 0, 0
        local function stub_fetch()
            in_flight = in_flight + 1
            max_in_flight = math.max(max_in_flight, in_flight)
            coroutine.yield(new_socket({}), "r")
            in_flight = in_flight - 1
            return true, "body"
        end
        local env, scheduled = stub_env({})
        local fetcher = asyncimage.new(env)
        fetcher:start{
            tasks = {
                { uid = 1, src = "https://x.invalid/1" },
                { uid = 2, src = "https://x.invalid/2" },
                { uid = 3, src = "https://x.invalid/3" },
            },
            fetch = stub_fetch,
            concurrency = 2,
            on_complete = function() end,
        }
        fire(scheduled)
        fire(scheduled)
        assert.equals(2, max_in_flight, "concurrency cap was exceeded")
    end)

    it("cancels: closes sockets, stops scheduling, never completes", function()
        local sock = new_socket({})
        local cancelled = false
        local completed = false
        -- A never-ready select parks the fetch at its first yield so the
        -- cancel path is what ends the batch.
        local never_ready = function() return {}, {} end
        local env, scheduled = stub_env({ select_fn = never_ready })
        local fetcher = asyncimage.new(env)
        fetcher:start{
            tasks = { { uid = 1, src = "https://x.invalid/a" } },
            fetch = function()
                coroutine.yield(sock, "r")
                return true, "body"
            end,
            is_cancelled = function() return cancelled end,
            on_complete = function() completed = true end,
        }
        cancelled = true
        pump(scheduled)
        assert.is_true(sock.closed, "cancel must close the socket")
        assert.is_false(completed, "cancel must not fire on_complete")
        assert.equals(0, #scheduled, "cancel must stop scheduling")
    end)

    it("enforces the per-fetch deadline", function()
        local sock = new_socket({})
        local t = 1000
        local completed
        local never_ready = function() return {}, {} end
        local env, scheduled = stub_env({
            select_fn = never_ready,
            now = function() return t end,
        })
        local fetcher = asyncimage.new(env)
        fetcher:start{
            tasks = { { uid = 1, src = "https://x.invalid/a" } },
            fetch = function()
                coroutine.yield(sock, "r")
                return true, "body"
            end,
            deadline_s = 10,
            on_complete = function(results) completed = results end,
        }
        t = 1020
        pump(scheduled)
        assert.is_true(sock.closed, "deadline must close the socket")
        assert.is_not_nil(completed, "deadline ends the batch")
        assert.is_nil(completed[1])
    end)

    it("aggregates successes and failures into one completion", function()
        local completed
        local env, scheduled = stub_env({})
        local fetcher = asyncimage.new(env)
        local outcomes = { [1] = { true, "one" }, [2] = { false, "HTTP error 500" } }
        fetcher:start{
            tasks = {
                { uid = 1, src = "https://x.invalid/1" },
                { uid = 2, src = "https://x.invalid/2" },
            },
            fetch = function(url)
                coroutine.yield(new_socket({}), "r")
                local outcome = outcomes[tonumber(url:match("/(%d)$"))]
                return outcome[1], outcome[2]
            end,
            on_complete = function(results) completed = results end,
        }
        pump(scheduled)
        assert.is_not_nil(completed)
        assert.equals("one", completed[1])
        assert.is_nil(completed[2])
    end)

    it("drops a coroutine that errors and still completes the batch", function()
        -- The hang class this module exists to prevent: an errored fetch
        -- must vanish, not park the scheduler forever.
        local completed
        local env, scheduled = stub_env({})
        local fetcher = asyncimage.new(env)
        fetcher:start{
            tasks = { { uid = 1, src = "https://x.invalid/broken" } },
            fetch = function()
                coroutine.yield(new_socket({}), "r")
                error("boom")
            end,
            on_complete = function(results) completed = results end,
        }
        pump(scheduled)
        assert.is_not_nil(completed, "an errored coroutine must not hang the batch")
        assert.is_nil(completed[1])
    end)
end)
