require("spec.stubs")

local posthtml = require("saforums.posthtml")

describe("posthtml sanitizer", function()
    it("keeps images as imgref spans carrying their source URL", function()
        local html = posthtml.sanitize_body('<img src="https://img.fixture.invalid/xyz.png" alt="an image">')
        assert.matches('<span class="imgref" src="https://img%.fixture%.invalid/xyz%.png">', html)
        assert.matches("%[image: an image%]", html)
    end)

    it("labels unlabeled images with the filename", function()
        local html = posthtml.sanitize_body('<img src="https://img.fixture.invalid/photo.jpg">')
        assert.matches("%[image: photo%.jpg%]", html)
    end)

    it("collapses smilies to their typed code", function()
        local html = posthtml.sanitize_body(
            '<img src="https://fi.somethingawful.com/smilies/posting/smile.gif" title=":)" alt="">')
        assert.equals(":)", html)
    end)

    it("drops smilies without a typed code, keeps real images on smilie hosts", function()
        assert.equals("", posthtml.sanitize_body(
            '<img src="https://fi.somethingawful.com/smilies/posting/smile.gif" alt="">'))
        -- avatars live on the same host, outside the smilie trees
        assert.matches("imgref", posthtml.sanitize_body(
            '<img src="https://fi.somethingawful.com/avatars/103.gif" alt="">'))
    end)

    it("leaves labeled links alone", function()
        local html = posthtml.sanitize_body('<a href="https://fixture.invalid/page">a page</a>')
        assert.matches("<a%s[^>]*>a page</a>", html)
    end)

    it("rewrites bare tweet links into tweet placeholders", function()
        local html = posthtml.sanitize_body(
            '<a href="https://twitter.com/someone/status/1234567890">https://twitter.com/someone/status/1234567890</a>')
        assert.matches('<span class="embedref">%[tweet: @someone%]</span>', html)
    end)

    it("rewrites bare bluesky links into placeholders", function()
        local html = posthtml.sanitize_body(
            '<a href="https://bsky.app/profile/someone/post/abc123">https://bsky.app/profile/someone/post/abc123</a>')
        assert.matches("%[bluesky post%]", html)
    end)

    it("rewrites bare youtube links into video placeholders", function()
        local html = posthtml.sanitize_body(
            '<a href="https://www.youtube.com/watch?v=FIXTURE01">https://www.youtube.com/watch?v=FIXTURE01</a>')
        assert.matches("%[video: youtube%]", html)
    end)

    it("rewrites bare image links into fetchable linked-image blocks", function()
        local html = posthtml.sanitize_body(
            '<a href="https://img.fixture.invalid/pic.png">https://img.fixture.invalid/pic.png</a>')
        assert.matches('<span class="imgref" src="https://img%.fixture%.invalid/pic%.png">', html)
        assert.matches("%[linked image: pic%.png%]", html)
    end)

    it("labels flash-era video embeds before the object strip eats them", function()
        local html = posthtml.sanitize_body(
            '<div class="bbcode_video"><object><param name="movie" value="https://vimeo.com/moogaloop.swf?clip_id=42"></object></div>')
        assert.matches("%[video: vimeo%]", html)
        assert.falsy(html:find("<object>"))

        local other = posthtml.sanitize_body(
            '<div class="bbcode_video"><object><param name="movie" value="https://media.fixture.invalid/x.swf"></object></div>')
        assert.matches("%[video%]", other)
    end)

    it("keeps the marked spoiler span form for the reading surface", function()
        local html = posthtml.sanitize_body('<span class="bbc-spoiler">hidden words</span>')
        assert.matches('<span class="spoiler">%[spoiler%] hidden words %[/spoiler%]</span>', html)
    end)

    it("still strips scripts and closes void tags", function()
        local html = posthtml.sanitize_body('words<script>evil()</script>more<br>tail')
        assert.falsy(html:find("evil"))
        assert.matches("<br/>", html)
    end)
end)

describe("posthtml smilie detection", function()
    it("knows the site's smilie trees", function()
        assert.is_true(posthtml.is_smilie_src("https://fi.somethingawful.com/smilies/posting/smile.gif"))
        assert.is_true(posthtml.is_smilie_src("https://i.somethingawful.com/emot/umad.gif"))
        assert.is_true(posthtml.is_smilie_src("https://forumimages.somethingawful.com/images/smile.png"))
        assert.is_false(posthtml.is_smilie_src("https://fi.somethingawful.com/avatars/103.gif"))
        assert.is_false(posthtml.is_smilie_src("https://img.fixture.invalid/smilies/fake.gif"))
    end)
end)
