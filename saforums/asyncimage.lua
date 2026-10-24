--[[
Background image fetching: non-blocking HTTPS GETs driven between UIManager
ticks, plus the small coroutine scheduler that runs them.

Nothing here may block the UI thread: every socket operation runs in
timeout-0 mode and the fetch coroutines yield when they would block; the
driver only resumes coroutines whose sockets socket.select reports ready.
A blocking fetch anywhere on this path froze e-ink devices (v0.5.1).

The non-blocking primitives and the HTTP request/response handling are
adapted from KOReader's frontend/httpasync.lua (upstream master 2adaff6,
2026-10), which ships only after this plugin's v2026.03 API floor. Both
sides are AGPL-3.0; the adaptation is marked below.

DNS resolution is the one residual blocking call: glibc getaddrinfo runs
before the non-blocking connect regime applies, once per host per process
(glibc caches afterwards). The thread page fetch has always had the same
exposure. These requests never carry cookies (spec: cookies are
credentials, and image hosts are not all first-party).

The environment (socket, ssl, url parser, select, scheduler, clock) is
injectable per instance so busted drives everything synchronously; the
defaults are KOReader's bundled modules and UIManager:scheduleIn.
]]

local config = require("saforums.config")
local logger = require("logger")

local asyncimage = {}

local DONE = "saforums-asyncimage-done"
local MAX_REDIRECTS = 3
local DEFAULT_CONCURRENCY = 2
local DEFAULT_DEADLINE_S = 15
local DEFAULT_TICK_S = 0.1

--- Build an instance around an injectable environment.
function asyncimage.new(env)
    env = env or {}
    local self = {
        socket = env.socket or require("socket"),
        ssl = env.ssl or require("ssl"),
        url = env.url or require("socket.url"),
        schedule_fn = env.schedule_fn or function(delay, fn)
            require("ui/uimanager"):scheduleIn(delay, fn)
        end,
        now = env.now or os.time,
    }
    if env.select_fn then
        self.select_fn = env.select_fn
    else
        local socket_lib = self.socket
        self.select_fn = function(recvt, sendt)
            return socket_lib.select(recvt, sendt, 0)
        end
    end
    return setmetatable(self, { __index = asyncimage })
end

