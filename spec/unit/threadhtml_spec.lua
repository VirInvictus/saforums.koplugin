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
                ["103"] = "avatars/103.gif",
                ["104"] = "avatars/104.png",
            },
            last_page = true,
        }
    end)

    it("renders a fragment: one card per post, first exempt, seen tinted", function()
        local html = threadhtml.render(doc)
        assert.matches('^<div class="thread">', html)
        assert.matches("</div>$", html)
        assert.is_nil(html:find("<html>"))
        assert.is_nil(html:find("DOCTYPE"))
        -- posts 1 and 2 are seen in the fixture; post 3 is not
        assert.matches('<div class="post first seen">', html)
        assert.matches('<div class="post seen">', html)
        assert.equals(1, select(2, html:gsub('<div class="post">', "")))
    end)

    it("renders the Awful header: avatar, name, custom title, date, regdate", function()
        local html = threadhtml.render(doc)
        assert.matches('<img class="avatar" src="avatars/103%.gif"', html)
        assert.matches('<div class="username">Poster Three', html)
        assert.matches('<span class="usertitle">Senior Fixture</span>', html)
        assert.matches('Oct 5, 2026 12:30', html)
        assert.matches('&#183; post #1', html)
        assert.matches('<div class="regdate">joined Mar 12, 2011</div>', html)
    end)

    it("badges the original poster exactly once", function()
        local html = threadhtml.render(doc)
        assert.matches('Poster Five', html)
        assert.matches('<span class="opbadge">OP</span>', html)
        assert.equals(1, select(2, html:gsub('class="opbadge"', "")))
    end)

    it("references avatars by resource-relative path, only for posters that have one", function()
        local html = threadhtml.render(doc)
        assert.matches('src="avatars/103%.gif"', html)
        assert.equals(2, select(2, html:gsub('class="avatar"', "")))
    end)

    it("sanitizes bodies through the shared pipeline", function()
        local html = threadhtml.render(doc)
        -- imgref spans carry their source URL since the tap-to-view wave;
        -- the dormant EPUB path styles the span and ignores the attribute.
        assert.matches('<span class="imgref" src=', html, 1, true)
        assert.matches('[image: an image]', html, 1, true)
        assert.matches("%[spoiler%] a hidden spoiler text %[/spoiler%]", html)
        assert.matches("<br/>", html)
        assert.is_nil(html:find("<script"))
    end)

    it("closes the thread with the frog line at 3em", function()
        local html = threadhtml.render(doc)
        assert.matches('<div class="endmarker">The frog says: GET OUT%.</div>', html)
        assert.matches("div%.endmarker { text%-align: center; line%-height: 3em", threadhtml.css)
    end)

    it("lays the header out as a two-cell table (mupdf ignores floats)", function()
        local html = threadhtml.render(doc)
        assert.matches('<table class="userhead">', html)
        assert.matches('<td class="avatarcell"><img class="avatar" src="avatars/103%.gif"', html)
        local css = threadhtml.css
        assert.matches("table%.userhead { width: 100%%", css)
        assert.matches("td%.avatarcell { width: 3em", css)
        -- no float: mupdf ignores it
        assert.is_nil(css:find("float"))
    end)

    it("carries the Awful design tokens in the stylesheet", function()
        local css = threadhtml.css
        assert.matches("div%.post { display: block; border%-top: 1px solid #ccc; border%-bottom: 1px solid #ccc", css)
        assert.matches("div%.post%.seen { background%-color: #e8e8e8", css)
        assert.matches("img%.avatar { width: 2%.5em", css)
        assert.matches("div%.username { font%-size: 1%.1em; font%-weight: bold", css)
        assert.matches("div%.postdate { font%-size: 0%.8em; color: #999", css)
        assert.matches("font%-family: sans%-serif", css)
        -- no line-height locks anywhere except the 3em end marker
        assert.equals(1, select(2, css:gsub("line%-height", "")))
    end)

    it("withholds the frog on non-last pages", function()
        doc.last_page = false
        local html = threadhtml.render(doc)
        assert.is_nil(html:find("endmarker"))
    end)

    it("renders a document with no avatars at all", function()
        doc.avatars = nil
        local html = threadhtml.render(doc)
        assert.is_nil(html:find('class="avatar"'))
        assert.matches('<div class="username">Poster Three', html)
    end)
end)
