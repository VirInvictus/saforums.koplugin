require("spec.stubs")

local postspageparser = require("saforums.postspageparser")

local function fixture(name)
    local handle = io.open("spec/fixtures/" .. name, "r")
    local content = handle:read("*a")
    handle:close()
    return content
end

describe("postspageparser", function()
    local result

    before_each(function()
        result = postspageparser.parse(fixture("postspage.html"))
    end)

    it("extracts the page identity", function()
        assert.equals("4231003", result.thread_id)
        assert.equals("46", result.forum_id)
        assert.equals("The Thread You Are Currently Reading (fixture)", result.title)
        assert.is_false(result.closed)
    end)

    it("finds every post in order", function()
        assert.equals(3, #result.posts)
        assert.equals("510000001", result.posts[1].id)
        assert.equals("510000003", result.posts[3].id)
    end)

    it("keeps the 1-based post index", function()
        assert.equals(1, result.posts[1].index)
        assert.equals(3, result.posts[3].index)
    end)

    it("separates authors from their ids", function()
        assert.equals("Poster Three", result.posts[1].author_name)
        assert.equals("103", result.posts[1].author_id)
        assert.equals("Poster Five", result.posts[3].author_name)
        assert.equals("105", result.posts[3].author_id)
    end)

    it("flags the original poster", function()
        assert.is_false(result.posts[1].author_is_op)
        assert.is_true(result.posts[3].author_is_op)
    end)

    it("reads author roles from the class list", function()
        assert.is_true(result.posts[2].author_is_mod)
        assert.is_true(result.posts[2].author_is_platinum)
        assert.is_false(result.posts[2].author_is_admin)
        assert.is_false(result.posts[1].author_is_mod)
    end)

    it("records seen state per post", function()
        assert.is_true(result.posts[1].seen)
        assert.is_true(result.posts[2].seen)
        assert.is_false(result.posts[3].seen)
    end)

    it("keeps raw post bodies with entities intact", function()
        local body = result.posts[1].body_html
        assert.matches("caf&eacute; word", body, 1, true)
        assert.matches("<b>bold</b>", body, 1, true)
    end)

    it("captures raw dates with the post-number prefix stripped", function()
        assert.equals("Oct 5, 2026 12:30", result.posts[1].date_raw)
    end)

    it("detects closed threads from the reply button", function()
        local closed = postspageparser.parse([[
        <html><body data-forum="46" data-thread="4231002">
        <div class="breadcrumbs"><a href="showthread.php?threadid=4231002">Locked</a></div>
        <ul class="postbuttons"><a href="newreply.php?action=newreply&amp;threadid=4231002"><img src="https://fi.fixture.invalid/buttons/closed.gif"></a></ul>
        </body></html>]])
        assert.is_true(closed.closed)
        assert.equals("Locked", closed.title)
    end)
end)

describe("postspageparser author sidebar", function()
    local result = postspageparser.parse(fixture("postspage.html"))

    it("pulls the avatar source from the userinfo sidebar", function()
        assert.equals("https://fi.fixture.invalid/avatars/103.gif", result.posts[1].avatar_src)
        assert.equals("https://fi.fixture.invalid/avatars/104.png", result.posts[2].avatar_src)
        assert.is_nil(result.posts[3].avatar_src)
    end)

    it("reads custom titles as clean text with raw HTML kept for avatar mining", function()
        assert.equals("Senior Fixture", result.posts[2].custom_title)
        assert.matches("<img", result.posts[2].custom_title_html)
        assert.is_nil(result.posts[3].custom_title)
    end)

    it("keeps the regdate", function()
        assert.equals("Mar 12, 2011", result.posts[1].regdate)
    end)
end)

describe("postspageparser date cleaning", function()
    it("strips the permalink and any separator junk before the date", function()
        local page = [[<html><body data-thread="1" data-forum="2">
        <table class="post" id="post9" data-idx="1">
        <tr><td class="userinfo"><dl class="userinfo"><dt class="author">A</dt></dl></td>
        <td class="postbody">x</td></tr>
        <tr><td class="postdate"><a href="#1">#1</a> � Oct 5, 2026 12:30</td></tr>
        </table></body></html>]]
        local result = postspageparser.parse(page)
        assert.equals("Oct 5, 2026 12:30", result.posts[1].date_raw)
    end)
end)

describe("postspageparser pagination", function()
    it("extracts page identity from div.pages", function()
        local result = postspageparser.parse(fixture("postspage.html"))
        assert.equals(1, result.pagination.current_page)
        assert.equals(7, result.pagination.total_pages)
        assert.equals("showthread.php?threadid=4231003", result.pagination.base_url)
        assert.equals(40, result.pagination.per_page)
    end)
end)