-- ---------------------------------------------------------------------------
-- Non-blocking primitives (adapted from KOReader's frontend/httpasync.lua)
-- ---------------------------------------------------------------------------

--- Non-blocking receive; yields (socket, "r"/"w") until data/error/EOF.
-- LuaSocket's receive(pattern, prefix) prepends `prefix` to the buffer it
-- reads into, so partial data already consumed on a timed-out call must be
-- passed back as the prefix on the next call; accumulated carries it so a
-- resumed receive continues exactly where it left off.
local function async_receive(sock, pattern)
    local accumulated = ""
    while true do
        local res, err, partial = sock:receive(pattern, accumulated)
        if err == "timeout" or err == "wantread" then
            accumulated = partial or accumulated
            coroutine.yield(sock, "r")
        elseif err == "wantwrite" then
            coroutine.yield(sock, "w")
        else
            return res, err, partial
        end
    end
end

--- Non-blocking send; yields (socket, "w"/"r") while it would block.
local function async_send(sock, data)
    local i = 1
    local n = #data
    while i <= n do
        local res, err, last = sock:send(data, i)
        if err == "timeout" or err == "wantwrite" then
            coroutine.yield(sock, "w")
            if last then i = last + 1 end
        elseif err == "wantread" then
            coroutine.yield(sock, "r")
        elseif err then
            return nil, err
        else
            i = res + 1
        end
    end
    return true
end

--- Non-blocking connect; yields (socket, "w") until connected or failed.
local function async_connect(sock, host, port)
    sock:settimeout(0)
    while true do
        local res, err = sock:connect(host, port)
        if res or err == "already connected" then
            return true
        elseif err == "timeout" or err == "Operation already in progress" then
            coroutine.yield(sock, "w")
        else
            return false, err
        end
    end
end

--- Non-blocking TLS handshake; yields (socket, "r"/"w") while it blocks.
local function async_handshake(sock)
    while true do
        local res, err = sock:dohandshake()
        if res then
            return true
        elseif err == "wantread" then
            coroutine.yield(sock, "r")
        elseif err == "wantwrite" then
            coroutine.yield(sock, "w")
        else
            return false, err
        end
    end
end

-- ---------------------------------------------------------------------------
-- One fetch, as a coroutine (HTTP handling adapted from httpasync.lua)
-- ---------------------------------------------------------------------------

--- Fetch one URL over a raw non-blocking socket, yielding while it would
--- block. Returns (true, body) or (false, err). Sends no cookies.
function asyncimage:fetch(url, redirect_count)
    redirect_count = redirect_count or 0
    if redirect_count > MAX_REDIRECTS then
        return false, "too many redirects"
    end

    local parsed = self.url.parse(url)
    if not parsed or not parsed.host then
        return false, "invalid url"
    end
    local host = parsed.host
    local port = parsed.port or (parsed.scheme == "https" and 443 or 80)
    local path = parsed.path or "/"
    if parsed.query then
        path = path .. "?" .. parsed.query
    end

    local sock = self.socket.tcp()
    local ok, err = async_connect(sock, host, port)
    if not ok then
        sock:close()
        return false, "connect error: " .. tostring(err)
    end

    if parsed.scheme == "https" then
        local ssl_sock, wrap_err = self.ssl.wrap(sock, {
            mode = "client",
            protocol = "any",
            verify = "none",
            options = { "all", "no_sslv2", "no_sslv3" },
        })
        if not ssl_sock then
            sock:close()
            return false, "ssl wrap error: " .. tostring(wrap_err)
        end
        sock = ssl_sock
        sock:settimeout(0)
        if sock.sni then
            sock:sni(host)
        end
        local hok, herr = async_handshake(sock)
        if not hok then
            sock:close()
            return false, "ssl handshake error: " .. tostring(herr)
        end
    end

    local req = table.concat({
        "GET " .. path .. " HTTP/1.1",
        "Host: " .. host,
        "User-Agent: " .. config.user_agent(),
        "Accept: image/*",
        "Connection: close",
        "",
        "",
    }, "\r\n")
    local sok, serr = async_send(sock, req)
    if not sok then
        sock:close()
        return false, "send error: " .. tostring(serr)
    end

    local resp_headers = {}
    local status_line
    while true do
        local line, lerr = async_receive(sock, "*l")
        if not line then
            sock:close()
            return false, "read error: " .. tostring(lerr)
        end
        if line == "" then break end
        if not status_line then
            status_line = line
        else
            local k, v = line:match("^(.-):%s*(.*)")
            if k and v then resp_headers[k:lower()] = v end
        end
    end
    if not status_line then
        sock:close()
        return false, "no status line received"
    end
    local code = tonumber(status_line:match("HTTP/%d%.%d%s+(%d%d%d)"))

    if code and code >= 300 and code < 400 and resp_headers["location"] then
        sock:close()
        local new_url = self.url.absolute(url, resp_headers["location"]:gsub("\r$", ""))
        return self:fetch(new_url, redirect_count + 1)
    end
    if code and code >= 400 then
        sock:close()
        return false, "HTTP error " .. tostring(code)
    end

    local body = {}
    -- A short body must fail, never cache: avatar files live forever, so
    -- half an image stored as a success would corrupt that poster's face
    -- on every future render.
    local body_complete = false
    local transfer_encoding = resp_headers["transfer-encoding"]
    if transfer_encoding and transfer_encoding:lower():find("chunked", 1, true) then
        while true do
            local size_line = async_receive(sock, "*l")
            if not size_line then break end
            local chunk_size = tonumber(size_line:match("^%x+"), 16)
            if not chunk_size or chunk_size == 0 then
                if chunk_size == 0 then body_complete = true end
                break
            end
            local chunk_data = async_receive(sock, chunk_size)
            if chunk_data and #chunk_data > 0 then
                body[#body + 1] = chunk_data
            end
            async_receive(sock, 2) -- trailing CRLF
        end
    else
        local content_length = tonumber(resp_headers["content-length"])
        if content_length then
            local received = 0
            while received < content_length do
                local chunk = async_receive(sock, content_length - received)
                if not chunk then break end
                body[#body + 1] = chunk
                received = received + #chunk
            end
            body_complete = received >= content_length
        else
            -- No length promised: EOF is the body's natural end.
            while true do
                local chunk, cerr, partial = async_receive(sock, 8192)
                if chunk then
                    body[#body + 1] = chunk
                else
                    if partial and #partial > 0 then
                        body[#body + 1] = partial
                    end
                    if cerr == "closed" then break end
                    if cerr ~= "timeout" and cerr ~= "wantread" then break end
                end
            end
            body_complete = true
        end
    end

    sock:close()
    if not body_complete then
        return false, "truncated body"
    end
    return true, table.concat(body)
end

-- ---------------------------------------------------------------------------
-- Tick scheduler: resumes ready fetch coroutines between event-loop ticks
-- ---------------------------------------------------------------------------

--- Start a batch of fetches. One batch per instance: a second start()
--- would orphan the first batch's sockets, and ui.lua news an instance
--- per thread open. opts:
---   tasks         { { uid = ..., src = url }, ... }
---   on_complete   function(results) with results[uid] = body or nil
---   is_cancelled function() -> bool, checked every tick (closes sockets)
---   fetch         override the fetch coroutine body (tests)
---   concurrency   max simultaneous fetches (default 2)
---   deadline_s    per-fetch wall-clock budget (default 15)
---   tick_s        delay between ticks (default 0.1)
function asyncimage:start(opts)
    local fetch_fn = opts.fetch or function(url)
        return self:fetch(url, 0)
    end
    local tasks = {}
    for _, task in ipairs(opts.tasks or {}) do
        tasks[#tasks + 1] = { uid = task.uid, src = task.src }
    end
    local state = {
        opts = opts,
        fetch_fn = fetch_fn,
        pending = tasks,
        active = {},   -- { { co, sock, mode, task, started } }
        results = {},
        scheduled = false,
    }
    self._state = state
    self:_tick()
    return self
end

function asyncimage:_schedule_next()
    local state = self._state
    if state.scheduled then return end
    state.scheduled = true
    local interval = state.opts.tick_s or DEFAULT_TICK_S
    self.schedule_fn(interval, function()
        state.scheduled = false
        self:_tick()
    end)
end

function asyncimage:_close_sockets()
    for _, entry in ipairs(self._state.active) do
        if entry.sock then
            pcall(function() entry.sock:close() end)
        end
    end
end

function asyncimage:_tick()
    local state = self._state
    if not state then return end

    if state.opts.is_cancelled and state.opts.is_cancelled() then
        self:_close_sockets()
        state.active, state.pending = {}, {}
        self._state = nil
        return
    end

    local now = self.now()
    local deadline = state.opts.deadline_s or DEFAULT_DEADLINE_S
    local survivors = {}
    for _, entry in ipairs(state.active) do
        if now - entry.started > deadline then
            logger.warn("saforums: background image fetch timed out for", entry.task.src)
            pcall(function() entry.sock:close() end)
            state.results[entry.task.uid] = nil
        else
            survivors[#survivors + 1] = entry
        end
    end
    state.active = survivors

    -- Fill the pool with new fetches.
    local concurrency = state.opts.concurrency or DEFAULT_CONCURRENCY
    while #state.active < concurrency and #state.pending > 0 do
        local task = table.remove(state.pending, 1)
        local co = coroutine.create(function()
            local ok, body = state.fetch_fn(task.src)
            if not ok then
                logger.warn("saforums: background image fetch failed:", task.src, body)
            end
            coroutine.yield(DONE, task, ok, body)
        end)
        state.active[#state.active + 1] = {
            co = co,
            sock = nil,
            mode = nil,
            task = task,
            started = now,
        }
    end

    -- Resume every coroutine that is ready (or has not yielded a socket yet).
    local recvt, sendt = {}, {}
    for _, entry in ipairs(state.active) do
        if entry.sock then
            if entry.mode == "r" then recvt[#recvt + 1] = entry.sock end
            if entry.mode == "w" then sendt[#sendt + 1] = entry.sock end
        end
    end
    local ready = {}
    if #recvt > 0 or #sendt > 0 then
        local r, w = self.select_fn(recvt, sendt)
        for _, s in ipairs(r or {}) do ready[s] = true end
        for _, s in ipairs(w or {}) do ready[s] = true end
    end

    local still_active = {}
    for _, entry in ipairs(state.active) do
        if entry.sock and not ready[entry.sock] then
            still_active[#still_active + 1] = entry
        else
            local last_sock = entry.sock
            entry.sock, entry.mode = nil, nil
            -- A resumed coroutine yields either its socket and mode
            -- ("r"/"w", still working) or the DONE sentinel, the task,
            -- and the fetch result.
            local ok, first, second, third, fourth = coroutine.resume(entry.co)
            if not ok then
                logger.warn("saforums: background fetch coroutine error:", first)
                if last_sock then
                    pcall(function() last_sock:close() end)
                end
            elseif first == DONE then
                local task, fetch_ok, body = second, third, fourth
                if fetch_ok and body and #body > 0 then
                    state.results[task.uid] = body
                else
                    state.results[task.uid] = nil
                end
            elseif coroutine.status(entry.co) == "dead" then
                state.results[entry.task.uid] = nil
            else
                entry.sock, entry.mode = first, second
                still_active[#still_active + 1] = entry
            end
        end
    end
    state.active = still_active

    if #state.active == 0 and #state.pending == 0 then
        self._state = nil
        if state.opts.on_complete then
            state.opts.on_complete(state.results)
        end
        return
    end
    self:_schedule_next()
end

return asyncimage
