require("spec.stubs")

local threadlistparser = require("saforums.threadlistparser")

local function fixture(name)
    local handle = io.open("spec/fixtures/" .. name, "r")
    local content = handle:read("*a")
    handle:close()
    return content
end

describe("threadlistparser", function()
    local result

    before_each(function()
        result = threadlistparser.parse(fixture("threadlist.html"))
    end)

    it("finds every thread row, announcements kept apart", function()
        assert.equals(4, #result.threads)
        assert.equals(1, #result.announcements)
    end)

    it("extracts the page identity", function()
        assert.equals("46", result.forum_id)
        assert.is_false(result.can_post)
    end)

    it("extracts pagination attributes", function()
        assert.equals(1, result.pagination.current_page)
        assert.equals(2, result.pagination.total_pages)
        assert.equals("forumdisplay.php?forumid=46", result.pagination.base_url)
        assert.equals(40, result.pagination.per_page)
    end)

    it("parses ids, titles, and authors", function()
        local first = result.threads[1]
        assert.equals("4231001", first.id)
        assert.equals("Fixture Rules: Read Before Posting (sticky)", first.title)
        assert.equals("Poster One", first.author_name)
        assert.equals("101", first.author_id)
    end)

    it("marks rows with an x link as fully read", function()
        assert.is_nil(result.threads[2].unread_count)
        assert.is_true(result.threads[2].is_read)
    end)

    it("recognizes never-opened threads by the missing lastseen cell", function()
        local never = result.threads[4]
        assert.equals("4231004", never.id)
        assert.is_nil(never.unread_count)
        assert.is_false(never.is_read)
    end)

    it("parses announcement rows into the announcement list", function()
        local announcement = result.announcements[1]
        assert.equals("Fixture Announcement: The Site Is On Fire (announcement)", announcement.title)
        assert.equals("Admin Person", announcement.author_name)
        assert.equals("1", announcement.author_id)
        assert.equals("09:00 AM Oct 1, 2026", announcement.last_post_date)
        assert.is_true(announcement.announcement)
    end)

    it("parses the rating numbers out of the img title", function()
        assert.equals(3, result.threads[1].rating_votes)
        assert.equals(4.0, result.threads[1].rating_average)
        assert.is_nil(result.threads[2].rating_votes)
    end)

    it("reads the forum's filterable tag list", function()
        assert.equals(2, #result.thread_tags)
        assert.equals("264", result.thread_tags[1].id)
        assert.equals("Ask / Tell", result.thread_tags[1].name)
        assert.equals("11", result.thread_tags[2].id)
        assert.equals("Discussion", result.thread_tags[2].name)
    end)

    it("distinguishes sticky, closed, and starred rows", function()
        assert.is_true(result.threads[1].sticky)
        assert.is_false(result.threads[1].closed)
        assert.is_true(result.threads[2].closed)
        assert.is_false(result.threads[2].sticky)
        assert.equals(1, result.threads[1].star)
        assert.is_nil(result.threads[2].star)
        assert.is_nil(result.threads[3].star)
    end)

    it("extracts reply counts and last-post facts", function()
        assert.equals(11, result.threads[1].replies)
        assert.equals(40, result.threads[2].replies)
        assert.equals("Poster Three", result.threads[1].last_post_author)
        assert.equals("09:15 PM Oct 1, 2026", result.threads[1].last_post_date)
        assert.equals("10:15 PM Oct 7, 2026", result.threads[3].last_post_date)
    end)

    it("keeps thread icons with their posticon id", function()
        assert.equals("264", result.threads[1].icon_id)
        assert.matches("td264%.gif$", result.threads[1].icon_src)
    end)

    it("survives an empty page", function()
        local empty = threadlistparser.parse("<html><body data-forum='46'></body></html>")
        assert.equals(0, #empty.threads)
        assert.is_nil(empty.pagination)
    end)
end)
