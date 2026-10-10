require("spec.stubs")

local listcache = require("saforums.listcache")

describe("listcache", function()
    local clock, cache

    before_each(function()
        clock = 1000
        cache = listcache.new({}, function() return clock end)
    end)

    it("returns nil for absent keys", function()
        assert.is_nil(cache:get("forum:46"))
        assert.is_false(cache:fresh("forum:46", 900))
    end)

    it("serves fresh entries without a fetch", function()
        cache:put("forum:46", { threads = { "a" } })
        clock = clock + 899
        assert.is_truthy(cache:fresh("forum:46", 900))
        assert.equals("a", cache:get("forum:46").threads[1])
    end)

    it("reports stale after the ttl passes but keeps the data readable", function()
        cache:put("forum:46", { threads = { "a" } })
        clock = clock + 900
        assert.is_false(cache:fresh("forum:46", 900))
        -- stale-while-revalidate: the stale copy still renders
        assert.truthy(cache:get("forum:46"))
    end)

    it("stores nil-free data only: a nil put is not an entry", function()
        cache:put("forum:46", nil)
        assert.is_false(cache:fresh("forum:46", 900))
        assert.is_nil(cache:get("forum:46"))
    end)

    it("forget drops one key, forget_all drops everything", function()
        cache:put("a", 1)
        cache:put("b", 2)
        cache:forget("a")
        assert.is_nil(cache:get("a"))
        assert.equals(2, cache:get("b"))
        cache:forget_all()
        assert.is_nil(cache:get("b"))
    end)

    it("persists through the caller's table across instances", function()
        local store = {}
        local writer = listcache.new(store, function() return clock end)
        writer:put("forum:46", "cached")
        local reader = listcache.new(store, function() return clock end)
        assert.equals("cached", reader:get("forum:46"))
    end)
end)
