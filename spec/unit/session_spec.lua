require("spec.stubs")

local config = require("saforums.config")
local session = require("saforums.session")

local function fixture(name)
    local handle = io.open("spec/fixtures/" .. name, "r")
    local content = handle:read("*a")
    handle:close()
    return content
end

-- Scripted transport: pops a canned response per request and records every
-- request it saw. A response is { code, headers, body } or { error }.
local function fake_transport(script)
    local transport = {
        requests = {},
        script = script or {},
    }
    function transport.request(request)
        transport.requests[#transport.requests + 1] = {
            method = request.method,
            url = request.url,
            headers = request.headers,
            body = request.body,
        }
        local response = table.remove(transport.script, 1)
            or { code = 200, headers = {}, body = "" }
        if response.error then
            return nil, response.error
        end
        return response.code, response.headers, response.body
    end
    return transport
end

describe("session", function()
    describe("multipart bodies", function()
        it("encodes fields with the boundary and 1252 values", function()
            local body = session.multipart_body({ action = "login", username = "caf\xC3\xA9" })
            assert.matches("%-%-saforums%-form%-boundary%-7f3a9c", body)
            assert.matches('name="action"', body)
            assert.matches("caf\xE9", body) -- UTF-8 é became the 1252 byte
        end)
    end)

    describe("url handling", function()
        it("resolves absolute and relative redirects", function()
            assert.equals("https://f.invalid/a",
                session.resolve_url("https://f.invalid/x/y", "/a"))
            assert.equals("https://f.invalid/x/b",
                session.resolve_url("https://f.invalid/x/y", "b"))
            assert.equals("https://other.invalid/z",
                session.resolve_url("https://f.invalid/x/y", "https://other.invalid/z"))
        end)

        it("restores perpage on showthread redirects only", function()
            assert.equals(
                "https://f.invalid/showthread.php?threadid=1&pagenumber=2&perpage=40",
                session.restore_perpage("https://f.invalid/showthread.php?threadid=1&pagenumber=2"))
            assert.equals(
                "https://f.invalid/showthread.php?threadid=1&perpage=50",
                session.restore_perpage("https://f.invalid/showthread.php?threadid=1&perpage=50"))
            assert.equals(
                "https://f.invalid/forumdisplay.php?forumid=1",
                session.restore_perpage("https://f.invalid/forumdisplay.php?forumid=1"))
        end)
    end)

    describe("requests", function()
        it("sends the honest UA and cookies, and stores new ones", function()
            local transport = fake_transport({
                { code = 200, headers = { ["set-cookie"] = "bbuserid=123; path=/" }, body = "ok" },
            })
            local s = session.new(transport.request)
            local result = s:get(config.base_url .. "/index.php")

            assert.equals("ok", result.kind)
            assert.equals(config.user_agent(), transport.requests[1].headers["user-agent"])
            assert.is_true(s:has_session())
        end)

        it("follows redirects and re-injects perpage", function()
            local transport = fake_transport({
                { code = 302, headers = { location = "/showthread.php?threadid=4231003&pagenumber=2" }, body = "" },
                { code = 200, headers = {}, body = "the page" },
            })
            local s = session.new(transport.request)
            local result = s:get("https://f.invalid/showthread.php?threadid=4231003&goto=newpost")

            assert.equals("ok", result.kind)
            assert.equals(2, #transport.requests)
            assert.matches("perpage=40", transport.requests[2].url)
            assert.equals("the page", result.body)
        end)

        it("caps redirect chains", function()
            local script = {}
            for _ = 1, 10 do
                script[#script + 1] = { code = 302, headers = { location = "/loop" }, body = "" }
            end
            local s = session.new(fake_transport(script).request)
            local result = s:get("https://f.invalid/start")
            assert.equals("http_error", result.kind)
            assert.equals("too many redirects", result.error)
        end)

        it("detects Cloudflare challenges by header and by body", function()
            local by_header = fake_transport({
                { code = 403, headers = { ["cf-mitigated"] = "challenge" }, body = "" },
            })
            local s = session.new(by_header.request)
            assert.equals("cloudflare", s:get("https://f.invalid/").kind)

            local by_body = fake_transport({
                { code = 503, headers = {}, body = "<title>Just a moment...</title>challenges.cloudflare.com" },
            })
            local s2 = session.new(by_body.request)
            assert.equals("cloudflare", s2:get("https://f.invalid/").kind)
        end)

        it("treats a bbuserid flip as a remote logout", function()
            local transport = fake_transport({
                { code = 200, headers = { ["set-cookie"] = "bbuserid=123; path=/" }, body = "" },
                { code = 200, headers = { ["set-cookie"] = "bbuserid=; expires=Thu, 01 Jan 1970 00:00:00 GMT" }, body = "" },
            })
            local s = session.new(transport.request)
            s:get("https://f.invalid/")            -- logs in
            local result = s:get("https://f.invalid/t") -- session gone
            assert.equals("logged_out", result.kind)
            assert.is_false(s:has_session())
        end)

        it("surfaces transport errors without retrying", function()
            local transport = fake_transport({ { error = "timeout" } })
            local s = session.new(transport.request)
            local result = s:get("https://f.invalid/")
            assert.equals("transport_error", result.kind)
            assert.equals(1, #transport.requests)
        end)
    end)

    describe("login", function()
        it("posts the account.php contract and parses the JSON reply", function()
            local transport = fake_transport({
                { code = 200, headers = { ["set-cookie"] = "bbuserid=555; path=/, bbpassword=hash; path=/" },
                  body = fixture("login_success.json") },
            })
            local s = session.new(transport.request)
            local document = s:login("FixtureUser", "password")

            local request = transport.requests[1]
            assert.equals("POST", request.method)
            assert.matches("^multipart/form%-data; boundary=", request.headers["content-type"])
            assert.matches('name="action"', request.body)
            assert.matches("login", request.body)
            assert.matches('name="username"', request.body)
            assert.matches("FixtureUser", request.body)
            assert.matches('name="password"', request.body)
            assert.matches('name="next"', request.body)
            assert.matches("/index%.php%?json=1", request.body)

            assert.equals("FixtureUser", document.user.username)
            assert.equals("555", s:to_table().cookies.bbuserid.value)
        end)

        it("answers an HTML failure page with not_json, not a crash", function()
            local transport = fake_transport({
                { code = 200, headers = {}, body = "<html><body>Wrong Password</body></html>" },
            })
            local s = session.new(transport.request)
            local document, result = s:login("u", "bad")
            assert.is_nil(document)
            assert.equals("not_json", result.kind)
        end)
    end)

    describe("persistence", function()
        it("round-trips through a plain table", function()
            local transport = fake_transport({
                { code = 200, headers = { ["set-cookie"] = "bbuserid=9; path=/" }, body = "" },
            })
            local s = session.new(transport.request)
            s:get("https://f.invalid/")

            local restored = session.new()
            restored:load(s:to_table())
            assert.equals("9", restored:to_table().cookies.bbuserid.value)
            assert.is_true(restored:has_session())
        end)
    end)
end)

describe("raw fetches", function()
    it("leaves binary bodies undecoded when raw is set", function()
        local transport = fake_transport({
            { code = 200, headers = {}, body = "\137PNG\r\n\x1a\n" },
        })
        local s = session.new(transport.request)
        local result = s:get("https://f.invalid/avatar.gif", { raw = true })
        assert.equals("\137PNG\r\n\x1a\n", result.body)
    end)

    it("still decodes text bodies by default", function()
        local transport = fake_transport({
            { code = 200, headers = {}, body = "caf\xE9" },
        })
        local s = session.new(transport.request)
        local result = s:get("https://f.invalid/page")
        assert.equals("caf\xC3\xA9", result.body)
    end)
end)

describe("goto=newpost jump targets", function()
    it("keeps the #pti fragment as jump_index and off the wire", function()
        local transport = fake_transport({
            { code = 302, headers = { location = "/showthread.php?threadid=1&pagenumber=3#pti47" }, body = "" },
            { code = 200, headers = {}, body = "the page" },
        })
        local s = session.new(transport.request)
        local result = s:get("https://f.invalid/showthread.php?threadid=1&goto=newpost")

        assert.equals("ok", result.kind)
        assert.equals(47, result.jump_index)
        assert.equals(2, #transport.requests)
        assert.is_nil(transport.requests[2].url:find("#", 1, true)) -- fragment never sent
        assert.matches("perpage=40", transport.requests[2].url)
    end)

    it("leaves jump_index nil on plain fetches", function()
        local transport = fake_transport({
            { code = 200, headers = {}, body = "" },
        })
        local s = session.new(transport.request)
        assert.is_nil(s:get("https://f.invalid/t").jump_index)
    end)
end)

describe("cookie host scoping", function()
    it("rides only on the site's own hosts, never third-party ones", function()
        local transport = fake_transport({
            { code = 200, headers = {}, body = "ok" },
            { code = 200, headers = {}, body = "ok" },
        })
        local s = session.new(transport.request)
        s.jar:load({
            bbuserid = { value = "123", path = "/" },
            bbpassword = { value = "fixture-value", path = "/" },
        })

        s:get("https://img.thirdparty.invalid/pic.png")
        assert.is_nil(transport.requests[1].headers.cookie)

        s:get("https://fi.somethingawful.com/avatars/1.png")
        assert.matches("bbuserid=123", transport.requests[2].headers.cookie)
    end)

    it("classifies hosts by the site suffix", function()
        assert.is_truthy(session.carries_cookies(config.base_url .. "/index.php"))
        assert.is_truthy(session.carries_cookies("https://fi.somethingawful.com/x.png"))
        assert.is_false(session.carries_cookies("https://imgur.invalid/x.png"))
        assert.is_false(session.carries_cookies("https://notsomethingawful.com/x.png"))
    end)
end)
