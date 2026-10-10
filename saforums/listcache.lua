--[[
List cache for the polite fetches (spec: Semantics > Politeness): forum
lists, bookmarks, the forums index, and announcement bodies render from
cache while fresh, and stale entries still render while a refetch runs
(stale-while-revalidate).

Entries are plain { data = ..., stored_at = ... } tables keyed by string;
the UI owns persistence (it saves the entry table into its settings and
hands it back on construction), so this module stays pure. The clock is
injectable for tests.
--]]

local listcache = {}

local Cache = {}
Cache.__index = Cache

--- entries: the persistent table (created fresh when nil).
--- now: function returning the current time in seconds (default os.time).
function listcache.new(entries, now)
    return setmetatable({
        entries = entries or {},
        now = now or os.time,
    }, Cache)
end

--- Data for key when an entry exists (fresh or stale; callers decide what
--- to do with stale data). nil when absent or the data itself is nil.
function Cache:get(key)
    local entry = self.entries[key]
    if entry and entry.data ~= nil then
        return entry.data
    end
    return nil
end

--- True when key has an entry younger than ttl seconds.
function Cache:fresh(key, ttl)
    local entry = self.entries[key]
    return entry ~= nil and entry.data ~= nil
        and (self.now() - entry.stored_at) < ttl
end

function Cache:put(key, data)
    self.entries[key] = { data = data, stored_at = self.now() }
end

function Cache:forget(key)
    self.entries[key] = nil
end

function Cache:forget_all()
    for key in pairs(self.entries) do
        self.entries[key] = nil
    end
end

return listcache
