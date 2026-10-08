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

    it("captures raw dates", function()
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
