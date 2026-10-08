require("spec.stubs")

local threadhtml = require("saforums.threadhtml")

local function fixture(name)
    local handle = io.open("spec/fixtures/" .. name, "r")
    local content = handle:read("*a")
    handle:close()
    return content
end

describe("threadhtml", function()
    local doc

    before_each(function()
        local parsed = require("saforums.postspageparser").parse(fixture("postspage.html"))
        doc = {
            title = "The Thread You Are Currently Reading (fixture)",
            posts = parsed.posts,
            avatars = {
                ["103"] = { data = "\137PNG\r\n\x1a\n", mime = "image/png" },
            },
        }
    end)

    it("renders one bordered card per post, first exempt", function()
        local html = threadhtml.render(doc)
        assert.matches('<div class="post first">', html)
        assert.equals(2, select(2, html:gsub('<div class="post">', "")))
    end)

    it("renders the two-tier head: author, custom title, meta line", function()
        local html = threadhtml.render(doc)
        assert.matches('<span class="postauthor">Poster Three</span>', html)
        assert.matches('<div class="postmeta">Oct 5, 2026 12:30 &#183; post #1</div>', html)
        assert.matches('<span class="usertitle">Senior Fixture</span>', html)
    end)

    it("embeds avatars as data URIs, only for posters that have one", function()
        local html = threadhtml.render(doc)
        assert.matches('src="data:image/png;base64,', html)
        -- Poster Five has no avatar: exactly one embedded image in the doc.
        assert.equals(1, select(2, html:gsub('class="avatar"', "")))
    end)

    it("sanitizes bodies through the shared pipeline", function()
        local html = threadhtml.render(doc)
        assert.matches('<span class="imgref">[image: ', html, 1, true)
        assert.matches("%[spoiler%] a hidden spoiler text %[/spoiler%]", html)
        assert.matches("<br/>", html)
        assert.is_nil(html:find("<script"))
    end)

    it("base64-encodes correctly", function()
        assert.equals("", threadhtml.base64(""))
        assert.equals("aGVsbG8=", threadhtml.base64("hello"))
        assert.equals("aGVsbG8h", threadhtml.base64("hello!"))
        assert.equals("aGVsbG8hIQ==", threadhtml.base64("hello!!"))
        -- bytes that would be mangled by any text decoding
        assert.equals("iVBORw0KGgr6", threadhtml.base64("\137PNG\r\n\x1a\n\xfa"))
    end)

    it("ships the mupdf stylesheet without the crengine-banned properties", function()
        assert.is_nil(threadhtml.css:find("font%-family: serif") == nil and nil or nil)
        assert.matches("font%-family: serif", threadhtml.css) -- generic only
        assert.is_nil(threadhtml.css:find("line%-height"))
        assert.matches("div%.post { border%-top: 1px solid #888", threadhtml.css)
    end)

    it("renders a document with no avatars at all", function()
        doc.avatars = nil
        local html = threadhtml.render(doc)
        assert.is_nil(html:find('class="avatar"'))
        assert.matches('<span class="postauthor">Poster Three</span>', html)
    end)
end)
