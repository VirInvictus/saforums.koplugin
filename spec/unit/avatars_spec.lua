require("spec.stubs")

-- The module wants KOReader's lfs; delegate the stub to the system one.
package.preload["libs/libkoreader-lfs"] = function()
    return require("lfs")
end

local lfs = require("lfs") -- system lfs is fine in tests; plugin uses libkoreader-lfs on device
local avatars = require("saforums.avatars")

local function fake_session()
    local s = { fetches = {} }
    function s:get(url, opts)
        s.fetches[#s.fetches + 1] = { url = url, opts = opts }
        if url:find("broken") then
            return { kind = "http_error", code = 404 }
        end
        return { kind = "ok", body = "\137PNG\r\n\x1a\n-fake-bytes" }
    end
    return s
end

describe("avatars", function()
    local dir

    before_each(function()
        dir = os.tmpname()
        os.remove(dir)
        lfs.mkdir(dir)
    end)

    after_each(function()
        os.remove(dir .. "/103.gif")
        os.remove(dir)
    end)

    it("maps source extensions to mime types", function()
        assert.equals("image/gif", avatars.mime_for("https://fi.invalid/a/103.gif"))
        assert.equals("image/jpeg", avatars.mime_for("https://fi.invalid/a/x.JPG?query=1"))
        assert.equals("image/png", avatars.mime_for("https://fi.invalid/a/mystery"))
    end)

    it("fetches on miss, stores raw bytes keyed by user id", function()
        local session = fake_session()
        local path = avatars.ensure(dir, session, "103", "https://fi.fixture.invalid/avatars/103.gif")
        assert.equals(dir .. "/103.gif", path)
        local handle = io.open(path, "rb")
        local bytes = handle:read("*a")
        handle:close()
        assert.equals("\137PNG\r\n\x1a\n-fake-bytes", bytes)
        assert.is_true(session.fetches[1].opts.raw)
    end)

    it("serves repeat posters from cache without fetching", function()
        local session = fake_session()
        local first = avatars.ensure(dir, session, "103", "https://fi.fixture.invalid/avatars/103.gif")
        local second = avatars.ensure(dir, session, "103", "https://fi.fixture.invalid/avatars/103.gif")
        assert.equals(first, second)
        assert.equals(1, #session.fetches)
    end)

    it("returns nil on fetch failure without writing a cache entry", function()
        local session = fake_session()
        local path = avatars.ensure(dir, session, "9", "https://fi.fixture.invalid/broken/9.gif")
        assert.is_nil(path)
        assert.is_nil(lfs.attributes(dir .. "/9.gif", "mode"))
    end)

    it("returns nil politely when there is nothing to fetch", function()
        local session = fake_session()
        assert.is_nil(avatars.ensure(dir, session, nil, "https://fi.fixture.invalid/x.gif"))
        assert.is_nil(avatars.ensure(dir, session, "103", nil))
        assert.equals(0, #session.fetches)
    end)
end)

describe("avatars fetch-budget filter", function()
    it("keeps real avatars, drops custom-title art and post icons", function()
        assert.is_truthy(avatars.is_avatar_candidate("https://fi.somethingawful.com/avatars/103.gif"))
        assert.is_truthy(avatars.is_avatar_candidate("https://i.somethingawful.com/images/u/x.png"))
        assert.is_false(avatars.is_avatar_candidate("https://fi.somethingawful.com/customtitles/title-x.gif"))
        assert.is_false(avatars.is_avatar_candidate("https://fi.somethingawful.com/posticons/7.gif"))
        assert.is_false(avatars.is_avatar_candidate(nil))
    end)
end)
