require("spec.stubs")

-- Real filesystem for the books; DocSettings/ReadHistory/ReadCollection are
-- stubbed recorders so the sidecar-cleanup contract is observable.
local recorder = { purged = {}, history_removed = {}, collection_removed = {} }
package.preload["docsettings"] = function()
    return { open = function(_, path)
        return { purge = function() recorder.purged[#recorder.purged + 1] = path end }
    end }
end
package.preload["readhistory"] = function()
    return {
        removeItemByPath = function(_, path) recorder.history_removed[#recorder.history_removed + 1] = path end,
    }
end
package.preload["readcollection"] = function()
    return {
        removeItem = function(_, path) recorder.collection_removed[#recorder.collection_removed + 1] = path end,
    }
end

local lfs = require("lfs")
package.preload["libs/libkoreader-lfs"] = function()
    return require("lfs")
end

local retention = require("saforums.retention")

describe("retention", function()
    local dir

    before_each(function()
        recorder.purged, recorder.history_removed, recorder.collection_removed = {}, {}, {}
        dir = os.tmpname()
        os.remove(dir)
        lfs.mkdir(dir)
        -- Five books, aged minutes apart; one stray non-epub that must be ignored.
        for i = 1, 5 do
            local path = dir .. string.format("/thread-%d.epub", i)
            local handle = io.open(path, "w")
            handle:write("x")
            handle:close()
            lfs.touch(path, 1700000000 + i * 60)
        end
        local stray = io.open(dir .. "/avatars-x", "w")
        stray:write("x")
        stray:close()
    end)

    after_each(function()
        for name in lfs.dir(dir) do
            if name ~= "." and name ~= ".." then
                os.remove(dir .. "/" .. name)
            end
        end
        os.remove(dir)
    end)

    it("deletes the oldest books beyond the cap", function()
        local deleted = retention.enforce(dir, 3)
        assert.equals(2, deleted)
        assert.is_nil(lfs.attributes(dir .. "/thread-1.epub", "mode"))
        assert.is_nil(lfs.attributes(dir .. "/thread-2.epub", "mode"))
        assert.is_not_nil(lfs.attributes(dir .. "/thread-3.epub", "mode"))
        assert.is_not_nil(lfs.attributes(dir .. "/thread-5.epub", "mode"))
    end)

    it("cleans sidecars, history, and collection for each deleted book", function()
        local deleted = retention.enforce(dir, 3)
        assert.same({ dir .. "/thread-1.epub", dir .. "/thread-2.epub" }, recorder.purged)
        assert.equals(2, #recorder.history_removed)
        assert.equals(2, #recorder.collection_removed)
    end)

    it("does nothing when the shelf is within the cap", function()
        assert.equals(0, retention.enforce(dir, 10))
        assert.equals(0, #recorder.purged)
    end)

    it("survives a missing directory and a zero cap", function()
        assert.equals(0, retention.enforce("/tmp/definitely-not-here-9x", 10))
        assert.equals(0, retention.enforce(dir, 0))
    end)
end)
