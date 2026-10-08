require("spec.stubs")

local Archiver = require("ffi/archiver")
local epubbuilder = require("saforums.epubbuilder")
local postspageparser = require("saforums.postspageparser")

local function fixture(name)
    local handle = io.open("spec/fixtures/" .. name, "r")
    local content = handle:read("*a")
    handle:close()
    return content
end

describe("epubbuilder", function()
    local page

    before_each(function()
        Archiver.Writer.instances = {}
        local result = postspageparser.parse(fixture("postspage.html"))
        page = { number = 1, posts = result.posts }
    end)

    local function build(tmp_suffix)
        local path = "/tmp/saforums-test/thread-4231003.epub" .. (tmp_suffix or "")
        local ok = epubbuilder.build(path, {
            thread_id = "4231003",
            title = "The Thread You Are Currently Reading (fixture)",
            pages = { page },
        })
        return ok, Archiver.Writer.instances[1]
    end

    it("refuses to build an empty book", function()
        local ok = epubbuilder.build("/tmp/saforums-test/x.epub", {
            thread_id = "1", title = "t", pages = {},
        })
        assert.is_false(ok)
        assert.equals(0, #Archiver.Writer.instances)
    end)

    it("opens the container as an epub at a .tmp path", function()
        local ok, epub = build()
        assert.is_true(ok)
        assert.equals("epub", epub.opened_kind)
        assert.matches("%.tmp$", epub.opened_path)
        assert.is_true(epub.closed)
    end)

    it("renames the .tmp onto the final path when the archiver is clean", function()
        local renamed
        local real_rename = os.rename
        os.rename = function(from, to)
            renamed = { from, to }
            return true
        end
        local ok, epub = build()
        os.rename = real_rename
        assert.is_true(ok)
        assert.is_nil(epub.err)
        assert.equals(epub.opened_path, renamed[1])
        assert.equals("/tmp/saforums-test/thread-4231003.epub", renamed[2])
    end)

    it("fails the build when the archiver reports an error", function()
        local Writer = Archiver.Writer
        local real_close = Writer.close
        Writer.close = function(self)
            self.closed = true
            self.err = "boom"
        end
        local ok = epubbuilder.build("/tmp/saforums-test/thread-4231003.epub", {
            thread_id = "4231003",
            title = "t",
            pages = { page },
        })
        Writer.close = real_close
        assert.is_false(ok)
    end)

    it("stores the mimetype first, uncompressed", function()
        local _, epub = build()
        assert.equals("application/epub+zip", epub.entries["mimetype"])
        assert.equals("store", epub.entry_compression["mimetype"])
        assert.equals("deflate", epub.entry_compression["META-INF/container.xml"])
    end)

    it("writes the container, opf, toc, and one chapter per page", function()
        local _, epub = build()
        assert.is_truthy(epub.entries["META-INF/container.xml"]:find("OEBPS/content%.opf"))
        local opf = epub.entries["OEBPS/content.opf"]
        assert.matches("<dc:title>The Thread You Are Currently Reading %(fixture%)</dc:title>", opf)
        assert.matches('unique%-identifier="bookid"', opf)
        assert.matches('idref="page1"', opf)
        assert.matches('saforums%-thread%-4231003', epub.entries["OEBPS/toc.ncx"])
        assert.is_truthy(epub.entries["OEBPS/page1.xhtml"])
    end)

    describe("sanitize_body", function()
        it("strips script and style blocks entirely", function()
            local out = epubbuilder.sanitize_body(
                "keep<script>alert(1)</script>me<style>p{}</style>please")
            assert.equals("keepmeplease", out)
        end)

        it("replaces images with bracketed placeholders", function()
            local out = epubbuilder.sanitize_body(
                'before<img src="https://i.fixture.invalid/photos/xyz.png" alt="a chart">after')
            assert.equals('before<span class="imgref">[image: a chart]</span>after', out)
        end)

        it("falls back to the filename when there is no alt", function()
            local out = epubbuilder.sanitize_body('<img src="https://h.invalid/x/pic.jpg">')
            assert.matches("%[image: pic%.jpg%]", out)
        end)

        it("marks spoiler spans", function()
            local out = epubbuilder.sanitize_body('<span class="bbc-spoiler">hidden words</span>')
            assert.matches('%[spoiler%] hidden words %[/spoiler%]', out)
            assert.matches('class="spoiler"', out)
        end)

        it("closes void tags for XHTML", function()
            local out = epubbuilder.sanitize_body("one<br>two<hr>three")
            assert.equals("one<br/>two<hr/>three", out)
        end)

        it("sends named entities numeric and escapes bare ampersands", function()
            local out = epubbuilder.sanitize_body("a&nbsp;b&amp;c & d&#233;")
            assert.equals("a&#160;b&amp;amp;c &amp; d&#233;", out)
        end)

        it("keeps blockquotes and links intact", function()
            local out = epubbuilder.sanitize_body('<blockquote><a href="https://fixture.invalid">link</a></blockquote>')
            assert.matches('<blockquote><a href="https://fixture.invalid">link</a></blockquote>', out, 1, true)
        end)
    end)

    it("escapes metadata and headers into the chapters", function()
        local _, epub = build()
        local chapter = epub.entries["OEBPS/page1.xhtml"]
        assert.matches('<span class="postauthor">Poster Three</span>', chapter)
        assert.matches("&#183; Oct 5, 2026 12:30", chapter)
        assert.is_truthy(chapter:find('xmlns="http://www.w3.org/1999/xhtml"'))
    end)
end)
