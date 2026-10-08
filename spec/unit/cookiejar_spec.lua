require("spec.stubs")

local config = require("saforums.config")
local cookiejar = require("saforums.cookiejar")

describe("cookiejar", function()
    describe("split_set_cookie", function()
        it("keeps a single header whole", function()
            local parts = cookiejar.split_set_cookie("bbuserid=123; expires=Wed, 21 Oct 2026 07:28:00 GMT; path=/")
            assert.equals(1, #parts)
        end)

        it("splits comma-joined headers without cutting Expires dates", function()
            local joined = "bbuserid=123; expires=Wed, 21 Oct 2026 07:28:00 GMT; path=/, " ..
                "bbpassword=abc; expires=Thu, 22 Oct 2026 07:28:00 GMT; path=/"
            local parts = cookiejar.split_set_cookie(joined)
            assert.equals(2, #parts)
            assert.matches("^bbuserid=123", parts[1])
            assert.matches("^bbpassword=abc", parts[2])
        end)

        it("does not split inside quoted values", function()
            local parts = cookiejar.split_set_cookie('weird="a,b=c", next=1')
            assert.equals(2, #parts)
        end)
    end)

    describe("parse_set_cookie", function()
        it("extracts name, value, and the attributes we keep", function()
            local cookie = cookiejar.parse_set_cookie(
                "bbuserid=123; expires=Wed, 21 Oct 2026 07:28:00 GMT; path=/; domain=.somethingawful.com; HttpOnly")
            assert.equals("bbuserid", cookie.name)
            assert.equals("123", cookie.value)
            assert.equals("/", cookie.path)
            assert.equals(".somethingawful.com", cookie.domain)
            assert.equals("Wed, 21 Oct 2026 07:28:00 GMT", cookie.expires)
        end)

        it("unwraps quoted values", function()
            local cookie = cookiejar.parse_set_cookie('token="a b"')
            assert.equals("a b", cookie.value)
        end)
    end)

    describe("jar", function()
        local jar

        before_each(function()
            jar = cookiejar.new()
            jar:store({
                ["set-cookie"] = "bbuserid=123; path=/, bbpassword=hash; path=/, __cf_bm=cfstuff; path=/",
            })
        end)

        it("stores cookies keyed by name", function()
            assert.equals("123", jar:get("bbuserid"))
            assert.equals("hash", jar:get("bbpassword"))
        end)

        it("reports session validity by bbuserid presence", function()
            assert.is_true(jar:has_session())
            local empty = cookiejar.new()
            assert.is_false(empty:has_session())
        end)

        it("builds a sorted Cookie header", function()
            local header = jar:header()
            assert.equals("__cf_bm=cfstuff; bbpassword=hash; bbuserid=123", header)
        end)

        it("clears the session but keeps Cloudflare clearance", function()
            jar:clear_session()
            assert.is_nil(jar:get("bbuserid"))
            assert.is_nil(jar:get("bbpassword"))
            assert.equals("cfstuff", jar:get("__cf_bm"))
            assert.is_false(jar:has_session())
        end)

        it("round-trips through a plain table for settings persistence", function()
            local restored = cookiejar.new()
            restored:load(jar:to_table())
            assert.equals("123", restored:get("bbuserid"))
            assert.equals("hash", restored:get("bbpassword"))
        end)

        it("accepts set-cookie as a list of headers too", function()
            local other = cookiejar.new()
            other:store({ ["set-cookie"] = { "bbuserid=9; path=/", "bbpassword=h; path=/" } })
            assert.equals("9", other:get("bbuserid"))
        end)

        it("never treats a missing header as an error", function()
            local empty = cookiejar.new()
            empty:store({})          -- no set-cookie at all
            empty:store(nil)
            assert.is_false(empty:has_session())
        end)
    end)

    describe("config", function()
        it("names the session cookies the site actually sets", function()
            assert.equals("bbuserid", config.session_user_cookie)
            assert.equals("bbpassword", config.session_password_cookie)
        end)

        it("keeps the UA honest", function()
            assert.matches("^saforums%.koplugin/", config.user_agent())
        end)

        it("stays in lockstep with the VERSION file", function()
            local version = io.open("VERSION", "r"):read("*l")
            assert.equals(version, config.version)
        end)
    end)
end)
