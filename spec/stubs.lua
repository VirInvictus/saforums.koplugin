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
