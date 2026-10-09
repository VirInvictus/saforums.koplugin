--[[
Test environment bootstrap, required at the top of every spec file.

- Puts the vendored htmlparser (same pin as koreader-base) on the package path.
- Preloads no-op stand-ins for the KOReader modules pure-layer code touches.
- Replaces ffi/archiver with a recording fake so the EPUB builder is testable
  without KOReader's compiled zip library.
--]]

package.path = "spec/vendor/htmlparser/?.lua;" .. package.path

local function preload(name, module)
    package.preload[name] = function()
        return module
    end
end

preload("gettext", function(s)
    return s
end)

local logger = {}
for _, level in ipairs({ "dbg", "info", "warn", "err" }) do
    logger[level] = function() end
end
preload("logger", logger)

preload("ui/uimanager", {
    show = function() end,
    close = function() end,
    nextTick = function(_, fn) fn() end,
    setDirty = function() end,
    scheduleIn = function() end,
})

preload("ffi/util", {
    template = function(str, ...)
        local args = { ... }
        return (str:gsub("%%%d+", function(spec)
            local n = tonumber(spec:sub(2))
            return tostring(args[n])
        end))
    end,
})

-- Records every EPUB the builder writes, per instance, for assertions.
local FakeWriter = {}
FakeWriter.__index = FakeWriter
FakeWriter.instances = {}

function FakeWriter:new()
    local instance = setmetatable({
        entries = {},
        entry_compression = {},
        compression = "deflate",
        opened_path = nil,
        opened_kind = nil,
        closed = false,
    }, self)
    table.insert(self.instances, instance)
    return instance
end

function FakeWriter:open(path, kind)
    self.opened_path = path
    self.opened_kind = kind
    return true
end

function FakeWriter:setZipCompression(compression)
    self.compression = compression
end

function FakeWriter:addFileFromMemory(name, content)
    self.entries[name] = content
    self.entry_compression[name] = self.compression
    return true
end

function FakeWriter:close()
    self.closed = true
    return true
end

preload("ffi/archiver", { Writer = FakeWriter })

-- Transport fakes: default_transport requires these lazily, so specs can
-- exercise the real request-building path without a network.
local socketutil_stub = {
    calls = {},
    set_timeout = function(self, block, total)
        self.calls[#self.calls + 1] = { "set_timeout", block, total }
    end,
    reset_timeout = function(self)
        self.calls[#self.calls + 1] = { "reset_timeout" }
    end,
}
preload("socketutil", socketutil_stub)

local https_stub
https_stub = {
    requests = {},
    -- Default canned response; specs can override respond().
    respond = function()
        return 1, 200, {}
    end,
    -- saforums calls https.request(req) with a dot, matching LuaSec's
    -- request-table form, so the stub records positionally.
    request = function(req)
        https_stub.requests[#https_stub.requests + 1] = req
        return https_stub.respond()
    end,
}
preload("ssl.https", https_stub)
