require("spec.stubs")

local config = require("saforums.config")
local session = require("saforums.session")
local socketutil_stub = require("socketutil")
local https_stub = require("ssl.https")

-- default_transport is the real on-device transport; these tests run it
-- against the https/socketutil fakes so the request table it builds is
-- pinned. The GET case is the regression the first device pass caught: a
-- GET that carries a body source fails inside LuaSocket's protected
-- wrapper as a silent (nil, error) and reads as a network error.

describe("default_transport", function()
    before_each(function()
        https_stub.requests = {}
        socketutil_stub.calls = {}
        https_stub.respond = function()
            return 1, 200, { ["x-fixture"] = "1" }
        end
    end)

    it("sends a GET with no body source and returns code, headers, body", function()
        local code, headers, body = session.default_transport({
            method = "GET",
            url = "https://forums.fixture.invalid/index.php?json=1",
            headers = { ["cookie"] = "bbuserid=1" },
        })
        assert.equals(200, code)
        assert.equals("1", headers["x-fixture"])
        assert.equals("", body)
        local sent = https_stub.requests[1]
        assert.is_nil(sent.source)
        assert.is_false(sent.redirect)
        assert.is_nil(sent.headers["content-length"])
    end)

    it("gives POSTs a body source and content-length", function()
        session.default_transport({
            method = "POST",
            url = "https://forums.fixture.invalid/account.php?json=1",
            headers = {},
            body = "field=value",
        })
        local sent = https_stub.requests[1]
        assert.is_not_nil(sent.source)
        assert.equals("11", sent.headers["content-length"])
    end)

    it("wraps the request in the socketutil timeout idiom", function()
        session.default_transport({ method = "GET", url = "https://f.invalid/" })
        assert.same({
            { "set_timeout", config.request_block_timeout, config.request_total_timeout },
            { "reset_timeout" },
        }, socketutil_stub.calls)
    end)

    it("surfaces LuaSocket's protected errors as (nil, message)", function()
        https_stub.respond = function()
            return nil, "wantread"
        end
        local code, err = session.default_transport({
            method = "GET",
            url = "https://f.invalid/",
        })
        assert.is_nil(code)
        assert.equals("wantread", err)
    end)

    it("build_https_request leaves the caller's sink table live", function()
        local sink = {}
        local request = session.build_https_request({
            method = "POST",
            url = "https://f.invalid/",
            headers = {},
            body = "abc",
        }, sink)
        assert.not_nil(request.sink)
        -- ltn12's string source yields the whole body, then stops.
        local first = request.source()
        assert.equals("abc", first)
        assert.is_nil(request.source())
    end)
end)
